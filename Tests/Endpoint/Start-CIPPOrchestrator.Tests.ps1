# Pester tests for Start-CIPPOrchestrator
# Validates queue routing and explicit queue-trigger direct execution

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    $FunctionPath = Join-Path $RepoRoot 'Modules/CIPPCore/Public/Entrypoints/Orchestrator Functions/Start-CIPPOrchestrator.ps1'

    function Get-CippTable { param($TableName) @{} }
    function Add-CIPPAzDataTableEntity { param($Entity, [switch]$Force) }
    function Add-CippQueueMessage { param($Cmdlet, $Parameters) }
    function Start-NewOrchestration { param($FunctionName, $InputObject) 'instance-id' }
    function Get-CIPPAzDataTableEntity { param($Filter) }
    function Get-AzDataTableEntity { param($Filter, $Property) @() }
    function Remove-AzDataTableEntity { param($Entity, [switch]$Force) }

    . $FunctionPath
}

Describe 'Start-CIPPOrchestrator' {
    BeforeEach {
        $env:AzureWebJobs_CIPPOrchestrator_Disabled = 'false'
        $script:storeCount = 0
        $script:queueCount = 0
        $script:startCount = 0
        $script:queuedCmdlet = $null
    }

    It 'stores and queues input when called without CallerIsQueueTrigger' {
        Mock -CommandName Add-CIPPAzDataTableEntity -MockWith { $script:storeCount++ }
        Mock -CommandName Add-CippQueueMessage -MockWith {
            param($Cmdlet, $Parameters)
            $script:queueCount++
            $script:queuedCmdlet = $Cmdlet
        }
        Mock -CommandName Start-NewOrchestration -MockWith { $script:startCount++; 'instance-id' }

        $null = Start-CIPPOrchestrator -InputObject @{ OrchestratorName = 'OnboardingOrchestrator'; Batch = @(@{ FunctionName = 'ExecOnboardTenantQueue'; id = 'rel-1' }) }

        $script:storeCount | Should -Be 1
        $script:queueCount | Should -Be 1
        $script:queuedCmdlet | Should -Be 'Start-CIPPOrchestrator'
        $script:startCount | Should -Be 0
    }

    It 'starts orchestration directly when explicitly called by queue trigger' {
        Mock -CommandName Add-CIPPAzDataTableEntity -MockWith { $script:storeCount++ }
        Mock -CommandName Add-CippQueueMessage -MockWith { $script:queueCount++ }
        Mock -CommandName Start-NewOrchestration -MockWith { $script:startCount++; 'instance-id' }

        $result = Start-CIPPOrchestrator -InputObject @{ OrchestratorName = 'OnboardingOrchestrator'; Batch = @(@{ FunctionName = 'ExecOnboardTenantQueue'; id = 'rel-2' }) } -CallerIsQueueTrigger

        $result | Should -Be 'instance-id'
        $script:startCount | Should -Be 1
        $script:storeCount | Should -Be 0
        $script:queueCount | Should -Be 0
    }
}
