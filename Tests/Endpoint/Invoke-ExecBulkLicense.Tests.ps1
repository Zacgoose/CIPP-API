# Pester tests for Invoke-ExecBulkLicense
BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    $FunctionPath = Join-Path $RepoRoot 'Modules/CIPPCore/Public/Entrypoints/HTTP Functions/Identity/Administration/Users/Invoke-ExecBulkLicense.ps1'

    class HttpResponseContext {
        [int]$StatusCode
        [object]$Body
    }

    function New-GraphGetRequest {
        param($uri, $tenantid)
        $script:graphUris += $uri
        $Ids = [regex]::Matches($uri, "id eq '([^']+)'") | ForEach-Object { $_.Groups[1].Value }
        return @($Ids | ForEach-Object { [pscustomobject]@{ id = $_; userPrincipalName = "$_@contoso.com"; assignedLicenses = @() } })
    }
    function Set-CIPPUserLicense { param($LicenseRequests, $TenantFilter, $APIName, $Headers) return @("Processed $($LicenseRequests.Count) users") }
    function Write-LogMessage { param($API, $tenant, $message, $Sev, $LogData) }
    function Get-CippException { param($Exception) return [pscustomobject]@{ NormalizedError = $Exception.Exception.Message } }

    . $FunctionPath
}

Describe 'Invoke-ExecBulkLicense' {
    BeforeEach {
        $script:graphUris = @()
    }

    It 'batches user lookup filters to avoid Graph OR clause limits' {
        $userRequests = @(1..16 | ForEach-Object {
                [pscustomobject]@{
                    tenantFilter      = 'contoso.onmicrosoft.com'
                    userIds           = "user$_"
                    LicenseOperation  = 'Add'
                    RemoveAllLicenses = $false
                    ReplaceAllLicenses = $false
                    Licenses          = @([pscustomobject]@{ value = 'sku-1' })
                    LicensesToRemove  = @()
                    LicensesToReplace = @()
                }
            })

        $request = [pscustomobject]@{
            Params  = @{ CIPPEndpoint = 'ExecBulkLicense' }
            Headers = @{}
            Body    = $userRequests
        }

        $response = Invoke-ExecBulkLicense -Request $request -TriggerMetadata $null

        $response.StatusCode | Should -Be ([System.Net.HttpStatusCode]::OK)
        $graphUris.Count | Should -Be 2
        $graphUris | ForEach-Object {
            ([regex]::Matches($_, "id eq '")).Count | Should -BeLessOrEqual 15
        }
    }
}
    $TypeAccelerators = [psobject].Assembly.GetType('System.Management.Automation.TypeAccelerators')
    if (-not $TypeAccelerators::Get.ContainsKey('HttpStatusCode')) {
        $TypeAccelerators::Add('HttpStatusCode', [System.Net.HttpStatusCode])
    }
