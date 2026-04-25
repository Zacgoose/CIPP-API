function Start-DmarcOrchestrator {
    <#
    .SYNOPSIS
        Start the DMARC report processing orchestrator
    .DESCRIPTION
        Reads enrolled tenants from the DmarcConfig table, builds a batch of
        per-tenant activity jobs, and fans out to Push-DmarcProcessTenant.
    .FUNCTIONALITY
        Entrypoint
    #>
    [CmdletBinding(SupportsShouldProcess = $true)]
    param()

    try {
        # Load enrolled tenants from DmarcConfig table
        $DmarcConfigTable = Get-CIPPTable -tablename 'DmarcConfig'
        $EnrolledTenants = @(Get-CIPPAzDataTableEntity @DmarcConfigTable -Filter "PartitionKey eq 'DmarcTenant' and Status eq 'Active'")

        if ($EnrolledTenants.Count -eq 0) {
            Write-LogMessage -API 'DmarcProcessor' -message 'No tenants enrolled for DMARC processing' -sev Info
            return 0
        }

        $Queue = New-CippQueueEntry -Name 'DMARC Report Processor' -TotalTasks $EnrolledTenants.Count

        # Build batch — one job per enrolled tenant
        $Batch = foreach ($Tenant in $EnrolledTenants) {
            $Config = if ($Tenant.Config) { $Tenant.Config | ConvertFrom-Json -ErrorAction SilentlyContinue } else { $null }
            [PSCustomObject]@{
                FunctionName      = 'DmarcProcessTenant'
                TenantFilter      = $Tenant.RowKey
                MailboxAddress    = $Config.MailboxAddress ?? "dmarc-reports@$($Tenant.RowKey)"
                PostProcessAction = $Config.PostProcessAction ?? 'Move'
                QueueId           = $Queue.RowKey
                QueueName         = "DMARC: $($Tenant.RowKey)"
            }
        }

        $InputObject = [PSCustomObject]@{
            OrchestratorName = 'DmarcProcessor'
            Batch            = @($Batch)
            SkipLog          = $true
        }

        if ($PSCmdlet.ShouldProcess('DMARC Processor', 'Starting Orchestrator')) {
            Write-LogMessage -API 'DmarcProcessor' -message "Starting DMARC Processor for $($EnrolledTenants.Count) tenants" -sev Info
            return Start-CIPPOrchestrator -InputObject $InputObject
        }
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -API 'DmarcProcessor' -message "Could not start DMARC Processor: $($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage
        return $false
    }
}
