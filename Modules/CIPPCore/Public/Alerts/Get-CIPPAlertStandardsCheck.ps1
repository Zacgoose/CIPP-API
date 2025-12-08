function Get-CIPPAlertStandardsCheck {
    <#
    .FUNCTIONALITY
        Entrypoint
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $false)]
        [Alias('input')]
        $InputValue,
        [Parameter(Mandatory = $true)]
        [string]$TenantFilter
    )

    try {
        # Get the interval in days from InputValue, default to 1 day if not specified
        $IntervalDays = if ($InputValue -and [int]$InputValue -gt 0) {
            [int]$InputValue
        } else {
            1
        }

        # Calculate the partition keys to check based on the interval
        $PartitionKeys = for ($i = 0; $i -lt $IntervalDays; $i++) {
            (Get-Date).AddDays(-$i).ToString('yyyyMMdd')
        }

        # Get the standards alerts table
        $Table = Get-CIPPTable -tablename CippStandardsAlerts

        # Retrieve all standards check alerts for this tenant within the interval
        $AllAlerts = [System.Collections.Generic.List[object]]::new()
        foreach ($PartitionKey in $PartitionKeys) {
            $Filter = "PartitionKey eq '$PartitionKey' and tenant eq '$TenantFilter'"
            $Alerts = Get-CIPPAzDataTableEntity @Table -Filter $Filter
            if ($Alerts) {
                foreach ($Alert in $Alerts) {
                    $AllAlerts.Add($Alert)
                }
            }
        }

        # Format the alerts for output
        $AlertData = $AllAlerts | ForEach-Object {
            try {
                $ObjectData = if ($_.object) {
                    $_.object | ConvertFrom-Json -ErrorAction SilentlyContinue
                } else {
                    $null
                }
            } catch {
                $ObjectData = $_.object
            }

            [PSCustomObject]@{
                Message      = $_.message
                StandardName = $_.standardName
                StandardId   = $_.standardId
                Tenant       = $_.tenant
                Timestamp    = $_.Timestamp
                Object       = $ObjectData
            }
        }

        # Only write to alert trace if we have alerts to report
        if ($AlertData) {
            Write-AlertTrace -cmdletName $MyInvocation.MyCommand -tenantFilter $TenantFilter -data $AlertData
        }

    } catch {
        Write-AlertMessage -tenant $TenantFilter -message "Standards Check Alert Error: $(Get-NormalizedError -message $_.Exception.message)"
    }
}
