function Set-CIPPDmarcMailbox {
    <#
    .SYNOPSIS
        Manage the DMARC shared mailbox and Application RBAC for a tenant
    .DESCRIPTION
        Creates, validates, and configures the per-tenant DMARC shared mailbox
        and Exchange Online Application RBAC (management scope + service principal
        + role assignment) scoped to only that mailbox. Each operation is gated by
        a switch so callers can run individual steps or the full provisioning flow.
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [Parameter(Mandatory = $true)]
        [string]$TenantFilter,

        [Parameter(Mandatory = $false)]
        [string]$MailboxAddress,

        [Parameter(Mandatory = $false)]
        [string]$DisplayName = 'CIPP DMARC Reports',

        [switch]$CreateMailbox,
        [switch]$CreateRbac,
        [switch]$TestAccess,
        [switch]$RemoveRbac,
        [switch]$RemoveMailbox
    )

    $Results = [System.Collections.Generic.List[object]]::new()
    $ScopeName = 'CIPP-DMARC-Scope'
    $RoleAssignmentName = 'CIPP-DMARC-MailReadWrite'

    # Resolve the mailbox address — default to dmarc-reports@defaultdomain
    if ([string]::IsNullOrWhiteSpace($MailboxAddress)) {
        $MailboxAddress = "dmarc-reports@$TenantFilter"
    }
    $Username = ($MailboxAddress -split '@')[0]

    # Resolve the SAM app identity for EXO service principal operations
    $SamAppId = $env:ApplicationID
    $SpResponse = New-GraphGetRequest -uri "https://graph.microsoft.com/v1.0/servicePrincipals(appId='$SamAppId')?`$select=id" -tenantid $TenantFilter -NoAuthCheck $true
    $SamObjectId = $SpResponse.id

    #region CreateMailbox
    if ($CreateMailbox -and $PSCmdlet.ShouldProcess($TenantFilter, "Create shared mailbox $MailboxAddress")) {
        try {
            $ExistingMailbox = New-ExoRequest -tenantid $TenantFilter -cmdlet 'Get-Mailbox' -cmdParams @{ Identity = $MailboxAddress } -useSystemMailbox $true
            $Results.Add([PSCustomObject]@{
                    Step    = 'CreateMailbox'
                    Success = $true
                    Message = "Shared mailbox $MailboxAddress already exists"
                })
        } catch {
            try {
                $MailboxParams = [pscustomobject]@{
                    displayName        = $DisplayName
                    name               = $Username
                    primarySMTPAddress = $MailboxAddress
                    Shared             = $true
                }
                $NewMailbox = New-ExoRequest -tenantid $TenantFilter -cmdlet 'New-Mailbox' -cmdParams $MailboxParams
                $Results.Add([PSCustomObject]@{
                        Step    = 'CreateMailbox'
                        Success = $true
                        Message = "Created shared mailbox $MailboxAddress"
                    })

                # Block sign-in for the shared mailbox
                try {
                    $null = Set-CIPPSignInState -userid $NewMailbox.ExternalDirectoryObjectId -TenantFilter $TenantFilter -AccountEnabled $false
                    $Results.Add([PSCustomObject]@{
                            Step    = 'BlockSignIn'
                            Success = $true
                            Message = "Blocked sign-in for $MailboxAddress"
                        })
                } catch {
                    $ErrorMessage = Get-CippException -Exception $_
                    $Results.Add([PSCustomObject]@{
                            Step    = 'BlockSignIn'
                            Success = $false
                            Message = "Failed to block sign-in: $($ErrorMessage.NormalizedError)"
                            Data    = $ErrorMessage
                        })
                }
            } catch {
                $ErrorMessage = Get-CippException -Exception $_
                $Results.Add([PSCustomObject]@{
                        Step    = 'CreateMailbox'
                        Success = $false
                        Message = "Failed to create shared mailbox: $($ErrorMessage.NormalizedError)"
                        Data    = $ErrorMessage
                    })
            }
        }
    }
    #endregion

    #region CreateRbac
    if ($CreateRbac -and $PSCmdlet.ShouldProcess($TenantFilter, "Create Application RBAC for $MailboxAddress")) {
        # Step 1: Create management scope
        try {
            $null = New-ExoRequest -tenantid $TenantFilter -cmdlet 'New-ManagementScope' -cmdParams @{
                Name                      = $ScopeName
                RecipientRestrictionFilter = "PrimarySmtpAddress -eq '$MailboxAddress'"
            } -useSystemMailbox $true
            $Results.Add([PSCustomObject]@{
                    Step    = 'CreateManagementScope'
                    Success = $true
                    Message = "Created management scope '$ScopeName' for $MailboxAddress"
                })
        } catch {
            $ErrorMessage = Get-CippException -Exception $_
            if ($ErrorMessage.NormalizedError -match 'already exists') {
                # Update existing scope to point to current mailbox
                try {
                    $null = New-ExoRequest -tenantid $TenantFilter -cmdlet 'Set-ManagementScope' -cmdParams @{
                        Identity                  = $ScopeName
                        RecipientRestrictionFilter = "PrimarySmtpAddress -eq '$MailboxAddress'"
                    } -useSystemMailbox $true
                    $Results.Add([PSCustomObject]@{
                            Step    = 'CreateManagementScope'
                            Success = $true
                            Message = "Updated existing management scope '$ScopeName' for $MailboxAddress"
                        })
                } catch {
                    $SetError = Get-CippException -Exception $_
                    $Results.Add([PSCustomObject]@{
                            Step    = 'CreateManagementScope'
                            Success = $false
                            Message = "Failed to update management scope: $($SetError.NormalizedError)"
                            Data    = $SetError
                        })
                }
            } else {
                $Results.Add([PSCustomObject]@{
                        Step    = 'CreateManagementScope'
                        Success = $false
                        Message = "Failed to create management scope: $($ErrorMessage.NormalizedError)"
                        Data    = $ErrorMessage
                    })
            }
        }

        # Step 2: Ensure SAM service principal exists in EXO
        try {
            $ExoSp = New-ExoRequest -tenantid $TenantFilter -cmdlet 'Get-ServicePrincipal' -cmdParams @{
                Identity = $SamAppId
            } -useSystemMailbox $true
            $Results.Add([PSCustomObject]@{
                    Step    = 'VerifyExoServicePrincipal'
                    Success = $true
                    Message = "SAM service principal found in Exchange Online ($($ExoSp.DisplayName))"
                })
        } catch {
            # Not found — register it (same pattern as Set-CIPPSAMAdminRoles)
            try {
                $null = New-ExoRequest -tenantid $TenantFilter -cmdlet 'New-ServicePrincipal' -cmdParams @{
                    AppId       = $SamAppId
                    ObjectId    = $SamObjectId
                    DisplayName = 'CIPP-SAM'
                } -useSystemMailbox $true
                $Results.Add([PSCustomObject]@{
                        Step    = 'RegisterExoServicePrincipal'
                        Success = $true
                        Message = 'SAM service principal was missing — registered in Exchange Online'
                    })
            } catch {
                $ErrorMessage = Get-CippException -Exception $_
                $Results.Add([PSCustomObject]@{
                        Step    = 'RegisterExoServicePrincipal'
                        Success = $false
                        Message = "Failed to register SAM service principal in Exchange Online: $($ErrorMessage.NormalizedError)"
                        Data    = $ErrorMessage
                    })
            }
        }

        # Step 3: Create role assignment scoped to the management scope
        try {
            $null = New-ExoRequest -tenantid $TenantFilter -cmdlet 'New-ManagementRoleAssignment' -cmdParams @{
                Name                = $RoleAssignmentName
                Role                = 'Application Mail.ReadWrite'
                App                 = $SamAppId
                CustomResourceScope = $ScopeName
            } -useSystemMailbox $true
            $Results.Add([PSCustomObject]@{
                    Step    = 'CreateRoleAssignment'
                    Success = $true
                    Message = "Created role assignment '$RoleAssignmentName' with Application Mail.ReadWrite scoped to '$ScopeName'"
                })
        } catch {
            $ErrorMessage = Get-CippException -Exception $_
            if ($ErrorMessage.NormalizedError -match 'already exists') {
                # Update existing role assignment scope
                try {
                    $null = New-ExoRequest -tenantid $TenantFilter -cmdlet 'Set-ManagementRoleAssignment' -cmdParams @{
                        Identity            = $RoleAssignmentName
                        CustomResourceScope = $ScopeName
                    } -useSystemMailbox $true
                    $Results.Add([PSCustomObject]@{
                            Step    = 'CreateRoleAssignment'
                            Success = $true
                            Message = "Updated existing role assignment '$RoleAssignmentName' to scope '$ScopeName'"
                        })
                } catch {
                    $SetError = Get-CippException -Exception $_
                    $Results.Add([PSCustomObject]@{
                            Step    = 'CreateRoleAssignment'
                            Success = $false
                            Message = "Failed to update role assignment: $($SetError.NormalizedError)"
                            Data    = $SetError
                        })
                }
            } else {
                $Results.Add([PSCustomObject]@{
                        Step    = 'CreateRoleAssignment'
                        Success = $false
                        Message = "Failed to create role assignment: $($ErrorMessage.NormalizedError)"
                        Data    = $ErrorMessage
                    })
            }
        }
    }
    #endregion

    #region TestAccess
    if ($TestAccess -and $PSCmdlet.ShouldProcess($TenantFilter, "Test Application RBAC access to $MailboxAddress")) {
        # Test 1: Verify mailbox exists
        try {
            $Mailbox = New-ExoRequest -tenantid $TenantFilter -cmdlet 'Get-Mailbox' -cmdParams @{ Identity = $MailboxAddress } -useSystemMailbox $true
            $Results.Add([PSCustomObject]@{
                    Step    = 'TestMailboxExists'
                    Success = $true
                    Message = "Mailbox $MailboxAddress exists"
                })
        } catch {
            $ErrorMessage = Get-CippException -Exception $_
            $Results.Add([PSCustomObject]@{
                    Step    = 'TestMailboxExists'
                    Success = $false
                    Message = "Mailbox $MailboxAddress not found: $($ErrorMessage.NormalizedError)"
                    Data    = $ErrorMessage
                })
        }

        # Test 2: Verify RBAC authorization (bypasses cache)
        try {
            $AuthTest = New-ExoRequest -tenantid $TenantFilter -cmdlet 'Test-ServicePrincipalAuthorization' -cmdParams @{
                Identity = $SamAppId
                Resource = $MailboxAddress
            } -useSystemMailbox $true
            $MailReadWrite = $AuthTest | Where-Object { $_.RoleName -eq 'Application Mail.ReadWrite' -and $_.InScope -eq $true }
            if ($MailReadWrite) {
                $Results.Add([PSCustomObject]@{
                        Step    = 'TestRbacAccess'
                        Success = $true
                        Message = "Application Mail.ReadWrite is active and in scope for $MailboxAddress"
                    })
            } else {
                $Results.Add([PSCustomObject]@{
                        Step    = 'TestRbacAccess'
                        Success = $false
                        Message = "Application Mail.ReadWrite is not in scope for $MailboxAddress. RBAC changes may take 30 minutes to 2 hours to propagate."
                        Data    = $AuthTest
                    })
            }
        } catch {
            $ErrorMessage = Get-CippException -Exception $_
            $Results.Add([PSCustomObject]@{
                    Step    = 'TestRbacAccess'
                    Success = $false
                    Message = "Failed to test RBAC authorization: $($ErrorMessage.NormalizedError)"
                    Data    = $ErrorMessage
                })
        }

        # Test 3: Verify Graph API mail access (may fail if RBAC cache hasn't propagated)
        try {
            $MailboxId = $Mailbox.ExternalDirectoryObjectId ?? $MailboxAddress
            $null = New-GraphGetRequest -uri "https://graph.microsoft.com/v1.0/users/$MailboxId/mailFolders/inbox?`$select=id,displayName,totalItemCount" -tenantid $TenantFilter -AsApp $true
            # Note: Graph mail access test uses -AsApp because it tests the Application RBAC we just configured
            $Results.Add([PSCustomObject]@{
                    Step    = 'TestGraphMailAccess'
                    Success = $true
                    Message = "Graph API can read inbox of $MailboxAddress"
                })
        } catch {
            $ErrorMessage = Get-CippException -Exception $_
            $Results.Add([PSCustomObject]@{
                    Step    = 'TestGraphMailAccess'
                    Success = $false
                    Message = "Graph API mail access not yet available. RBAC changes may take 30 minutes to 2 hours to propagate. Error: $($ErrorMessage.NormalizedError)"
                    Data    = $ErrorMessage
                })
        }
    }
    #endregion

    #region RemoveRbac
    if ($RemoveRbac -and $PSCmdlet.ShouldProcess($TenantFilter, "Remove Application RBAC for DMARC")) {
        try {
            $null = New-ExoRequest -tenantid $TenantFilter -cmdlet 'Remove-ManagementRoleAssignment' -cmdParams @{
                Identity = $RoleAssignmentName
                Confirm  = $false
            } -useSystemMailbox $true
            $Results.Add([PSCustomObject]@{
                    Step    = 'RemoveRoleAssignment'
                    Success = $true
                    Message = "Removed role assignment '$RoleAssignmentName'"
                })
        } catch {
            $ErrorMessage = Get-CippException -Exception $_
            $Results.Add([PSCustomObject]@{
                    Step    = 'RemoveRoleAssignment'
                    Success = $false
                    Message = "Failed to remove role assignment: $($ErrorMessage.NormalizedError)"
                    Data    = $ErrorMessage
                })
        }

        try {
            $null = New-ExoRequest -tenantid $TenantFilter -cmdlet 'Remove-ManagementScope' -cmdParams @{
                Identity = $ScopeName
                Confirm  = $false
            } -useSystemMailbox $true
            $Results.Add([PSCustomObject]@{
                    Step    = 'RemoveManagementScope'
                    Success = $true
                    Message = "Removed management scope '$ScopeName'"
                })
        } catch {
            $ErrorMessage = Get-CippException -Exception $_
            $Results.Add([PSCustomObject]@{
                    Step    = 'RemoveManagementScope'
                    Success = $false
                    Message = "Failed to remove management scope: $($ErrorMessage.NormalizedError)"
                    Data    = $ErrorMessage
                })
        }
    }
    #endregion

    #region RemoveMailbox
    if ($RemoveMailbox -and $PSCmdlet.ShouldProcess($TenantFilter, "Remove shared mailbox $MailboxAddress")) {
        try {
            $null = New-ExoRequest -tenantid $TenantFilter -cmdlet 'Remove-Mailbox' -cmdParams @{
                Identity = $MailboxAddress
                Confirm  = $false
            } -useSystemMailbox $true
            $Results.Add([PSCustomObject]@{
                    Step    = 'RemoveMailbox'
                    Success = $true
                    Message = "Removed shared mailbox $MailboxAddress"
                })
        } catch {
            $ErrorMessage = Get-CippException -Exception $_
            $Results.Add([PSCustomObject]@{
                    Step    = 'RemoveMailbox'
                    Success = $false
                    Message = "Failed to remove mailbox: $($ErrorMessage.NormalizedError)"
                    Data    = $ErrorMessage
                })
        }
    }
    #endregion

    return $Results
}
