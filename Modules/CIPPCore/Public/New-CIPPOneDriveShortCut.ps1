function New-CIPPOneDriveShortCut {
    [CmdletBinding()]
    param (
        $Username,
        $UserId,
        $URL,
        $LibraryId,  # Add this parameter
        $TenantFilter,
        $APIName = 'Create OneDrive shortcut',
        $Headers
    )
    Write-Host "Received $Username and $UserId. We're using $URL and $TenantFilter"
    try {
        $SiteInfo = New-GraphGetRequest -uri 'https://graph.microsoft.com/beta/sites/' -tenantid $TenantFilter -asapp $true | Where-Object -Property weburl -EQ $URL

        if ($LibraryId) {
            # Get specific document library
            Write-Host "Getting specific library: $LibraryId"
            $DriveInfo = New-GraphGetRequest -uri "https://graph.microsoft.com/beta/sites/$($SiteInfo.id)/drive/$LibraryId" -tenantid $TenantFilter -asapp $true
            $ListItemUniqueId = $DriveInfo.SharePointIds
            $LibraryName = $DriveInfo.name
        } else {
            # Fallback to default Documents library
            Write-Host "Using default Documents library"
            $DriveInfo = New-GraphGetRequest -uri "https://graph.microsoft.com/beta/sites/$($SiteInfo.id)/drive?`$select=SharepointIds" -tenantid $TenantFilter -asapp $true
            $ListItemUniqueId = $DriveInfo.SharePointIds
            $LibraryName = 'Documents'
        }

        $body = [PSCustomObject]@{
            name                                = $LibraryName
            remoteItem                          = @{
                sharepointIds = @{
                    listId           = $($ListItemUniqueId.listid)
                    listItemUniqueId = 'root'
                    siteId           = $($ListItemUniqueId.siteId)
                    siteUrl          = $($ListItemUniqueId.siteUrl)
                    webId            = $($ListItemUniqueId.webId)
                }
            }
            '@microsoft.graph.conflictBehavior' = 'rename'
        } | ConvertTo-Json -Depth 10

        New-GraphPOSTRequest -method POST "https://graph.microsoft.com/beta/users/$Username/drive/root/children" -body $Body -tenantid $TenantFilter -asapp $true
        Write-LogMessage -API $APIName -headers $Headers -message "Created OneDrive shortcut called $LibraryName for $($Username)" -Sev 'info'
        return "Successfully created OneDrive Shortcut for $Username called $LibraryName"
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        $Result = "Could not add Onedrive shortcut to $Username : $($ErrorMessage.NormalizedError)"
        Write-LogMessage -headers $Headers -API $APIName -message $Result -Sev 'Error' -LogData $ErrorMessage
        throw $Result
    }
}
