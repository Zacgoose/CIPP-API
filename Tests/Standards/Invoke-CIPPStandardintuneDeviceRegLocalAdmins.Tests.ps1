BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    $StandardPath = Join-Path $RepoRoot 'Modules/CIPPCore/Public/Standards/Invoke-CIPPStandardintuneDeviceRegLocalAdmins.ps1'

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
        $script:alerts = @()
        $script:compareFields = @()
        $script:bpaFields = @()
        $script:lastBody = $null

        Mock -CommandName New-GraphGETRequest -MockWith {
            [pscustomobject]@{
                azureADJoin = @{
                    localAdmins = @{
                        enableGlobalAdmins = $true
                        registeringUsers   = @{
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

    It 'uses direct settings object values and remediates both local admin options' {
        $settings = @{
            disableRegisteringUsers = $true
            enableGlobalAdmins      = $false
            remediate               = $true
            alert                   = $false
            report                  = $false
        }

        Invoke-CIPPStandardintuneDeviceRegLocalAdmins -Tenant $tenant -Settings $settings

        Should -Invoke New-GraphPOSTRequest -ParameterFilter { $Type -eq 'PUT' -and $Uri -eq 'https://graph.microsoft.com/beta/policies/deviceRegistrationPolicy' } -Times 1
        $parsedBody = $lastBody | ConvertFrom-Json
        $parsedBody.azureADJoin.localAdmins.registeringUsers.'@odata.type' | Should -Be '#microsoft.graph.noDeviceRegistrationMembership'
        $parsedBody.azureADJoin.localAdmins.enableGlobalAdmins | Should -BeFalse
    }

    It 'alerts when settings drift and reports expected values' {
        $settings = @{
            disableRegisteringUsers = $true
            enableGlobalAdmins      = $false
            remediate               = $false
            alert                   = $true
            report                  = $true
            standardId              = 'std-123'
        }

        Invoke-CIPPStandardintuneDeviceRegLocalAdmins -Tenant $tenant -Settings $settings

        $alerts | Should -HaveCount 1
        $alerts[0].Standard | Should -Be 'intuneDeviceRegLocalAdmins'
        $alerts[0].Object.current.enableGlobalAdmins | Should -BeTrue
        $compareFields | Should -HaveCount 1
        $compareFields[0].Expected.enableGlobalAdmins | Should -BeFalse
        $compareFields[0].Expected.registeringUsers.'@odata.type' | Should -Be '#microsoft.graph.noDeviceRegistrationMembership'
        $bpaFields | Should -HaveCount 1
        $bpaFields[0].Value | Should -BeFalse
    }

    It 'returns without remediation when required input values are missing' {
        $settings = @{
            disableRegisteringUsers = $true
            remediate               = $true
            alert                   = $false
            report                  = $false
        }

        Invoke-CIPPStandardintuneDeviceRegLocalAdmins -Tenant $tenant -Settings $settings

        Should -Invoke New-GraphPOSTRequest -Times 0
    }
}
