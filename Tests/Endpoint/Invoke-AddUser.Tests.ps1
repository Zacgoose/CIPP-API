using namespace System.Net
# Pester tests for Invoke-AddUser

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    $FunctionPath = Join-Path $RepoRoot 'Modules/CIPPCore/Public/Entrypoints/HTTP Functions/Identity/Administration/Users/Invoke-AddUser.ps1'

    class HttpResponseContext {
        [int]$StatusCode
        [object]$Body
    }
    enum HttpStatusCode {
        OK = 200
        BadRequest = 400
        InternalServerError = 500
    }

    function New-CIPPUserTask {
        throw @{ Results = @('Failed to create user. Error:Another object with the same value for property userPrincipalName already exists.') }
    }

    . $FunctionPath
}

Describe 'Invoke-AddUser' {
    It 'returns the detailed New-CIPPUserTask error instead of System.Collections.Hashtable' {
        $request = [pscustomobject]@{
            Params  = @{ CIPPEndpoint = 'AddUser' }
            Headers = @{}
            Body    = [pscustomobject]@{
                tenantFilter = 'contoso.onmicrosoft.com'
                Scheduled    = [pscustomobject]@{ Enabled = $false }
            }
        }

        $response = Invoke-AddUser -Request $request -TriggerMetadata $null

        $response.StatusCode | Should -Be ([System.Net.HttpStatusCode]::InternalServerError)
        $response.Body.Results[0] | Should -Be 'Failed to create user. Error:Another object with the same value for property userPrincipalName already exists.'
        $response.Body.Results[0] | Should -Not -Be 'System.Collections.Hashtable'
    }
}
