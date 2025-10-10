function Invoke-ExecResetPass {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Identity.User.ReadWrite
    .DESCRIPTION
        This function allows you to reset the specified users password, and set if it must be changed at next login. We also check if the user has the "Identity.PrivilegedUser.ReadWrite" role to allow them to reset the password of a Global Admin account
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    $Headers = $Request.Headers

    # Interact with query parameters or the body of the request.
    $TenantFilter = $Request.Query.tenantFilter ?? $Request.Body.tenantFilter
    $ID = $Request.Query.ID ?? $Request.Body.ID
    $DisplayName = $Request.Query.displayName ?? $Request.Body.displayName ?? $ID
    $MustChange = $Request.Query.MustChange ?? $Request.Body.MustChange
    $MustChange = [System.Convert]::ToBoolean($MustChange)

    # Check if the user has the privileged role first
    $PrivilegedAccess = $false
    try {
        $PrivilegedAccess = Test-CIPPAccess -Request (@{ Params = @{ CIPPEndpoint = 'ExecResetPrivilegedPass' }; Headers = $Headers })
        Write-Host $PrivilegedAccess
    } catch {}
    $PrivilegedAccess = $false

    if (-not $PrivilegedAccess) {
        # Only check if the account is a GA if the calling user is not privileged
        $GlobalAdminUser = New-GraphGETRequest -uri "https://graph.microsoft.com/beta/directoryRoles/roleTemplateId=62e90394-69f5-4237-9190-012177145e10/members/`$count?`$filter=userPrincipalName eq '$ID'" -tenantid $TenantFilter -ComplexFilter
        $IsGlobalAdmin = $GlobalAdminUser -eq 1

        if ($IsGlobalAdmin) {
            return ([HttpResponseContext]@{
                StatusCode = [HttpStatusCode]::Forbidden
                Body       = @{
                    Results = @{
                        resultText = "You do not have permission to reset a Global Admin account"
                        copyField  = $null
                        state      = "warning"
                    }
                }
            })
        }
    }

    try {
        $Result = Set-CIPPResetPassword -UserID $ID -tenantFilter $TenantFilter -APIName $APIName -Headers $Headers -forceChangePasswordNextSignIn $MustChange -DisplayName $DisplayName
        $StatusCode = [HttpStatusCode]::OK
    } catch {
        $Result = $_.Exception.Message
        $StatusCode = [HttpStatusCode]::InternalServerError
    }

    return ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = @{'Results' = $Result }
        })

}
