function Get-CIPPAlertSharepointQuota {
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
        [int]$PercentageThreshold,
        
        $TenantFilter
    )
    try {
        $SharePointInfo = Get-SharePointAdminLink -Public $false -tenantFilter $TenantFilter
        $extraHeaders = @{
            'Accept' = 'application/json'
        }
        $sharepointQuota = (New-GraphGetRequest -extraHeaders $extraHeaders -scope "$($SharePointInfo.AdminUrl)/.default" -tenantid $TenantFilter -uri "$($SharePointInfo.AdminUrl)/_api/StorageQuotas()?api-version=1.3.2")
    } catch {
        return
    }
    if ($sharepointQuota) {
        # Handle threshold - support both direct parameter and InputValue for backward compatibility
        if ($PSBoundParameters.ContainsKey('PercentageThreshold')) {
            $Value = $PercentageThreshold
        } elseif ([int]$InputValue -gt 0) {
            $Value = [int]$InputValue
        } else {
            $Value = 90
        }
        $UsedStoragePercentage = [int](($sharepointQuota.GeoUsedStorageMB / $sharepointQuota.TenantStorageMB) * 100)
        if ($UsedStoragePercentage -gt $Value) {
            $AlertData = [PSCustomObject]@{
                UsedStoragePercentage = $UsedStoragePercentage
                StorageUsed           = ([math]::Round($sharepointQuota.GeoUsedStorageMB / 1024, 2))
                StorageQuota          = ([math]::Round($sharepointQuota.TenantStorageMB / 1024, 2))
                AlertQuotaThreshold   = $Value
                Tenant                = $TenantFilter
            }
            Write-AlertTrace -cmdletName $MyInvocation.MyCommand -tenantFilter $TenantFilter -data $AlertData
        }
    }
}
