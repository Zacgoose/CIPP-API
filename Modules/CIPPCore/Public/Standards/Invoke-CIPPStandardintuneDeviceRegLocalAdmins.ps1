function Invoke-CIPPStandardintuneDeviceRegLocalAdmins {
    <#
    .FUNCTIONALITY
        Internal
    .COMPONENT
        (APIName) intuneDeviceRegLocalAdmins
    .SYNOPSIS
        (Label) Configure local administrator rights for users joining devices
    .DESCRIPTION
        (Helptext) Controls whether users who register Microsoft Entra joined devices are granted local administrator rights on those devices.
        (DocsDescription) Configures the Device Registration Policy local administrator behavior for registering users. When enabled, users who register devices are not granted local administrator rights.
    .NOTES
        CAT
            Intune Standards
        TAG
        EXECUTIVETEXT
            Controls whether employees who enroll devices automatically receive local administrator access. Disabling registering-user admin rights follows least-privilege principles and reduces security risk from over-privileged endpoints.
        ADDEDCOMPONENT
            {"type":"switch","name":"standards.intuneDeviceRegLocalAdmins.disableRegisteringUsers","label":"Disable registering users as local administrators","defaultValue":true}
        IMPACT
            Medium Impact
        ADDEDDATE
            2026-02-23
        POWERSHELLEQUIVALENT
            Update-MgBetaPolicyDeviceRegistrationPolicy
        RECOMMENDEDBY
        UPDATECOMMENTBLOCK
            Run the Tools\Update-StandardsComments.ps1 script to update this comment block
    .LINK
        https://docs.cipp.app/user-documentation/tenant/standards/list-standards
    #>

    param($Tenant, $Settings)
    $TestResult = Test-CIPPStandardLicense -StandardName 'intuneDeviceRegLocalAdmins' -TenantFilter $Tenant -RequiredCapabilities @('INTUNE_A', 'MDM_Services', 'EMS', 'SCCM', 'MICROSOFTINTUNEPLAN1')

    if ($TestResult -eq $false) {
        return $true
    }

    try {
        $PreviousSetting = New-GraphGetRequest -uri 'https://graph.microsoft.com/beta/policies/deviceRegistrationPolicy' -tenantid $Tenant
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -API 'Standards' -Tenant $Tenant -Message "Could not get the intuneDeviceRegLocalAdmins state for $Tenant. Error: $($ErrorMessage.NormalizedError)" -Sev Error -LogData $ErrorMessage
        return
    }

    $CurrentOdataType = $PreviousSetting.azureADJoin.localAdmins.registeringUsers.'@odata.type'
    $DesiredOdataType = if ([bool]$Settings.disableRegisteringUsers) { '#microsoft.graph.noDeviceRegistrationMembership' } else { '#microsoft.graph.allDeviceRegistrationMembership' }
    $StateIsCorrect = $CurrentOdataType -eq $DesiredOdataType
    $DesiredStateText = if ([bool]$Settings.disableRegisteringUsers) { 'disabled' } else { 'enabled' }

    if ($Settings.remediate -eq $true) {
        if ($StateIsCorrect -eq $true) {
            Write-LogMessage -API 'Standards' -tenant $Tenant -message "Registering users local administrator rights are already $DesiredStateText." -sev Info
        } else {
            try {
                $PreviousSetting.azureADJoin.localAdmins.registeringUsers = @{ '@odata.type' = $DesiredOdataType }
                $NewBody = ConvertTo-Json -Compress -InputObject $PreviousSetting -Depth 10
                New-GraphPostRequest -tenantid $Tenant -Uri 'https://graph.microsoft.com/beta/policies/deviceRegistrationPolicy' -Type PUT -Body $NewBody -ContentType 'application/json'
                $PreviousSetting.azureADJoin.localAdmins.registeringUsers.'@odata.type' = $DesiredOdataType
                Write-LogMessage -API 'Standards' -tenant $Tenant -message "Set registering users local administrator rights to $DesiredStateText." -sev Info
            } catch {
                $ErrorMessage = Get-CippException -Exception $_
                Write-LogMessage -API 'Standards' -tenant $Tenant -message "Failed to set registering users local administrator rights to $DesiredStateText. Error: $($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage
            }
        }
    }

    if ($Settings.alert -eq $true) {
        if ($StateIsCorrect -eq $true) {
            Write-LogMessage -API 'Standards' -tenant $Tenant -message "Registering users local administrator rights are $DesiredStateText as configured." -sev Info
        } else {
            Write-StandardsAlert -message "Registering users local administrator rights are not $DesiredStateText" -object @{ current = $CurrentOdataType; desired = $DesiredOdataType } -tenant $Tenant -standardName 'intuneDeviceRegLocalAdmins' -standardId $Settings.standardId
            Write-LogMessage -API 'Standards' -tenant $Tenant -message "Registering users local administrator rights are not $DesiredStateText." -sev Info
        }
    }

    if ($Settings.report -eq $true) {
        $CurrentValue = @{
            registeringUsers = @{
                '@odata.type' = $CurrentOdataType
            }
        }
        $ExpectedValue = @{
            registeringUsers = @{
                '@odata.type' = $DesiredOdataType
            }
        }
        Set-CIPPStandardsCompareField -FieldName 'standards.intuneDeviceRegLocalAdmins' -CurrentValue $CurrentValue -ExpectedValue $ExpectedValue -TenantFilter $Tenant
        Add-CIPPBPAField -FieldName 'intuneDeviceRegLocalAdmins' -FieldValue $StateIsCorrect -StoreAs bool -Tenant $Tenant
    }
}
