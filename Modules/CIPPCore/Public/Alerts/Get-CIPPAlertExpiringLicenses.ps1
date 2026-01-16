function Get-CIPPAlertExpiringLicenses {
    <#
    .FUNCTIONALITY
        Entrypoint
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $false)]
        [Alias('input')]
        $InputValue,
        
        [Parameter(Mandatory = $false)]
        [int]$ExpiringLicensesDays,
        
        [Parameter(Mandatory = $false)]
        [bool]$ExpiringLicensesUnassignedOnly,
        
        $TenantFilter
    )
    try {
        # Parse input parameters - support both direct parameters and InputValue for backward compatibility
        # Priority: Direct parameters > InputValue properties > Defaults
        
        # Handle DaysThreshold
        if ($PSBoundParameters.ContainsKey('ExpiringLicensesDays')) {
            # Direct parameter takes priority
            $DaysThreshold = $ExpiringLicensesDays
        } elseif ($InputValue -is [hashtable] -or $InputValue -is [PSCustomObject]) {
            $DaysThreshold = if ($InputValue.ExpiringLicensesDays) { [int]$InputValue.ExpiringLicensesDays } else { 30 }
        } elseif ($InputValue) {
            # Backward compatibility: if InputValue is a simple value, treat it as days threshold
            $DaysThreshold = [int]$InputValue
        } else {
            $DaysThreshold = 30
        }
        
        # Handle UnassignedOnly
        if ($PSBoundParameters.ContainsKey('ExpiringLicensesUnassignedOnly')) {
            # Direct parameter takes priority
            $UnassignedOnly = $ExpiringLicensesUnassignedOnly
        } elseif ($InputValue -is [hashtable] -or $InputValue -is [PSCustomObject]) {
            $UnassignedOnly = if ($null -ne $InputValue.ExpiringLicensesUnassignedOnly) { [bool]$InputValue.ExpiringLicensesUnassignedOnly } else { $false }
        } else {
            $UnassignedOnly = $false
        }

        $AlertData = Get-CIPPLicenseOverview -TenantFilter $TenantFilter | ForEach-Object {
            $UnassignedCount = [int]$_.CountAvailable

            # If unassigned only filter is enabled, skip licenses with no unassigned units
            if ($UnassignedOnly -and $UnassignedCount -le 0) {
                return
            }

            foreach ($Term in $TermData) {
                if ($Term.DaysUntilRenew -lt $DaysThreshold -and $Term.DaysUntilRenew -gt 0) {
                    $Message = if ($UnassignedOnly) {
                        "$($_.License) has $UnassignedCount unassigned license(s) expiring in $($Term.DaysUntilRenew) days. The estimated term is $($Term.Term)"
                    } else {
                        "$($_.License) will expire in $($Term.DaysUntilRenew) days. The estimated term is $($Term.Term)"
                    }

                    Write-Host $Message
                    [PSCustomObject]@{
                        Message        = $Message
                        License        = $_.License
                        SkuId          = $_.skuId
                        DaysUntilRenew = $Term.DaysUntilRenew
                        Term           = $Term.Term
                        Status         = $Term.Status
                        TotalLicenses  = $Term.TotalLicenses
                        CountUsed      = $_.CountUsed
                        CountAvailable = $UnassignedCount
                        NextLifecycle  = $Term.NextLifecycle
                        Tenant         = $_.Tenant
                    }
                }
            }
        }
        Write-AlertTrace -cmdletName $MyInvocation.MyCommand -tenantFilter $TenantFilter -data $AlertData

    } catch {
    }
}
