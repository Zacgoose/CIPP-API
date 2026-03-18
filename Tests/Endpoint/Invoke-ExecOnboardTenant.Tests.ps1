# Pester tests for Invoke-ExecOnboardTenant
# Validates onboarding status polling and retry behavior

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    $FunctionPath = Join-Path $RepoRoot 'Modules/CIPPCore/Public/Entrypoints/HTTP Functions/Tenant/Administration/Invoke-ExecOnboardTenant.ps1'

    class HttpResponseContext {
        [int]$StatusCode
        [object]$Body
    }

    enum HttpStatusCode {
        OK = 200
        BadRequest = 400
        NotFound = 404
    }

    Add-Type -AssemblyName System.Net.Http

    function Get-CIPPTable { param($TableName) @{} }
    function Get-CIPPAzDataTableEntity { param($Filter) }
    function Add-CIPPAzDataTableEntity { param($Entity, [switch]$Force) }
    function Start-CIPPOrchestrator { param($InputObject) 'instance-id' }
    function Write-LogMessage { param($headers, $API, $message, $Sev, $LogData) }
    function Get-NormalizedError { param($message) $message }

    . $FunctionPath
}

Describe 'Invoke-ExecOnboardTenant' {
    BeforeEach {
        $script:lastFilter = $null
        $script:startCount = 0
        $script:addCount = 0
        $script:startInput = $null
    }

    It 'returns existing onboarding record without restarting orchestration when not retrying' {
        Mock -CommandName Get-CIPPAzDataTableEntity -MockWith {
            param($Filter)
            $script:lastFilter = $Filter
            [pscustomobject]@{
                PartitionKey    = 'Onboarding'
                RowKey          = 'rel-123'
                Status          = 'running'
                OnboardingSteps = '{"Step1":{"Status":"succeeded","Title":"Step 1","Message":"Done"},"Step2":{"Status":"running","Title":"Step 2","Message":"In progress"}}'
                Relationship    = '{"customer":{"displayName":"Contoso"}}'
                Logs            = '[{"Date":"2026-03-18T00:00:00Z","Log":"Started"}]'
            }
        }
        Mock -CommandName Start-CIPPOrchestrator -MockWith {
            param($InputObject)
            $script:startCount++
            $script:startInput = $InputObject
            'instance-id'
        }
        Mock -CommandName Add-CIPPAzDataTableEntity -MockWith { $script:addCount++ }

        $request = [pscustomobject]@{
            Params  = @{ CIPPEndpoint = 'ExecOnboardTenant' }
            Headers = @{}
            Body    = [pscustomobject]@{
                id = 'rel-123'
            }
        }

        $response = Invoke-ExecOnboardTenant -Request $request -TriggerMetadata $null

        $response.StatusCode | Should -Be ([System.Net.HttpStatusCode]::OK)
        $response.Body.RowKey | Should -Be 'rel-123'
        $response.Body.Status | Should -Be 'running'
        $response.Body.OnboardingSteps[0].Status | Should -Be 'succeeded'
        $script:lastFilter | Should -Be "RowKey eq 'rel-123'"
        $script:startCount | Should -Be 0
        $script:addCount | Should -Be 0
    }

    It 'requeues onboarding when retry is explicitly requested' {
        Mock -CommandName Get-CIPPAzDataTableEntity -MockWith {
            param($Filter)
            $script:lastFilter = $Filter
            [pscustomobject]@{
                PartitionKey    = 'Onboarding'
                RowKey          = 'rel-456'
                Status          = 'failed'
                OnboardingSteps = '{"Step1":{"Status":"failed","Title":"Step 1","Message":"Failed"}}'
                Relationship    = ''
                Logs            = ''
            }
        }
        Mock -CommandName Start-CIPPOrchestrator -MockWith {
            param($InputObject)
            $script:startCount++
            $script:startInput = $InputObject
            'instance-id'
        }
        Mock -CommandName Add-CIPPAzDataTableEntity -MockWith { $script:addCount++ }

        $request = [pscustomobject]@{
            Params  = @{ CIPPEndpoint = 'ExecOnboardTenant' }
            Headers = @{}
            Body    = [pscustomobject]@{
                id    = 'rel-456'
                Retry = $true
            }
        }

        $response = Invoke-ExecOnboardTenant -Request $request -TriggerMetadata $null

        $response.StatusCode | Should -Be ([System.Net.HttpStatusCode]::OK)
        $script:lastFilter | Should -Be "RowKey eq 'rel-456'"
        $script:startCount | Should -Be 1
        $script:startInput.OrchestratorName | Should -Be 'OnboardingOrchestrator'
        $script:startInput.Batch[0].FunctionName | Should -Be 'ExecOnboardTenantQueue'
        $script:startInput.Batch[0].id | Should -Be 'rel-456'
        $script:addCount | Should -Be 1
        $response.Body.Status | Should -Be 'queued'
    }
}
