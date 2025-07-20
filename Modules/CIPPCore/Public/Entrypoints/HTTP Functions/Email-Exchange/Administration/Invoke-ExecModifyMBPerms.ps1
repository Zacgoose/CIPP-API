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
    Write-Host "=== ExecModifyMBPerms Started ===" -ForegroundColor Yellow

    # Extract the mailbox requests - handle both bulk and single formats
    $MailboxRequests = $null
    $Results = [System.Collections.ArrayList]::new()

    Write-Host "Request body keys: $($request.body.PSObject.Properties.Name -join ', ')" -ForegroundColor Cyan
    Write-Host "Request body type: $($request.body.GetType().Name)" -ForegroundColor Cyan
    Write-Host "Request body content: $($request.body | ConvertTo-Json -Depth 3)" -ForegroundColor Cyan

    # Check if this is a direct array of mailbox requests (new format)
    if ($request.body -is [array]) {
        $MailboxRequests = $request.body
        Write-Host "Processing direct array format with $($MailboxRequests.Count) mailboxes" -ForegroundColor Green
        Write-LogMessage -headers $Request.Headers -API $APINAME -message "Processing direct array format with $($MailboxRequests.Count) mailboxes" -Sev 'Debug'
    }
    # Check if this is the bulk format with mailboxRequests property
    elseif ($request.body.mailboxRequests) {
        $MailboxRequests = $request.body.mailboxRequests
        Write-Host "Processing bulk format with $($MailboxRequests.Count) mailboxes" -ForegroundColor Green
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
        Write-Host "Processing legacy single mailbox format for $($request.body.userID)" -ForegroundColor Green
        Write-LogMessage -headers $Request.Headers -API $APINAME -message "Processing legacy single mailbox format for $($request.body.userID)" -Sev 'Debug'
    }

    if (-not $MailboxRequests -or $MailboxRequests.Count -eq 0) {
        Write-Host "ERROR: No mailbox requests provided in either format" -ForegroundColor Red
        Write-LogMessage -headers $Request.Headers -API $APINAME -message 'No mailbox requests provided in either format' -Sev 'Error'
        $body = [pscustomobject]@{'Results' = @("No mailbox requests provided") }
        Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::BadRequest
            Body       = $Body
        })
        return
    }

    # Get the tenant from the request body
    $TenantFilter = $Request.body.tenantFilter
    Write-Host "Tenant: $TenantFilter" -ForegroundColor Cyan

    Write-Host "Processing permission changes for $($MailboxRequests.Count) mailboxes" -ForegroundColor Green
    Write-LogMessage -headers $Request.Headers -API $APINAME -message "Processing permission changes for $($MailboxRequests.Count) mailboxes" -Sev 'Info' -tenant $TenantFilter

    # Initialize metadata array
    $script:CmdletMetadataArray = [System.Collections.ArrayList]::new()

    # Build cmdlet array for bulk processing
    $CmdletArray = [System.Collections.ArrayList]::new()
    $UserLookupCache = @{}

    foreach ($MailboxRequest in $MailboxRequests) {
        $Username = $MailboxRequest.userID
        $Permissions = $MailboxRequest.permissions

        Write-Host "Processing mailbox: $Username" -ForegroundColor Yellow
        Write-Host "Permissions count: $($Permissions.Count)" -ForegroundColor Cyan

        if ([string]::IsNullOrEmpty($Username)) {
            Write-Host "WARNING: Skipping mailbox with missing userID" -ForegroundColor Red
            $null = $Results.Add("Skipped mailbox with missing userID")
            continue
        }

        # Cache user lookups to avoid repeated API calls
        if (-not $UserLookupCache.ContainsKey($Username)) {
            try {
                Write-Host "Looking up user: $Username" -ForegroundColor Cyan
                $UserObject = New-GraphGetRequest -uri "https://graph.microsoft.com/beta/users/$($Username)" -tenantid $TenantFilter
                # Store both ObjectId and UPN for different cmdlet requirements
                $UserLookupCache[$Username] = @{
                    ObjectId = $UserObject.id
                    UPN = $UserObject.userPrincipalName
                    DisplayName = $UserObject.displayName
                }
                Write-Host "Found user ID: $($UserLookupCache[$Username].ObjectId) UPN: $($UserLookupCache[$Username].UPN)" -ForegroundColor Green
            }
            catch {
                Write-Host "ERROR: Could not find user $($Username): $($_.Exception.Message)" -ForegroundColor Red
                # Try with different format if first fails
                try {
                    $UserObject = New-GraphGetRequest -uri "https://graph.microsoft.com/beta/users?`$filter=userPrincipalName eq '$Username'" -tenantid $TenantFilter
                    if ($UserObject.value -and $UserObject.value.Count -gt 0) {
                        $UserLookupCache[$Username] = @{
                            ObjectId = $UserObject.value[0].id
                            UPN = $UserObject.value[0].userPrincipalName
                            DisplayName = $UserObject.value[0].displayName
                        }
                        Write-Host "Found user via filter: $($UserLookupCache[$Username].ObjectId)" -ForegroundColor Green
                    } else {
                        throw "User not found with filter either"
                    }
                }
                catch {
                    Write-LogMessage -headers $Request.Headers -API $APINAME -message "Could not find user $($Username): $($_.Exception.Message)" -Sev 'Error' -tenant $TenantFilter
                    $null = $Results.Add("Could not find user $($Username): $($_.Exception.Message)")
                    continue
                }
            }
        }
        # Use UPN for Exchange cmdlets as they typically work better than ObjectId
        $UserId = $UserLookupCache[$Username].UPN

        # Convert permissions to array format if needed
        if ($Permissions -is [PSCustomObject]) {
            Write-Host "Converting permissions object to array" -ForegroundColor Cyan
            if ($Permissions.PSObject.Properties.Name -match '^\d+$') {
                $Permissions = $Permissions.PSObject.Properties.Value
            }
            else {
                $Permissions = @($Permissions)
            }
        }

        Write-Host "Processing $($Permissions.Count) permission entries for $Username" -ForegroundColor Yellow

        foreach ($Permission in $Permissions) {
            $PermissionLevels = $Permission.PermissionLevel
            $Modification = $Permission.Modification
            $AutoMap = if ($Permission.PSObject.Properties.Name -contains 'AutoMap') { $Permission.AutoMap } else { $true }

            Write-Host "Permission: $PermissionLevels, Action: $Modification, AutoMap: $AutoMap" -ForegroundColor Cyan

            # Handle multiple permission levels separated by commas
            if ($PermissionLevels -like "*,*") {
                $PermissionLevelArray = $PermissionLevels -split ',' | ForEach-Object { $_.Trim() }
            }
            else {
                $PermissionLevelArray = @($PermissionLevels.Trim())
            }

            # Handle UserID as array of objects or single value
            $TargetUsers = if ($Permission.UserID -is [array]) {
                Write-Host "UserID is array with $($Permission.UserID.Count) users" -ForegroundColor Cyan
                $Permission.UserID | ForEach-Object {
                    if ($_ -is [PSCustomObject] -and $_.value) {
                        Write-Host "Extracted user: $($_.value)" -ForegroundColor Green
                        $_.value
                    }
                    elseif ($_ -is [string]) {
                        Write-Host "User string: $_" -ForegroundColor Green
                        $_
                    }
                    else {
                        Write-Host "User other: $($_.ToString())" -ForegroundColor Green
                        $_.ToString()
                    }
                }
            }
            else {
                Write-Host "UserID is single value: $($Permission.UserID)" -ForegroundColor Cyan
                # Handle single user - could be string or object
                if ($Permission.UserID -is [PSCustomObject] -and $Permission.UserID.value) {
                    @($Permission.UserID.value)
                }
                elseif ($Permission.UserID -is [string]) {
                    @($Permission.UserID)
                }
                else {
                    @($Permission.UserID.ToString())
                }
            }

            Write-Host "Target users: $($TargetUsers -join ', ')" -ForegroundColor Green

            foreach ($TargetUser in $TargetUsers) {
                foreach ($PermissionLevel in $PermissionLevelArray) {

                    Write-Host "Creating cmdlet for: $TargetUser -> $PermissionLevel ($Modification)" -ForegroundColor Yellow

                    # Create cmdlet parameters based on permission type and action
                    $CmdletParams = @{}
                    $CmdletName = ""
                    $ExpectedResult = ""

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
                                $ExpectedResult = "Removed $($TargetUser) from $($Username) Shared Mailbox permissions (FullAccess)"
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
                                $ExpectedResult = "Granted $($TargetUser) access to $($Username) Mailbox (FullAccess) with automapping set to $($AutoMap)"
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
                                $ExpectedResult = "Removed $($TargetUser) from $($Username) with Send As permissions"
                            }
                            else {
                                $CmdletName = 'Add-RecipientPermission'
                                $CmdletParams = @{
                                    Identity     = $UserId
                                    Trustee      = $TargetUser
                                    accessRights = @('SendAs')
                                    Confirm      = $false
                                }
                                $ExpectedResult = "Granted $($TargetUser) access to $($Username) with Send As permissions"
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
                                $ExpectedResult = "Removed $($TargetUser) from $($Username) Send on Behalf Permissions"
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
                                $ExpectedResult = "Granted $($TargetUser) access to $($Username) with Send On Behalf Permissions"
                            }
                        }
                        'ReadPermission' {
                            if ($Modification -eq 'Remove') {
                                $CmdletName = 'Remove-MailboxPermission'
                                $CmdletParams = @{
                                    Identity     = $UserId
                                    user         = $TargetUser
                                    accessRights = @('ReadPermission')
                                    Confirm      = $false
                                }
                                $ExpectedResult = "Removed $($TargetUser) from $($Username) Read Permissions"
                            }
                        }
                        'ExternalAccount' {
                            if ($Modification -eq 'Remove') {
                                $CmdletName = 'Remove-MailboxPermission'
                                $CmdletParams = @{
                                    Identity     = $UserId
                                    user         = $TargetUser
                                    accessRights = @('ExternalAccount')
                                    Confirm      = $false
                                }
                                $ExpectedResult = "Removed $($TargetUser) from $($Username) External Account Permissions"
                            }
                        }
                        'DeleteItem' {
                            if ($Modification -eq 'Remove') {
                                $CmdletName = 'Remove-MailboxPermission'
                                $CmdletParams = @{
                                    Identity     = $UserId
                                    user         = $TargetUser
                                    accessRights = @('DeleteItem')
                                    Confirm      = $false
                                }
                                $ExpectedResult = "Removed $($TargetUser) from $($Username) Delete Item Permissions"
                            }
                        }
                        'ChangePermission' {
                            if ($Modification -eq 'Remove') {
                                $CmdletName = 'Remove-MailboxPermission'
                                $CmdletParams = @{
                                    Identity     = $UserId
                                    user         = $TargetUser
                                    accessRights = @('ChangePermission')
                                    Confirm      = $false
                                }
                                $ExpectedResult = "Removed $($TargetUser) from $($Username) Change Permission Rights"
                            }
                        }
                        'ChangeOwner' {
                            if ($Modification -eq 'Remove') {
                                $CmdletName = 'Remove-MailboxPermission'
                                $CmdletParams = @{
                                    Identity     = $UserId
                                    user         = $TargetUser
                                    accessRights = @('ChangeOwner')
                                    Confirm      = $false
                                }
                                $ExpectedResult = "Removed $($TargetUser) from $($Username) Change Owner Permissions"
                            }
                        }
                    }

                    if ($CmdletName) {
                        # Create cmdlet object for bulk request
                        $CmdletObj = @{
                            CmdletInput = @{
                                CmdletName = $CmdletName
                                Parameters = $CmdletParams
                            }
                        }

                        # Store expected result and metadata separately for later use
                        $CmdletMetadata = [PSCustomObject]@{
                            ExpectedResult = $ExpectedResult
                            Mailbox = $Username
                            TargetUser = $TargetUser
                            Permission = $PermissionLevel
                            Action = $Modification
                            Index = $CmdletArray.Count
                        }

                        $null = $CmdletArray.Add($CmdletObj)
                        $null = $script:CmdletMetadataArray.Add($CmdletMetadata)

                        Write-Host "Added cmdlet #$($CmdletArray.Count): $($CmdletName) for $($TargetUser) on $($Username) ($($PermissionLevel))" -ForegroundColor Green
                        Write-LogMessage -headers $Request.Headers -API $APINAME -message "Added $($CmdletName) cmdlet for $($TargetUser) on $($Username) ($($PermissionLevel))" -Sev 'Debug' -tenant $TenantFilter
                    }
                    else {
                        Write-Host "WARNING: No cmdlet name determined for $PermissionLevel" -ForegroundColor Red
                    }
                }
            }
        }
    }

    Write-Host "Total cmdlets built: $($CmdletArray.Count)" -ForegroundColor Yellow

    if ($CmdletArray.Count -eq 0) {
        Write-Host "ERROR: No valid cmdlets to process" -ForegroundColor Red
        Write-LogMessage -headers $Request.Headers -API $APINAME -message 'No valid cmdlets to process' -Sev 'Warning' -tenant $TenantFilter
        $body = [pscustomobject]@{'Results' = @("No valid permission changes to process") }
        Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body       = $Body
        })
        return
    }

    # Validate cmdlet array structure
    Write-Host "Validating cmdlet array structure..." -ForegroundColor Cyan
    for ($i = 0; $i -lt $CmdletArray.Count; $i++) {
        $cmd = $CmdletArray[$i]
        if (-not $cmd.CmdletInput) {
            Write-Host "ERROR: Missing CmdletInput at index $i" -ForegroundColor Red
        }
        if (-not $cmd.CmdletInput.CmdletName) {
            Write-Host "ERROR: Missing CmdletName at index $i" -ForegroundColor Red
        }
        if (-not $cmd.CmdletInput.Parameters) {
            Write-Host "ERROR: Missing Parameters at index $i" -ForegroundColor Red
        }
    }

    # Add temporary override for testing
    $ForceSingleRequests = $false  # Set to $true to test individual requests

    # Decide whether to use bulk processing or individual calls
    if ($CmdletArray.Count -gt 1 -and -not $ForceSingleRequests) {
        Write-Host "Using BULK processing for $($CmdletArray.Count) operations" -ForegroundColor Magenta
        # Use bulk processing for multiple operations
        try {
            Write-Host "Executing bulk request..." -ForegroundColor Yellow
            Write-LogMessage -headers $Request.Headers -API $APINAME -message "Executing bulk request with $($CmdletArray.Count) cmdlets" -Sev 'Info' -tenant $TenantFilter

            # === BULK REQUEST DEBUG ===
            Write-Host "=== BULK REQUEST DEBUG ===" -ForegroundColor Magenta
            Write-Host "Tenant: $TenantFilter" -ForegroundColor Yellow
            Write-Host "Cmdlet Array Count: $($CmdletArray.Count)" -ForegroundColor Yellow
            Write-Host "First cmdlet structure:" -ForegroundColor Yellow
            $CmdletArray[0] | ConvertTo-Json -Depth 5 | Write-Host

            # Check if we have a valid anchor
            $FirstIdentity = $CmdletArray[0].CmdletInput.Parameters.Identity
            Write-Host "First Identity for anchor: $FirstIdentity" -ForegroundColor Yellow

            # Try to validate the anchor exists
            try {
                $AnchorTest = New-GraphGetRequest -uri "https://graph.microsoft.com/beta/users/$FirstIdentity" -tenantid $TenantFilter
                Write-Host "Anchor validation successful: $($AnchorTest.userPrincipalName)" -ForegroundColor Green
            } catch {
                Write-Host "Anchor validation failed: $($_.Exception.Message)" -ForegroundColor Red
            }

            # Time the bulk request
            $StartTime = Get-Date
            Write-Host "Starting bulk request at: $StartTime" -ForegroundColor Yellow

            # Try multiple approaches to bulk request
            Write-Host "Attempting bulk request with useSystemMailbox..." -ForegroundColor Cyan
            $BulkResults = New-ExoBulkRequest -tenantid $TenantFilter -cmdletArray @($CmdletArray) -ReturnWithCommand $true -useSystemMailbox $true

            $EndTime = Get-Date
            $Duration = $EndTime - $StartTime
            Write-Host "Bulk request completed at: $EndTime (Duration: $($Duration.TotalSeconds) seconds)" -ForegroundColor Yellow

            if ($Duration.TotalSeconds -lt 2) {
                Write-Host "WARNING: Bulk request completed too quickly - possible failure" -ForegroundColor Red
            }

            Write-Host "Bulk results type: $($BulkResults.GetType().Name)" -ForegroundColor Cyan
            if ($BulkResults) {
                Write-Host "Bulk results keys/count: $($BulkResults.Keys.Count)" -ForegroundColor Cyan
            } else {
                Write-Host "Bulk results is null or empty" -ForegroundColor Red
            }

            # Process bulk results based on working patterns
            if ($BulkResults) {
                $errorCount = 0
                $ErrorMessages = [System.Collections.Generic.List[string]]::new()

                if ($BulkResults -is [hashtable] -and $BulkResults.Keys.Count -gt 0) {
                    Write-Host "Processing bulk results with keys: $($BulkResults.Keys -join ', ')" -ForegroundColor Cyan

                    foreach ($cmdletName in $BulkResults.Keys) {
                        $cmdletResults = $BulkResults[$cmdletName]
                        Write-Host "Results for $cmdletName`: $($cmdletResults.Count) items" -ForegroundColor Cyan
                        foreach ($result in $cmdletResults) {
                            if ($result.error) {
                                $errorCount++
                                try {
                                    $ErrorMessage = Get-CippException -Exception $result.error
                                    $ErrorMessages.Add("Error in $cmdletName`: $($ErrorMessage.NormalizedError)")
                                    Write-Host "Error in $cmdletName`: $($ErrorMessage.NormalizedError)" -ForegroundColor Red
                                }
                                catch {
                                    $ErrorMessages.Add("Error in $cmdletName`: $($result.error)")
                                    Write-Host "Error in $cmdletName`: $($result.error)" -ForegroundColor Red
                                }
                            }
                        }
                    }
                }
                else {
                    Write-Host "No specific bulk results returned - this is normal for write operations" -ForegroundColor Yellow
                }

                # Add error messages to results
                foreach ($ErrorMessage in $ErrorMessages) {
                    $null = $Results.Add($ErrorMessage)
                }

                # If no errors, assume success and add expected results
                if ($errorCount -eq 0) {
                    Write-Host "No errors found - operations likely succeeded" -ForegroundColor Green
                    foreach ($CmdletMetadata in $script:CmdletMetadataArray) {
                        if ($CmdletMetadata.ExpectedResult) {
                            $null = $Results.Add($CmdletMetadata.ExpectedResult)
                            Write-Host "Added result: $($CmdletMetadata.ExpectedResult)" -ForegroundColor Green
                        }
                    }
                }

                Write-Host "Successfully processed bulk mailbox permission changes" -ForegroundColor Green
                Write-LogMessage -headers $Request.Headers -API $APINAME -message "Successfully processed bulk mailbox permission changes with $errorCount errors" -Sev 'Info' -tenant $TenantFilter
            }
            else {
                Write-Host "No bulk results returned" -ForegroundColor Yellow
                # Still add expected results since no errors were thrown
                foreach ($CmdletMetadata in $script:CmdletMetadataArray) {
                    if ($CmdletMetadata.ExpectedResult) {
                        $null = $Results.Add($CmdletMetadata.ExpectedResult)
                    }
                }
            }
        }
        catch {
            Write-Host "ERROR in bulk request: $($_.Exception.Message)" -ForegroundColor Red
            Write-Host "Falling back to individual requests..." -ForegroundColor Yellow
            Write-LogMessage -headers $Request.Headers -API $APINAME -message "Error executing bulk request: $($_.Exception.Message)" -Sev 'Error' -tenant $TenantFilter

            # Fallback to individual processing
            for ($i = 0; $i -lt $CmdletArray.Count; $i++) {
                $CmdletObj = $CmdletArray[$i]
                $CmdletMetadata = $script:CmdletMetadataArray[$i]
                try {
                    Write-Host "Executing individual request $($i+1): $($CmdletObj.CmdletInput.CmdletName)" -ForegroundColor Yellow
                    $null = New-ExoRequest -Anchor $CmdletMetadata.Mailbox -tenantid $TenantFilter -cmdlet $CmdletObj.CmdletInput.CmdletName -cmdParams $CmdletObj.CmdletInput.Parameters
                    $null = $Results.Add($CmdletMetadata.ExpectedResult)
                    Write-Host "Individual request $($i+1) completed successfully" -ForegroundColor Green
                }
                catch {
                    Write-Host "ERROR in individual request $($i+1): $($_.Exception.Message)" -ForegroundColor Red
                    $null = $Results.Add("Could not execute $($CmdletMetadata.Permission) permission modification for $($CmdletMetadata.TargetUser) on $($CmdletMetadata.Mailbox). Error: $($_.Exception.Message)")
                }
            }
        }
    }
    else {
        Write-Host "Using INDIVIDUAL processing for single operation" -ForegroundColor Magenta
        # Use individual processing for single operation
        $CmdletObj = $CmdletArray[0]
        $CmdletMetadata = $script:CmdletMetadataArray[0]
        try {
            Write-Host "Executing individual request: $($CmdletObj.CmdletInput.CmdletName)" -ForegroundColor Yellow
            $null = New-ExoRequest -Anchor $CmdletMetadata.Mailbox -tenantid $TenantFilter -cmdlet $CmdletObj.CmdletInput.CmdletName -cmdParams $CmdletObj.CmdletInput.Parameters
            Write-Host "Individual request completed successfully" -ForegroundColor Green
            $null = $Results.Add($CmdletMetadata.ExpectedResult)
            Write-LogMessage -headers $Request.Headers -API $APINAME -message "Executed $($CmdletMetadata.Permission) permission modification for $($CmdletMetadata.TargetUser) on $($CmdletMetadata.Mailbox)" -Sev 'Info' -tenant $TenantFilter
        }
        catch {
            Write-Host "ERROR in individual request: $($_.Exception.Message)" -ForegroundColor Red
            Write-LogMessage -headers $Request.Headers -API $APINAME -message "Could not execute $($CmdletMetadata.Permission) permission modification for $($CmdletMetadata.TargetUser) on $($CmdletMetadata.Mailbox): $($_.Exception.Message)" -Sev 'Error' -tenant $TenantFilter
            $null = $Results.Add("Could not execute $($CmdletMetadata.Permission) permission modification for $($CmdletMetadata.TargetUser) on $($CmdletMetadata.Mailbox). Error: $($_.Exception.Message)")
        }
    }

    Write-Host "Final results count: $($Results.Count)" -ForegroundColor Yellow
    Write-Host "=== ExecModifyMBPerms Completed ===" -ForegroundColor Yellow

    $body = [pscustomobject]@{'Results' = @($Results) }

    # Associate values to output bindings by calling 'Push-OutputBinding'.
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body       = $Body
        })
}
