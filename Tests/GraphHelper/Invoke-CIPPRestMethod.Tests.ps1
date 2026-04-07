# Pester tests for Invoke-CIPPRestMethod

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    $FunctionPath = Join-Path $RepoRoot 'Modules/CIPPCore/Public/GraphHelper/Invoke-CIPPRestMethod.ps1'
    . $FunctionPath
}

Describe 'Invoke-CIPPRestMethod' {
    BeforeEach {
        $script:CIPPHttpClient = $null
        $script:CIPPHttpClientLock = $null
    }

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

    It 'uses form-url-encoding for hashtable body without an explicit content type' {
        $Observed = @{}
        $script:CIPPHttpClient = [pscustomobject]@{}
        $script:CIPPHttpClient | Add-Member -MemberType ScriptMethod -Name SendAsync -Value {
            param($Request, $CancellationToken)
            $Observed.ContentType = $Request.Content.Headers.ContentType.MediaType
            $Observed.Body = $Request.Content.ReadAsStringAsync().GetAwaiter().GetResult()
            $Response = [System.Net.Http.HttpResponseMessage]::new([System.Net.HttpStatusCode]::OK)
            $Response.Content = [System.Net.Http.StringContent]::new('{"ok":true}', [System.Text.Encoding]::UTF8, 'application/json')
            return [System.Threading.Tasks.Task[System.Net.Http.HttpResponseMessage]]::FromResult($Response)
        }

        $null = Invoke-CIPPRestMethod -Uri 'https://example.com/token' -Method 'POST' -Body @{
            client_id  = 'test-client-id'
            grant_type = 'refresh_token'
        }

        $Observed.ContentType | Should -Be 'application/x-www-form-urlencoded'
        $Observed.Body | Should -Match '(^|&)client_id=test-client-id(&|$)'
        $Observed.Body | Should -Match '(^|&)grant_type=refresh_token(&|$)'
    }
}
