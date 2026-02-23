BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    $StandardPath = Join-Path $RepoRoot 'Modules/CIPPCore/Public/Standards/Invoke-CIPPStandardintuneDeviceRegLocalAdmins.ps1'

    function Test-CIPPStandardLicense { param($StandardName, $TenantFilter, $RequiredCapabilities) }
    function New-GraphGETRequest { param($uri, $tenantid) }
    function New-GraphPOSTRequest { param($tenantid, $Uri, $Type, $Body, $ContentType) }
    function Write-LogMessage { param($API, $tenant, $message, $sev, $LogData) }
    function Write-StandardsAlert { param($message, $object, $tenant, $standardName, $standardId) }
    function Set-CIPPStandardsCompareField { param($FieldName, $CurrentValue, $ExpectedValue, $TenantFilter) }
    function Add-CIPPBPAField { param($FieldName, $FieldValue, $StoreAs, $Tenant) }
    function Get-CippException { param($Exception) [pscustomobject]@{ NormalizedError = $Exception.Message } }

    . $StandardPath
}

Describe 'Invoke-CIPPStandardintuneDeviceRegLocalAdmins' {
    $tenant = 'contoso.onmicrosoft.com'

    BeforeEach {
        $script:compareFields = @()
        $script:alerts = @()
        $script:bpaFields = @()
        $script:lastBody = $null

        Mock -CommandName Test-CIPPStandardLicense -MockWith { $true }
        Mock -CommandName New-GraphGETRequest -MockWith {
            [pscustomobject]@{
                azureADJoin = @{
                    localAdmins = @{
                        enableGlobalAdmins = $true
                        registeringUsers = @{
                            '@odata.type' = '#microsoft.graph.allDeviceRegistrationMembership'
                        }
                    }
                }
            }
        }
        Mock -CommandName New-GraphPOSTRequest -MockWith {
            param($tenantid, $Uri, $Type, $Body, $ContentType)
            $script:lastBody = $Body
        }
        Mock -CommandName Write-StandardsAlert -MockWith {
            param($message, $object, $tenant, $standardName, $standardId)
            $script:alerts += @{ Message = $message; Object = $object; Standard = $standardName; Id = $standardId }
        }
        Mock -CommandName Set-CIPPStandardsCompareField -MockWith {
            param($FieldName, $CurrentValue, $ExpectedValue, $TenantFilter)
            $script:compareFields += @{ Field = $FieldName; Current = $CurrentValue; Expected = $ExpectedValue; Tenant = $TenantFilter }
        }
        Mock -CommandName Add-CIPPBPAField -MockWith {
            param($FieldName, $FieldValue, $StoreAs, $Tenant)
            $script:bpaFields += @{ Field = $FieldName; Value = $FieldValue; StoreAs = $StoreAs; Tenant = $Tenant }
        }
    }

    It 'returns true and exits when license requirement fails' {
        Mock -CommandName Test-CIPPStandardLicense -MockWith { $false }

        $result = Invoke-CIPPStandardintuneDeviceRegLocalAdmins -Tenant $tenant -Settings @{ disableRegisteringUsers = $true }

        $result | Should -BeTrue
        Should -Invoke New-GraphGETRequest -Times 0
    }

    It 'remediates by setting registering users and global admins based on label/value options' {
        $settings = @{
            disableRegisteringUsers = @{ label = 'Disable registering users as local administrators'; value = $true }
            enableGlobalAdmins      = @{ label = 'Allow Global Administrators to be local administrators'; value = $false }
            remediate               = $true
            alert                   = $false
            report                  = $false
        }

        Invoke-CIPPStandardintuneDeviceRegLocalAdmins -Tenant $tenant -Settings $settings

        Should -Invoke New-GraphPOSTRequest -ParameterFilter { $Type -eq 'PUT' -and $Uri -eq 'https://graph.microsoft.com/beta/policies/deviceRegistrationPolicy' } -Times 1
        ($lastBody | ConvertFrom-Json).azureADJoin.localAdmins.registeringUsers.'@odata.type' | Should -Be '#microsoft.graph.noDeviceRegistrationMembership'
        ($lastBody | ConvertFrom-Json).azureADJoin.localAdmins.enableGlobalAdmins | Should -BeFalse
    }

    It 'writes alert when current state does not match desired state' {
        $settings = @{ disableRegisteringUsers = $true; enableGlobalAdmins = $false; remediate = $false; alert = $true; report = $false; standardId = 'std-123' }

        Invoke-CIPPStandardintuneDeviceRegLocalAdmins -Tenant $tenant -Settings $settings

        $alerts | Should -HaveCount 1
        $alerts[0].Standard | Should -Be 'intuneDeviceRegLocalAdmins'
        $alerts[0].Id | Should -Be 'std-123'
        $alerts[0].Object.current.registeringUsers | Should -Be '#microsoft.graph.allDeviceRegistrationMembership'
        $alerts[0].Object.current.enableGlobalAdmins | Should -BeTrue
    }

    It 'writes report compare and BPA fields based on compliance state' {
        $settings = @{
            disableRegisteringUsers = @{ label = 'Disable registering users as local administrators'; value = $false }
            enableGlobalAdmins      = @{ label = 'Allow Global Administrators to be local administrators'; value = $true }
            remediate               = $false
            alert                   = $false
            report                  = $true
        }

        Invoke-CIPPStandardintuneDeviceRegLocalAdmins -Tenant $tenant -Settings $settings

        $compareFields | Should -HaveCount 1
        $compareFields[0].Field | Should -Be 'standards.intuneDeviceRegLocalAdmins'
        $compareFields[0].Expected.registeringUsers.'@odata.type' | Should -Be '#microsoft.graph.allDeviceRegistrationMembership'
        $compareFields[0].Expected.enableGlobalAdmins | Should -BeTrue
        $bpaFields | Should -HaveCount 1
        $bpaFields[0].Value | Should -BeTrue
    }
}
