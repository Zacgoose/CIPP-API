function Start-UpdatePermissionsOrchestrator {
    <#
    .SYNOPSIS
    Start the Update Permissions Orchestrator

    .FUNCTIONALITY
    Entrypoint
    #>
    [CmdletBinding(SupportsShouldProcess = $true)]
    param()

    try {
        Write-Information 'Updating Permissions'

        $PartnerTenant = @{
            'customerId'        = $env:TenantID
            'defaultDomainName' = 'PartnerTenant'
            'displayName'       = '*Partner Tenant'
        }

        $TenantList = Get-Tenants -IncludeAll | Where-Object { $_.Excluded -eq $false }

        $Tenants = [System.Collections.Generic.List[object]]::new()
        foreach ($Tenant in $TenantList) {
            $Tenants.Add($Tenant)
        }

        if ($Tenants.customerId -notcontains $env:TenantID) {
            $Tenants.Add($PartnerTenant)
        }

        $CPVTable = Get-CIPPTable -TableName cpvtenants
        $CPVRows = Get-CIPPAzDataTableEntity @CPVTable
        $LastCPV = ($CPVRows | Sort-Object -Property Timestamp -Descending | Select-Object -First 1).Timestamp.DateTime
        Write-Information "CPV last updated at $LastCPV"

        $AccessChecksTable = Get-CIPPTable -TableName AccessChecks

        $SAMPermissions = Get-CIPPSamPermissions
        Write-Information "SAM Permissions last updated at $($SAMPermissions.Timestamp)"

        $SAMRolesTable = Get-CIPPTable -TableName SAMRoles
        $SAMRoles = Get-CIPPAzDataTableEntity @SAMRolesTable
        Write-Information "SAM Roles last updated at $($SAMRoles.Timestamp.DateTime)"

        $Tenants = $Tenants | ForEach-Object {
            $CPVRow = $CPVRows | Where-Object -Property Tenant -EQ $_.customerId

            # Determine retry interval based on last status
            # No status or Failed status: retry after 1 day, Success: retry after 7 days
            $RetryDays = if (!$CPVRow.LastStatus -or $CPVRow.LastStatus -eq 'Failed') { -1 } else { -7 }
            $NeedsRetry = $CPVRow.Timestamp.DateTime -le (Get-Date).AddDays($RetryDays).ToUniversalTime()

            $NeedsUpdate = !$CPVRow -or $env:ApplicationID -notin $CPVRow.applicationId -or $SAMPermissions.Timestamp -gt $CPVRow.Timestamp.DateTime -or $NeedsRetry -or !$_.defaultDomainName -or ($SAMRoles.Timestamp.DateTime -gt $CPVRow.Timestamp.DateTime -and ($SAMRoles.Tenants -contains $_.defaultDomainName -or $SAMRoles.Tenants.value -contains $_.defaultDomainName -or $SAMRoles.Tenants -contains 'AllTenants' -or $SAMRoles.Tenants.value -contains 'AllTenants'))

            if (!$NeedsUpdate -and $_.defaultDomainName -ne 'PartnerTenant') {
                try {
                    $null = Test-CIPPAccessTenant -Tenant $_.customerId
                    $TenantAccessCheck = Get-CIPPAzDataTableEntity @AccessChecksTable -Filter "PartitionKey eq 'TenantAccessChecks' and RowKey eq '$($_.customerId)'"
                    if ($TenantAccessCheck -and $TenantAccessCheck.Data) {
                        $TenantAccessData = $TenantAccessCheck.Data | ConvertFrom-Json -ErrorAction Stop
                        if ($TenantAccessData.PSObject.Properties.Name -contains 'CPVPermissionsStatus' -and $TenantAccessData.CPVPermissionsStatus -eq $false) {
                            $NeedsUpdate = $true
                        }
                    }
                } catch {
                }
            }

            if ($NeedsUpdate) {
                $_
            }
        }
        $TenantCount = ($Tenants | Measure-Object).Count

        if ($TenantCount -gt 0) {
            Write-Information "Found $TenantCount tenants that require permissions update"
            $Queue = New-CippQueueEntry -Name 'Update Permissions' -TotalTasks $TenantCount
            $TenantBatch = $Tenants | Select-Object defaultDomainName, customerId, displayName, @{n = 'FunctionName'; exp = { 'UpdatePermissionsQueue' } }, @{n = 'QueueId'; exp = { $Queue.RowKey } }, @{n = 'RunAccessCheck'; exp = { $true } }
            $InputObject = [PSCustomObject]@{
                OrchestratorName = 'UpdatePermissionsOrchestrator'
                Batch            = @($TenantBatch)
            }
            Start-NewOrchestration -FunctionName 'CIPPOrchestrator' -InputObject ($InputObject | ConvertTo-Json -Depth 5 -Compress)
        } else {
            Write-Information 'No tenants require permissions update'
        }
    } catch {}
}
