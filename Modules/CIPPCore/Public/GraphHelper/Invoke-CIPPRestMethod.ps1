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

        [ValidateSet('GET', 'POST', 'PUT', 'PATCH', 'DELETE', 'HEAD', 'OPTIONS', 'TRACE')]
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

    if ($UseLegacyInvokeRestMethod) {
        return Invoke-RestMethod @RestMethodParams
    }

    if (-not $script:CIPPHttpClient) {
        $Handler = [System.Net.Http.SocketsHttpHandler]::new()
        $Handler.AutomaticDecompression = [System.Net.DecompressionMethods]::All
        $script:CIPPHttpClient = [System.Net.Http.HttpClient]::new($Handler)
    }

    $Request = [System.Net.Http.HttpRequestMessage]::new([System.Net.Http.HttpMethod]::new($Method), $Uri)
    $Response = $null
    $Timeout = [System.Threading.CancellationTokenSource]::new([TimeSpan]::FromSeconds([Math]::Max(1, $TimeoutSec)))

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
            if ($RequestBody -isnot [string] -and $ContentType -and $ContentType -like 'application/json*') {
                $RequestBody = $RequestBody | ConvertTo-Json -Depth 20 -Compress
            }
            $BodyText = if ($null -eq $RequestBody) { '' } else { [string]$RequestBody }
            $EffectiveContentType = if ($ContentType) { $ContentType } else { 'application/json' }
            $Request.Content = [System.Net.Http.StringContent]::new($BodyText, [System.Text.Encoding]::UTF8, $EffectiveContentType)
        }

        foreach ($Key in $DeferredContentHeaders.Keys) {
            if (-not $Request.Content) {
                $Request.Content = [System.Net.Http.StringContent]::new('', [System.Text.Encoding]::UTF8)
            }
            $Request.Content.Headers.Remove($Key) | Out-Null
            $null = $Request.Content.Headers.TryAddWithoutValidation($Key, $DeferredContentHeaders[$Key])
        }

        $Response = $script:CIPPHttpClient.SendAsync($Request, $Timeout.Token).GetAwaiter().GetResult()
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
            throw "Response status code does not indicate success: $StatusCode. Response body: $Content"
        }

        if ([string]::IsNullOrWhiteSpace($Content)) {
            return $null
        }

        $MediaType = if ($Response.Content.Headers.ContentType) { $Response.Content.Headers.ContentType.MediaType } else { '' }
        if ($MediaType -like 'application/json*' -or $Content.TrimStart().StartsWith('{') -or $Content.TrimStart().StartsWith('[')) {
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
        $Timeout.Dispose()
    }
}
