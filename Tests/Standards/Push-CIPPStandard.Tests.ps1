# Pester tests for Push-CIPPStandard

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    $FunctionPath = Join-Path $RepoRoot 'Modules/CIPPCore/Public/Entrypoints/Activity Triggers/Standards/Push-CIPPStandard.ps1'

    function Measure-CippTask { param($TaskName, $EventName, $Metadata, $Script) }
    function Write-LogMessage { param($API, $tenant, $message, $sev, $LogData, $Headers) }
    function Get-CIPPTextReplacement { param($TenantFilter, $Text) $Text }
    function Get-CippException { param($Exception) $Exception }
    function Invoke-CIPPStandardAuditLog { param($Tenant, $Settings) }
    function Test-CIPPRerun { param($TenantFilter, $Type, $API, $Settings, $Headers, $Clear, $ClearAll) }

    . $FunctionPath
}

Describe 'Push-CIPPStandard' {
    BeforeEach {
        $script:CapturedAPI = $null

        Mock -CommandName Test-CIPPRerun -MockWith {
            param(
                $TenantFilter,
                $Type,
                $API
            )
            $script:CapturedAPI = $API
            return $false
        }

        Mock -CommandName Measure-CippTask -MockWith {
            param($TaskName, $EventName, $Metadata, $Script)
        }
    }

    It 'omits trailing underscore when templateId is missing' {
        $item = [pscustomobject]@{
            Tenant     = 'contoso.onmicrosoft.com'
            Standard   = 'AuditLog'
            templateId = $null
            Settings   = [pscustomobject]@{}
        }

        Push-CIPPStandard -Item $item

        $CapturedAPI | Should -Be 'AuditLog'
    }
}
