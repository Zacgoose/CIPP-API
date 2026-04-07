function Invoke-CIPPRestMethod {
    <#
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [Alias('Url')]
        [uri]$Uri,

        [ValidateSet('GET', 'POST', 'PUT', 'PATCH', 'DELETE', 'HEAD', 'OPTIONS')]
        [string]$Method = 'GET',

        [object]$Body,

        [hashtable]$Headers = @{},

        [string]$ContentType,

        [switch]$SkipHttpErrorCheck,

        [string]$ResponseHeadersVariable,

        [string]$StatusCodeVariable,

        [int]$TimeoutSec = 100,

        [switch]$UseLegacyInvokeRestMethod
    )

    $RestMethodParams = @{
        Uri         = $Uri
        Method      = $Method
        Headers     = $Headers
        ErrorAction = $ErrorActionPreference
    }

    if ($PSBoundParameters.ContainsKey('Body')) {
        $RestMethodParams['Body'] = $Body
    }

    if ($PSBoundParameters.ContainsKey('ContentType') -and $ContentType) {
        $RestMethodParams['ContentType'] = $ContentType
    }

    if ($SkipHttpErrorCheck) {
        $RestMethodParams['SkipHttpErrorCheck'] = $true
    }

    if ($ResponseHeadersVariable) {
        $RestMethodParams['ResponseHeadersVariable'] = $ResponseHeadersVariable
    }

    if ($StatusCodeVariable) {
        $RestMethodParams['StatusCodeVariable'] = $StatusCodeVariable
    }

    if ($TimeoutSec -gt 0) {
        $RestMethodParams['TimeoutSec'] = $TimeoutSec
    }

    if ($UseLegacyInvokeRestMethod) {
        return Invoke-RestMethod @RestMethodParams
    }

    if (-not $script:CIPPHttpClient) {
        if (-not $script:CIPPHttpClientLock) {
            $script:CIPPHttpClientLock = [System.Threading.SemaphoreSlim]::new(1, 1)
        }

        $null = $script:CIPPHttpClientLock.Wait()
        try {
            if (-not $script:CIPPHttpClient) {
                $Handler = [System.Net.Http.SocketsHttpHandler]::new()
                $Handler.AutomaticDecompression = [System.Net.DecompressionMethods]::All
                $script:CIPPHttpClient = [System.Net.Http.HttpClient]::new($Handler)
                $script:CIPPHttpClient.Timeout = [System.Threading.Timeout]::InfiniteTimeSpan
            }
        } finally {
            $null = $script:CIPPHttpClientLock.Release()
        }
    }

    $Request = [System.Net.Http.HttpRequestMessage]::new([System.Net.Http.HttpMethod]::new($Method), $Uri)
    $Response = $null
    $TimeoutCancellation = $null
    $CancellationToken = [System.Threading.CancellationToken]::None
    if ($TimeoutSec -gt 0) {
        $TimeoutCancellation = [System.Threading.CancellationTokenSource]::new([TimeSpan]::FromSeconds($TimeoutSec))
        $CancellationToken = $TimeoutCancellation.Token
    }

    try {
        $DeferredContentHeaders = @{}
        foreach ($Key in $Headers.Keys) {
            $Value = [string]$Headers[$Key]
            if (-not $Request.Headers.TryAddWithoutValidation($Key, $Value)) {
                $DeferredContentHeaders[$Key] = $Value
            }
        }

        if ($PSBoundParameters.ContainsKey('Body')) {
            $RequestBody = $Body
            $IsFormContentType = -not $ContentType -or $ContentType -like 'application/x-www-form-urlencoded*'
            $UseFormUrlEncoding = ($RequestBody -is [System.Collections.IDictionary]) -and $IsFormContentType
            if ($UseFormUrlEncoding) {
                $FormPairs = [System.Collections.Generic.List[System.Collections.Generic.KeyValuePair[string, string]]]::new()
                foreach ($Entry in $RequestBody.GetEnumerator()) {
                    $FormPairs.Add([System.Collections.Generic.KeyValuePair[string, string]]::new([string]$Entry.Key, [string]$Entry.Value))
                }
                $Request.Content = [System.Net.Http.FormUrlEncodedContent]::new($FormPairs)
            } else {
                if ($RequestBody -isnot [string] -and $ContentType -and $ContentType -like 'application/json*') {
                    $RequestBody = $RequestBody | ConvertTo-Json -Depth 20 -Compress
                }
                $BodyText = if ($null -eq $RequestBody) { '' } else { [string]$RequestBody }
                $EffectiveContentType = if ($ContentType) { $ContentType } else { 'application/json' }
                $Request.Content = [System.Net.Http.StringContent]::new($BodyText, [System.Text.Encoding]::UTF8, $EffectiveContentType)
            }
        }

        foreach ($Key in $DeferredContentHeaders.Keys) {
            if (-not $Request.Content) {
                $Request.Content = [System.Net.Http.StringContent]::new('', [System.Text.Encoding]::UTF8)
            }
            $Request.Content.Headers.Remove($Key) | Out-Null
            $null = $Request.Content.Headers.TryAddWithoutValidation($Key, $DeferredContentHeaders[$Key])
        }

        $Response = $script:CIPPHttpClient.SendAsync($Request, $CancellationToken).GetAwaiter().GetResult()
        $StatusCode = [int]$Response.StatusCode
        $Content = if ($Response.Content) { $Response.Content.ReadAsStringAsync().GetAwaiter().GetResult() } else { $null }

        if ($StatusCodeVariable) {
            Set-Variable -Scope 1 -Name $StatusCodeVariable -Value $StatusCode
        }

        if ($ResponseHeadersVariable) {
            $AllHeaders = @{}
            foreach ($Header in $Response.Headers) {
                $AllHeaders[$Header.Key] = [string[]]$Header.Value
            }
            if ($Response.Content) {
                foreach ($Header in $Response.Content.Headers) {
                    $AllHeaders[$Header.Key] = [string[]]$Header.Value
                }
            }
            Set-Variable -Scope 1 -Name $ResponseHeadersVariable -Value $AllHeaders
        }

        if (-not $SkipHttpErrorCheck -and -not $Response.IsSuccessStatusCode) {
            throw "Response status code does not indicate success: $StatusCode"
        }

        if ([string]::IsNullOrWhiteSpace($Content)) {
            return $null
        }

        $TrimmedContent = $Content.TrimStart()
        $MediaType = if ($Response.Content.Headers.ContentType) { $Response.Content.Headers.ContentType.MediaType } else { '' }
        if ($MediaType -like 'application/json*' -or $TrimmedContent.StartsWith('{') -or $TrimmedContent.StartsWith('[')) {
            try {
                return $Content | ConvertFrom-Json
            } catch {
                return $Content
            }
        }

        return $Content
    } finally {
        if ($Response) {
            $Response.Dispose()
        }
        $Request.Dispose()
        if ($TimeoutCancellation) {
            $TimeoutCancellation.Dispose()
        }
    }
}
