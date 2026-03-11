function Invoke-ExecUserSettings {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        CIPP.Core.ReadWrite
    #>
    param($Request, $TriggerMetadata)
    try {
        $object = $Request.Body.currentSettings | Select-Object * -ExcludeProperty CurrentTenant, pageSizes, sidebarShow, sidebarUnfoldable, _persist | ConvertTo-Json -Compress -Depth 10
        $User = $Request.Body.user
        if ($User -isnot [string]) {
            $User = @(
                $User.userDetails
                $User.userPrincipalName
                $User.upn
                $User.value
                $User.username
                $User.name
                $User.email
            ) | Where-Object { $_ -is [string] -and -not [string]::IsNullOrWhiteSpace($_) } | Select-Object -First 1
        }

        if ([string]::IsNullOrWhiteSpace($User)) {
            throw 'User value is required to save user settings'
        }

        $Table = Get-CippTable -tablename 'UserSettings'
        $Table.Force = $true
        Add-CIPPAzDataTableEntity @Table -Entity @{
            JSON         = "$object"
            RowKey       = "$User"
            PartitionKey = 'UserSettings'
        }
        $StatusCode = [System.Net.HttpStatusCode]::OK
        $Results = [pscustomobject]@{'Results' = 'Successfully added user settings' }
    } catch {
        $ErrorMsg = Get-NormalizedError -message $($_.Exception.Message)
        $Results = "Function Error: $ErrorMsg"
        $StatusCode = [System.Net.HttpStatusCode]::BadRequest
    }
    return [HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = @($Results)
        }

}
