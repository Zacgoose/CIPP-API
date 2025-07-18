using namespace System.Net

Function Invoke-ExecModifyMBPerms {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Exchange.Mailbox.ReadWrite
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    Write-LogMessage -headers $Request.Headers -API $APINAME -message 'Accessed this API' -Sev 'Debug'

    # Extract the mailbox requests - handle both bulk and single formats
    $MailboxRequests = $null
    $Results = [System.Collections.ArrayList]::new()

    # Check if this is the new bulk format
    if ($request.body.mailboxRequests) {
        $MailboxRequests = $request.body.mailboxRequests
        Write-LogMessage -headers $Request.Headers -API $APINAME -message "Processing bulk format with $($MailboxRequests.Count) mailboxes" -Sev 'Debug'
    }
    # Check if this is the legacy single mailbox format
    elseif ($request.body.userID -and $request.body.permissions) {
        # Convert single request to array format for unified processing
        $MailboxRequests = @([PSCustomObject]@{
            userID = $request.body.userID
            tenantFilter = $request.body.tenantFilter
            permissions = $request.body.permissions
        })
        Write-LogMessage -headers $Request.Headers -API $APINAME -message "Processing legacy single mailbox format for $($request.body.userID)" -Sev 'Debug'
    }

    # Debug logging
    Write-LogMessage -headers $Request.Headers -API $APINAME -message "Request body keys: $($request.body.PSObject.Properties.Name -join ', ')" -Sev 'Debug'

    if (-not $MailboxRequests -or $MailboxRequests.Count -eq 0) {
        Write-LogMessage -headers $Request.Headers -API $APINAME -message 'No mailbox requests provided in either format' -Sev 'Error'
        Write-LogMessage -headers $Request.Headers -API $APINAME -message "Full request body: $($request.body | ConvertTo-Json -Depth 5)" -Sev 'Debug'
        $body = [pscustomobject]@{'Results' = @("No mailbox requests provided. Request body keys: $($request.body.PSObject.Properties.Name -join ', ')") }
        Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::BadRequest
            Body       = $Body
        })
        return
    }

    # Get the tenant from the first request (assuming all are same tenant)
    $TenantFilter = $MailboxRequests[0].tenantFilter

    Write-LogMessage -headers $Request.Headers -API $APINAME -message "Processing bulk permission changes for $($MailboxRequests.Count) mailboxes" -Sev 'Info' -tenant $TenantFilter

    # Build cmdlet array for bulk processing
    $CmdletArray = [System.Collections.ArrayList]::new()
    $UserLookupCache = @{}

    foreach ($MailboxRequest in $MailboxRequests) {
        $Username = $MailboxRequest.userID
        $Permissions = $MailboxRequest.permissions

        if ([string]::IsNullOrEmpty($Username)) {
            $null = $Results.Add("Skipped mailbox with missing userID")
            continue
        }

        # Cache user lookups to avoid repeated API calls
        if (-not $UserLookupCache.ContainsKey($Username)) {
            try {
                $UserLookupCache[$Username] = (New-GraphGetRequest -uri "https://graph.microsoft.com/beta/users/$($Username)" -tenantid $TenantFilter).id
            }
            catch {
                Write-LogMessage -headers $Request.Headers -API $APINAME -message "Could not find user $($Username): $($_.Exception.Message)" -Sev 'Error' -tenant $TenantFilter
                $null = $Results.Add("Could not find user $($Username): $($_.Exception.Message)")
                continue
            }
        }
        $UserId = $UserLookupCache[$Username]

        # Convert permissions to array format if needed
        if ($Permissions -is [PSCustomObject]) {
            if ($Permissions.PSObject.Properties.Name -match '^\d+$') {
                $Permissions = $Permissions.PSObject.Properties.Value
            }
            else {
                $Permissions = @($Permissions)
            }
        }

        foreach ($Permission in $Permissions) {
            $PermissionLevels = $Permission.PermissionLevel
            $Modification = $Permission.Modification
            $AutoMap = if ($Permission.PSObject.Properties.Name -contains 'AutoMap') { $Permission.AutoMap } else { $true }

            # Handle multiple permission levels separated by commas
            if ($PermissionLevels -like "*,*") {
                $PermissionLevelArray = $PermissionLevels -split ',' | ForEach-Object { $_.Trim() }
            }
            else {
                $PermissionLevelArray = @($PermissionLevels.Trim())
            }

            # Handle UserID as array of objects or single value
            $TargetUsers = if ($Permission.UserID -is [array]) {
                $Permission.UserID | ForEach-Object {
                    if ($_ -is [PSCustomObject] -and $_.value) {
                        $_.value
                    }
                    elseif ($_ -is [string]) {
                        $_
                    }
                    else {
                        $_.ToString()
                    }
                }
            }
            else {
                if ($Permission.UserID -is [PSCustomObject] -and $Permission.UserID.value) {
                    @($Permission.UserID.value)
                }
                else {
                    @($Permission.UserID)
                }
            }

            foreach ($TargetUser in $TargetUsers) {
                foreach ($PermissionLevel in $PermissionLevelArray) {

                    # Create cmdlet object for bulk processing
                    $CmdletParams = @{}
                    $CmdletName = ""

                    switch ($PermissionLevel) {
                        'FullAccess' {
                            if ($Modification -eq 'Remove') {
                                $CmdletName = 'Remove-MailboxPermission'
                                $CmdletParams = @{
                                    Identity     = $UserId
                                    user         = $TargetUser
                                    accessRights = @('FullAccess')
                                    Confirm      = $false
                                }
                            }
                            else {
                                $CmdletName = 'Add-MailboxPermission'
                                $CmdletParams = @{
                                    Identity     = $UserId
                                    user         = $TargetUser
                                    accessRights = @('FullAccess')
                                    automapping  = $AutoMap
                                    Confirm      = $false
                                }
                            }
                        }
                        'SendAs' {
                            if ($Modification -eq 'Remove') {
                                $CmdletName = 'Remove-RecipientPermission'
                                $CmdletParams = @{
                                    Identity     = $UserId
                                    Trustee      = $TargetUser
                                    accessRights = @('SendAs')
                                    Confirm      = $false
                                }
                            }
                            else {
                                $CmdletName = 'Add-RecipientPermission'
                                $CmdletParams = @{
                                    Identity     = $UserId
                                    Trustee      = $TargetUser
                                    accessRights = @('SendAs')
                                    Confirm      = $false
                                }
                            }
                        }
                        'SendOnBehalf' {
                            $CmdletName = 'Set-Mailbox'
                            if ($Modification -eq 'Remove') {
                                $CmdletParams = @{
                                    Identity            = $UserId
                                    GrantSendonBehalfTo = @{
                                        '@odata.type' = '#Exchange.GenericHashTable'
                                        remove        = $TargetUser
                                    }
                                    Confirm             = $false
                                }
                            }
                            else {
                                $CmdletParams = @{
                                    Identity            = $UserId
                                    GrantSendonBehalfTo = @{
                                        '@odata.type' = '#Exchange.GenericHashTable'
                                        add           = $TargetUser
                                    }
                                    Confirm             = $false
                                }
                            }
                        }
                    }

                    if ($CmdletName) {
                        # Create cmdlet object for bulk request
                        $CmdletObj = [PSCustomObject]@{
                            CmdletInput = [PSCustomObject]@{
                                CmdletName = $CmdletName
                                Parameters = $CmdletParams
                            }
                            Mailbox = $Username
                            TargetUser = $TargetUser
                            Permission = $PermissionLevel
                            Action = $Modification
                        }
                        $null = $CmdletArray.Add($CmdletObj)
                    }
                }
            }
        }
    }

    if ($CmdletArray.Count -eq 0) {
        Write-LogMessage -headers $Request.Headers -API $APINAME -message 'No valid cmdlets to process' -Sev 'Warning' -tenant $TenantFilter
        $body = [pscustomobject]@{'Results' = @("No valid permission changes to process") }
        Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body       = $Body
        })
        return
    }

    try {
        Write-LogMessage -headers $Request.Headers -API $APINAME -message "Executing bulk request with $($CmdletArray.Count) cmdlets" -Sev 'Info' -tenant $TenantFilter

        # Execute bulk request
        $BulkResults = New-ExoBulkRequest -tenantid $TenantFilter -cmdletArray $CmdletArray

        # Process results
        foreach ($CmdletObj in $CmdletArray) {
            $mailbox = $CmdletObj.Mailbox
            $targetUser = $CmdletObj.TargetUser
            $permission = $CmdletObj.Permission
            $action = $CmdletObj.Action

            if ($action -eq 'Remove') {
                $null = $Results.Add("Removed $($targetUser) from $($mailbox) with $($permission) permissions")
            }
            else {
                if ($permission -eq 'FullAccess') {
                    $autoMapText = if ($CmdletObj.CmdletInput.Parameters.automapping) { "with automapping enabled" } else { "with automapping disabled" }
                    $null = $Results.Add("Granted $($targetUser) access to $($mailbox) Mailbox ($($permission)) $($autoMapText)")
                }
                else {
                    $null = $Results.Add("Granted $($targetUser) access to $($mailbox) with $($permission) permissions")
                }
            }
        }

        Write-LogMessage -headers $Request.Headers -API $APINAME -message "Successfully processed bulk mailbox permission changes" -Sev 'Info' -tenant $TenantFilter
    }
    catch {
        Write-LogMessage -headers $Request.Headers -API $APINAME -message "Error executing bulk request: $($_.Exception.Message)" -Sev 'Error' -tenant $TenantFilter
        $null = $Results.Add("Error executing bulk permission changes: $($_.Exception.Message)")
    }

    $body = [pscustomobject]@{'Results' = @($Results) }

    # Associate values to output bindings by calling 'Push-OutputBinding'.
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body       = $Body
        })
}
