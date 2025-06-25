function Invoke-ListDirectoryRoles {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Tenant.Directory.Read
    #>
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    Write-LogMessage -user $request.headers.'x-ms-client-principal' -API $APINAME -message 'Accessed this API' -Sev 'Debug'

    try {
        # Get directory role templates (these are the available roles that can be activated)
        $DirectoryRoleTemplates = New-GraphGETRequest -uri "https://graph.microsoft.com/v1.0/directoryRoleTemplates" -tenantid $env:TenantID -NoAuthCheck $true

        # Filter to commonly used admin roles for service principals
        $CommonRoles = @(
            'Global Reader',
            'Security Reader',
            'Reports Reader',
            'Helpdesk Administrator',
            'Password Administrator',
            'Billing Administrator',
            'User Administrator',
            'Groups Administrator',
            'Application Administrator',
            'Cloud Application Administrator',
            'Exchange Administrator',
            'SharePoint Administrator',
            'Teams Administrator',
            'Intune Administrator',
            'Security Administrator',
            'Compliance Administrator'
        )

        $FilteredRoles = $DirectoryRoleTemplates | Where-Object {
            $_.displayName -in $CommonRoles
        } | Select-Object id, displayName, description | Sort-Object displayName

        $StatusCode = [HttpStatusCode]::OK
        $Results = $FilteredRoles

    } catch {
        $ErrorMsg = Get-NormalizedError -message $_.Exception.Message
        $Results = @{ Error = $ErrorMsg }
        $StatusCode = [HttpStatusCode]::BadRequest
    }

    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
        StatusCode = $StatusCode
        Body       = @($Results)
    })
}
