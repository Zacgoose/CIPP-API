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
            $UserPropertyOrder = @('userDetails', 'userPrincipalName', 'upn', 'value', 'username', 'name', 'email')
            $ResolvedUser = $null
            foreach ($Property in $UserPropertyOrder) {
                $Candidate = $User.$Property
                if ($Candidate -is [string] -and -not [string]::IsNullOrWhiteSpace($Candidate)) {
                    $ResolvedUser = $Candidate
                    break
                }
            }
            $User = $ResolvedUser
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
