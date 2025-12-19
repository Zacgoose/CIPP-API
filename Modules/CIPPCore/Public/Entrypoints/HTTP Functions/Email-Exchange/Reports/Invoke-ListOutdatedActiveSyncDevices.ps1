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
        # Filter for outdated ActiveSync devices (version < 16.1) using the ActiveSync switch
        # ActiveSync 16.1 was released in June 2016 and will be the minimum required version starting March 1, 2026
        # Using the -ActiveSync switch to filter on the Exchange server for better performance
        
        # Get mobile devices with ActiveSync filter
        $AllDevices = New-ExoRequest -tenantid $TenantFilter -cmdlet 'Get-MobileDevice' -cmdParams @{ActiveSync = $true}
        
        $MinimumVersion = [version]'16.1'
        
        # Client-side filtering for version comparison (as version comparison is not supported in OPATH)
        $OutdatedDevices = $AllDevices | Where-Object {
            # Ensure ClientVersion exists and can be parsed
            if (-not $_.ClientVersion) {
                return $false
            }
            # Safely parse and check if version is less than 16.1
            try {
                $deviceVersion = [version]$_.ClientVersion
                return ($deviceVersion -lt $MinimumVersion)
            } catch {
                # If version parsing fails, exclude the device
                return $false
            }
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
