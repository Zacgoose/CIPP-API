# Pester tests for Invoke-ExecUserSettings
# Validates saving user settings for both string and object user payloads
using namespace System.Net

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    $FunctionPath = Join-Path $RepoRoot 'Modules/CIPPCore/Public/Entrypoints/Invoke-ExecUserSettings.ps1'

    class HttpResponseContext {
        [int]$StatusCode
        [object]$Body
    }

    Add-Type -AssemblyName System.Net.Http

    function Get-CippTable { param($tablename) @{ TableName = $tablename } }
    function Add-CIPPAzDataTableEntity {
        param($TableName, $Force, $Entity)
        $script:lastEntity = $Entity
    }
    function Get-NormalizedError { param($message) $message }

    . $FunctionPath
}

Describe 'Invoke-ExecUserSettings' {
    BeforeEach {
        $script:lastEntity = $null
    }

    It 'stores settings using a string user row key' {
        $request = [pscustomobject]@{
            Body = [pscustomobject]@{
                user            = 'alex@contoso.com'
                currentSettings = [pscustomobject]@{
                    paletteMode = 'dark'
                }
            }
        }

        $response = Invoke-ExecUserSettings -Request $request -TriggerMetadata $null

        $response.StatusCode | Should -Be ([System.Net.HttpStatusCode]::OK)
        $lastEntity.RowKey | Should -Be 'alex@contoso.com'
        $lastEntity.PartitionKey | Should -Be 'UserSettings'
        $lastEntity.JSON | Should -Match '"paletteMode":"dark"'
    }

    It 'uses userDetails when user payload is an object and preserves bookmark order' {
        $request = [pscustomobject]@{
            Body = [pscustomobject]@{
                user            = [pscustomobject]@{
                    userDetails = 'jamie@contoso.com'
                    userId      = '123'
                }
                currentSettings = [pscustomobject]@{
                    bookmarks = @(
                        [pscustomobject]@{ label = 'Dashboard'; path = '/dashboardv2' }
                        [pscustomobject]@{ label = 'Users'; path = '/identity/administration/users' }
                    )
                }
            }
        }

        $response = Invoke-ExecUserSettings -Request $request -TriggerMetadata $null

        $response.StatusCode | Should -Be ([System.Net.HttpStatusCode]::OK)
        $lastEntity.RowKey | Should -Be 'jamie@contoso.com'

        $bookmarks = (ConvertFrom-Json $lastEntity.JSON -Depth 10).bookmarks
        $bookmarks[0].label | Should -Be 'Dashboard'
        $bookmarks[1].label | Should -Be 'Users'
    }
}
