BeforeAll {
    $script:RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    $FunctionPath = Join-Path $script:RepoRoot 'Modules/CIPPCore/Public/Get-CIPPTimerFunctions.ps1'

    function Get-CIPPTable { param($TableName) }
    function Get-CIPPAzDataTableEntity { param($Table, $Filter, $Property) }
    function Get-CIPPFeatureFlag {}
    function Add-CIPPAzDataTableEntity { param($Table, $Entity, [switch]$Force) }
    function Remove-AzDataTableEntity { param($Table, $Entity, [switch]$Force) }

    . $FunctionPath
}

Describe 'Get-CIPPTimerFunctions schedule matching' {
    BeforeEach {
        $script:FixedNow = [datetime]'2026-03-18T12:20:00Z'
        $script:Statuses = @()
        $script:SavedStatuses = @()

        $env:WEBSITE_SITE_NAME = 'cipp-standards'
        $env:CIPP_PROCESSOR = 'true'

        Mock -CommandName Get-Date -MockWith { $script:FixedNow }
        Mock -CommandName Get-Module -MockWith {
            [pscustomobject]@{
                ModuleBase = (Join-Path $script:RepoRoot 'Modules/CIPPCore')
            }
        }
        Mock -CommandName Get-CIPPFeatureFlag -MockWith { @() }
        Mock -CommandName Get-CIPPTable -MockWith {
            param($TableName)
            @{ TableName = $TableName }
        }
        Mock -CommandName Get-Content -MockWith {
            @'
[
  {
    "Id": "9b0c8e50-f798-49db-9a8b-dbcc0fcadeea",
    "Command": "Start-StandardsOrchestrator",
    "Cron": "0 0 */12 * * *",
    "Priority": 4,
    "RunOnProcessor": true,
    "PreferredProcessor": "standards"
  }
]
'@
        }
        Mock -CommandName Get-Command -MockWith { @{ Name = 'Start-StandardsOrchestrator' } }
        Mock -CommandName Add-CIPPAzDataTableEntity -MockWith {
            param($Table, $Entity, [switch]$Force)
            $script:SavedStatuses += $Entity
        }
        Mock -CommandName Remove-AzDataTableEntity -MockWith {}
        Mock -CommandName Get-CIPPAzDataTableEntity -MockWith {
            param($Table, $Filter, $Property)

            if ($Filter -like "*PartitionKey eq 'OffloadFunctions'*") {
                return $null
            }

            if ($Filter -like "*PartitionKey eq 'Version'*") {
                return @(
                    [pscustomobject]@{ RowKey = 'cipp-standards'; Version = '1.0.0' }
                    [pscustomobject]@{ RowKey = 'cipp-standards-standards'; Version = '1.0.0' }
                )
            }

            if ($Table.TableName -eq 'CIPPTimers') {
                return $script:Statuses
            }

            return @()
        }
    }

    It 'returns standards timer details when listing all tasks' {
        $script:Statuses = @(
            [pscustomobject]@{
                PartitionKey       = 'Timer'
                RowKey             = '9b0c8e50-f798-49db-9a8b-dbcc0fcadeea'
                Command            = 'Start-StandardsOrchestrator'
                Cron               = '0 0 */12 * * *'
                LastOccurrence     = [datetime]'2026-03-17T12:00:00Z'
                NextOccurrence     = [datetime]'2026-03-18T12:00:00Z'
                Status             = 'Completed'
                OrchestratorId     = ''
                RunOnProcessor     = $true
                PreferredProcessor = 'standards'
                IsSystem           = $false
                ErrorMsg           = ''
            }
        )

        $result = @(Get-CIPPTimerFunctions -ListAllTasks)

        $result | Should -HaveCount 1
        $result[0].Command | Should -Be 'Start-StandardsOrchestrator'
        $result[0].NextOccurrence | Should -BeGreaterThan $script:FixedNow
    }

    It 'does not schedule standards timer when next occurrence after LastOccurrence is still in the future' {
        $script:Statuses = @(
            [pscustomobject]@{
                PartitionKey       = 'Timer'
                RowKey             = '9b0c8e50-f798-49db-9a8b-dbcc0fcadeea'
                Command            = 'Start-StandardsOrchestrator'
                Cron               = '0 0 */12 * * *'
                LastOccurrence     = [pscustomobject]@{ DateTime = [datetime]'2026-03-18T12:10:00Z' }
                NextOccurrence     = [datetime]'2026-03-19T00:00:00Z'
                Status             = 'Completed'
                OrchestratorId     = ''
                RunOnProcessor     = $true
                PreferredProcessor = 'standards'
                IsSystem           = $false
                ErrorMsg           = ''
            }
        )

        $result = @(Get-CIPPTimerFunctions)

        $result | Should -BeNullOrEmpty
    }
}
