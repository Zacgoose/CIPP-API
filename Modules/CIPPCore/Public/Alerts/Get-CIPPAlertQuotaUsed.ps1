function Get-CIPPAlertQuotaUsed {
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
        $AlertData = New-GraphGetRequest -uri "https://graph.microsoft.com/beta/reports/getMailboxUsageDetail(period='D7')?`$format=application/json" -tenantid $TenantFilter
    } catch {
        return
    }
    $OverQuota = $AlertData | ForEach-Object {
        if ([string]::IsNullOrEmpty($_.StorageUsedInBytes) -or [string]::IsNullOrEmpty($_.prohibitSendReceiveQuotaInBytes) -or $_.StorageUsedInBytes -eq 0 -or $_.prohibitSendReceiveQuotaInBytes -eq 0) { return }
        try {
            $PercentLeft = [math]::round(($_.storageUsedInBytes / $_.prohibitSendReceiveQuotaInBytes) * 100)
        } catch { $PercentLeft = 100 }
        
        # Handle threshold - support both direct parameter and InputValue for backward compatibility
        if ($PSBoundParameters.ContainsKey('PercentageThreshold')) {
            $Value = $PercentageThreshold
        } elseif ([int]$InputValue -gt 0) {
            $Value = [int]$InputValue
        } else {
            $Value = 90
        }
        if ($PercentLeft -gt $Value) {
            [PSCustomObject]@{
                Message                         = "$($_.userPrincipalName): Mailbox is more than $($value)% full. Mailbox is $PercentLeft% full"
                Owner                           = $_.userPrincipalName
                RecipientType                   = $_.recipientType
                UsagePercent                    = $PercentLeft
                StorageUsedInBytes              = $_.storageUsedInBytes
                ProhibitSendReceiveQuotaInBytes = $_.prohibitSendReceiveQuotaInBytes
                Tenant                          = $TenantFilter
            }
        }
    }
    Write-AlertTrace -cmdletName $MyInvocation.MyCommand -tenantFilter $TenantFilter -data $OverQuota
}
