function Invoke-ListOutdatedActiveSyncDevices {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Exchange.Mailbox.Read
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)
    
    # Interact with query parameters or the body of the request.
    $TenantFilter = $Request.Query.TenantFilter
    
    try {
        # Get all mobile devices for the tenant
        $AllDevices = New-ExoRequest -tenantid $TenantFilter -cmdlet 'Get-MobileDevice'
        
        # Filter for outdated ActiveSync devices (version < 16.1)
        # ActiveSync 16.1 was released in June 2016 and will be the minimum required version starting March 1, 2026
        $MinimumVersion = [version]'16.1'
        
        $OutdatedDevices = $AllDevices | Where-Object {
            # Check if device is using ActiveSync/EAS
            ($_.ClientType -eq 'EAS' -or $_.ClientType -match 'ActiveSync') -and 
            # Ensure ClientVersion exists
            $_.ClientVersion -and 
            # Check if version is less than 16.1
            ([version]$_.ClientVersion -lt $MinimumVersion)
        } | Sort-Object UserDisplayName | Select-Object @{ Name = 'userDisplayName'; Expression = { $_.UserDisplayName } },
        @{ Name = 'userPrincipalName'; Expression = { $_.UserPrincipalName } },
        @{ Name = 'deviceId'; Expression = { $_.DeviceId } },
        @{ Name = 'deviceModel'; Expression = { $_.DeviceModel } },
        @{ Name = 'clientType'; Expression = { $_.ClientType } },
        @{ Name = 'clientVersion'; Expression = { $_.ClientVersion } },
        @{ Name = 'deviceOS'; Expression = { $_.DeviceOS } },
        @{ Name = 'deviceFriendlyName'; Expression = { if ([string]::IsNullOrEmpty($_.DeviceFriendlyName)) { 'Unknown' } else { $_.DeviceFriendlyName } } },
        @{ Name = 'firstSyncTime'; Expression = { $_.FirstSyncTime } },
        @{ Name = 'lastSuccessSync'; Expression = { $_.LastSuccessSync } }
        
        $StatusCode = [HttpStatusCode]::OK
    } catch {
        $ErrorMessage = Get-NormalizedError -Message $_.Exception.Message
        $StatusCode = [HttpStatusCode]::Forbidden
        $OutdatedDevices = $ErrorMessage
    }
    
    return ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = @($OutdatedDevices)
        })
}
