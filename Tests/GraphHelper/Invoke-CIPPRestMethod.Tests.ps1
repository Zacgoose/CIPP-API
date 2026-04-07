# Pester tests for Invoke-CIPPRestMethod

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    $FunctionPath = Join-Path $RepoRoot 'Modules/CIPPCore/Public/GraphHelper/Invoke-CIPPRestMethod.ps1'
    . $FunctionPath
}

Describe 'Invoke-CIPPRestMethod' {
    It 'uses Invoke-RestMethod in legacy mode' {
        Mock Invoke-RestMethod {
            return [pscustomobject]@{ ok = $true }
        } -Verifiable

        $result = Invoke-CIPPRestMethod -Uri 'https://example.com/test' -Method 'GET' -Headers @{ Authorization = 'Bearer token' } -UseLegacyInvokeRestMethod

        $result.ok | Should -BeTrue
        Should -Invoke Invoke-RestMethod -Times 1 -Exactly
    }

    It 'passes response variable parameters in legacy mode' {
        Mock Invoke-RestMethod {
            return [pscustomobject]@{ ok = $true }
        }

        $null = Invoke-CIPPRestMethod -Uri 'https://example.com/test' -Method 'POST' -Body '{}' -ContentType 'application/json' -ResponseHeadersVariable 'responseHeaders' -StatusCodeVariable 'responseStatus' -UseLegacyInvokeRestMethod

        Should -Invoke Invoke-RestMethod -Times 1 -Exactly -ParameterFilter {
            $ResponseHeadersVariable -eq 'responseHeaders' -and $StatusCodeVariable -eq 'responseStatus'
        }
    }

    It 'uses HttpClient mode by default instead of Invoke-RestMethod' {
        Mock Invoke-RestMethod { throw 'Should not be called' }

        { Invoke-CIPPRestMethod -Uri 'mailto:test@example.com' } | Should -Throw
        Should -Invoke Invoke-RestMethod -Times 0
    }
}
