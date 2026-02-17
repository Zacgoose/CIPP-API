function Invoke-AddCustomScript {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        CIPP.CustomScript.ReadWrite
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $TriggerMetadata.FunctionName
    $Headers = $Request.Headers

    try {
        # Validate required fields for restore vs add/update
        $RestoreToVersion = $Request.Body.RestoreToVersion
        $ScriptGuid = $Request.Body.ScriptGuid

        # Handle restore functionality
        if ($RestoreToVersion) {
            # Restore requires only ScriptGuid and RestoreToVersion
            if ([string]::IsNullOrWhiteSpace($ScriptGuid)) {
                throw 'ScriptGuid is required for restore operation'
            }

            # Get existing script to determine version
            $Table = Get-CippTable -tablename 'CustomPowershellScripts'
            $Filter = "PartitionKey eq 'CustomScript' and ScriptGuid eq '{0}'" -f $ScriptGuid
            $ExistingScripts = Get-CIPPAzDataTableEntity @Table -Filter $Filter

            # Find the target version
            $TargetScript = $ExistingScripts | Where-Object { $_.Version -eq $RestoreToVersion }

            if (-not $TargetScript) {
                throw "Version $RestoreToVersion not found for script GUID '$ScriptGuid'"
            }

            # Delete all versions newer than the restore target
            $NewerVersions = $ExistingScripts | Where-Object { $_.Version -gt $RestoreToVersion }
            foreach ($script in $NewerVersions) {
                Remove-AzDataTableEntity @Table -Entity $script
            }

            Write-LogMessage -API $APIName -headers $Headers -message "Restored custom script: $($TargetScript.ScriptName) to version $RestoreToVersion (Deleted $($NewerVersions.Count) newer version(s))" -sev 'Info'

            $Body = @{
                Results = "Successfully restored custom script '$($TargetScript.ScriptName)' to version $RestoreToVersion"
            }

            $StatusCode = [HttpStatusCode]::OK
        } else {
            # Normal add/update - create new version
            $ScriptName = $Request.Body.ScriptName
            $ScriptContent = $Request.Body.ScriptContent
            $Description = $Request.Body.Description
            $Category = $Request.Body.Category
            $Risk = $Request.Body.Risk

            if ([string]::IsNullOrWhiteSpace($ScriptName)) {
                throw 'ScriptName is required'
            }

            if ([string]::IsNullOrWhiteSpace($ScriptContent)) {
                throw 'ScriptContent is required'
            }

            # Validate script security constraints before saving
            Test-CustomScriptSecurity -ScriptContent $ScriptContent

            # Validate script name format (alphanumeric, spaces, hyphens, underscores only)
            if ($ScriptName -notmatch '^[a-zA-Z0-9\s\-_]+$') {
                throw 'ScriptName can only contain letters, numbers, spaces, hyphens, and underscores. Spaces are allowed but may affect command-line usage.'
            }

            # Get the table reference
            $Table = Get-CippTable -tablename 'CustomPowershellScripts'

            if ($ScriptGuid) {
                # Get existing script to determine version if the GUID is provided (update scenario)
                $Filter = "PartitionKey eq 'CustomScript' and ScriptGuid eq '{0}'" -f $ScriptGuid
                $ExistingVersions = Get-CIPPAzDataTableEntity @Table -Filter $Filter
                if (-not $ExistingVersions) {
                    throw "Script with GUID '$ScriptGuid' not found"
                }

                $Version = ($ExistingVersions | Measure-Object -Property Version -Maximum).Maximum + 1
            } else {
                # Create GUID for script since it doesn't exist yet
                $ScriptGuid = (New-Guid).ToString()
                $Version = 1
            }

            # Create entity
            $RowKey = '{0}-v{1}' -f $ScriptGuid, $Version
            $Entity = @{
                PartitionKey       = 'CustomScript'
                RowKey             = $RowKey
                ScriptGuid         = $ScriptGuid
                ScriptName         = $ScriptName
                Version            = $Version
                ScriptContent      = $ScriptContent
                Description        = $Description
                Category           = $Category
                Risk               = $Risk
                CreatedBy          = if ($Headers) { ([System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($Headers.'x-ms-client-principal')) | ConvertFrom-Json).userDetails } else { 'Unknown' }
                CreatedDate        = (Get-Date).ToUniversalTime().ToString('o')
            }

            # Save to table
            Add-CIPPAzDataTableEntity @Table -Entity $Entity -Force

            Write-LogMessage -API $APIName -headers $Headers -message "Created custom script: $ScriptName (Version: $Version)" -sev 'Info'

            $Body = @{
                Results = "Successfully created custom script '$ScriptName'"
            }

            $StatusCode = [HttpStatusCode]::OK
        }

    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -API $APIName -headers $Headers -message "Failed to create custom script: $($ErrorMessage.NormalizedError)" -Sev 'Error' -LogData $ErrorMessage
        $StatusCode = [HttpStatusCode]::BadRequest
        $Body = @{ Error = $ErrorMessage.NormalizedError }
    }

    return ([HttpResponseContext]@{
            StatusCode = $StatusCode ?? [HttpStatusCode]::OK
            Body       = $Body
        })
}
