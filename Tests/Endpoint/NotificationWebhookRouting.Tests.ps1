# Pester tests for notification webhook routing configuration

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    $SetConfigPath = Join-Path $RepoRoot 'Modules/CIPPCore/Public/Set-CIPPNotificationConfig.ps1'
    $ScheduledAlertPath = Join-Path $RepoRoot 'Modules/CIPPCore/Public/Send-CIPPScheduledTaskAlert.ps1'

    function Get-CippTable { param($tablename) @{ TableName = $tablename } }
    function Add-CIPPAzDataTableEntity { param($Entity, [switch]$Force) $script:lastEntity = $Entity }
    function Get-Tenants { param($TenantFilter) [pscustomobject]@{ customerId = 'tenant-id' } }
    function Get-CIPPTextReplacement { param($Text, $TenantFilter) $Text }
    function Send-CIPPAlert { param($Type, $Title, $HTMLContent, $TenantFilter, $JSONContent, $altWebhook) $script:lastAlert = @{ Type = $Type; altWebhook = $altWebhook } }
    function Write-LogMessage { param() }

    . $SetConfigPath
    . $ScheduledAlertPath
}

Describe 'Notification webhook routing' {
    BeforeEach {
        $script:lastEntity = $null
        $script:lastAlert = $null
    }

    It 'stores scoped webhook settings in notification config' {
        $result = Set-CIPPNotificationConfig `
            -email 'ops@contoso.com' `
            -webhook 'https://default.example/webhook' `
            -offboardingWebhook 'https://default.example/offboarding' `
            -driftWebhook 'https://default.example/drift' `
            -onepertenant $true `
            -logsToInclude @(@{ value = 'Warning' }) `
            -sendtoIntegration $false `
            -sev 'Alert'

        $result | Should -Be 'Successfully set the configuration'
        $script:lastEntity.webhook | Should -Be 'https://default.example/webhook'
        $script:lastEntity.offboardingWebhook | Should -Be 'https://default.example/offboarding'
        $script:lastEntity.driftWebhook | Should -Be 'https://default.example/drift'
    }

    It 'uses offboarding webhook override for offboarding task alerts' {
        function Get-CIPPAzDataTableEntity {
            param($Filter)
            if ($Filter -eq "PartitionKey eq 'CippNotifications' and RowKey eq 'CippNotifications'") {
                return [pscustomobject]@{ offboardingWebhook = 'https://default.example/offboarding' }
            }
            return $null
        }

        $taskInfo = [pscustomobject]@{
            Name          = 'Offboarding: user@contoso.com'
            PostExecution = 'webhook'
        }

        Send-CIPPScheduledTaskAlert -Results @(@{ Results = 'Done' }) -TaskInfo $taskInfo -TenantFilter 'contoso.onmicrosoft.com' -TaskType 'Offboarding'

        $script:lastAlert.Type | Should -Be 'webhook'
        $script:lastAlert.altWebhook | Should -Be 'https://default.example/offboarding'
    }
}
