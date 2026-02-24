# Pester tests for Invoke-ExecBulkLicense

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    $FunctionPath = Join-Path $RepoRoot 'Modules/CIPPCore/Public/Entrypoints/HTTP Functions/Identity/Administration/Users/Invoke-ExecBulkLicense.ps1'

    class HttpResponseContext {
        [int]$StatusCode
        [object]$Body
    }
    if (-not ('HttpStatusCode' -as [Type])) {
        Add-Type -TypeDefinition 'public enum HttpStatusCode { OK = 200, BadRequest = 400 }'
    }

    function New-GraphGetRequest {
        param($uri, $tenantid)
        $script:graphRequestUris += $uri
        $Ids = [regex]::Matches($uri, "id eq '([^']+)'") | ForEach-Object { $_.Groups[1].Value }
        foreach ($Id in $Ids) {
            [pscustomobject]@{
                id               = $Id
                userPrincipalName = "$Id@contoso.com"
                assignedLicenses = @()
            }
        }
    }

    function Set-CIPPUserLicense {
        param([System.Collections.Generic.List[object]]$LicenseRequests, $TenantFilter, $APIName, $Headers)
        $script:lastLicenseRequests = $LicenseRequests
        return @("Processed $($LicenseRequests.Count) users")
    }

    function Write-LogMessage { param() }
    function Get-CippException { param($Exception) return $Exception }

    . $FunctionPath
}

Describe 'Invoke-ExecBulkLicense' {
    BeforeEach {
        $script:graphRequestUris = @()
        $script:lastLicenseRequests = $null
    }

    It 'chunks user filter queries to avoid Graph OR clause limits' {
        $RequestBody = for ($i = 1; $i -le 72; $i++) {
            [pscustomobject]@{
                tenantFilter      = 'contoso.onmicrosoft.com'
                userIds           = "user$i"
                LicenseOperation  = 'Add'
                RemoveAllLicenses = $false
                ReplaceAllLicenses = $false
                Licenses          = @([pscustomobject]@{ value = 'sku-1' })
                LicensesToRemove  = @()
                LicensesToReplace = @()
            }
        }

        $Request = [pscustomobject]@{
            Params  = @{ CIPPEndpoint = 'ExecBulkLicense' }
            Headers = @{}
            Body    = $RequestBody
        }

        $Response = Invoke-ExecBulkLicense -Request $Request -TriggerMetadata $null

        $Response.StatusCode | Should -Be ([System.Net.HttpStatusCode]::OK)
        $graphRequestUris.Count | Should -Be 2
        foreach ($Uri in $graphRequestUris) {
            ([regex]::Matches($Uri, "id eq '")).Count | Should -BeLessOrEqual 70
        }
        $lastLicenseRequests.Count | Should -Be 72
    }
}
