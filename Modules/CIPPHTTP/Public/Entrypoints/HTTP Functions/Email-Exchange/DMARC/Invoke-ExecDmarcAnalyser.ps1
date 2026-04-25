function Invoke-ExecDmarcAnalyser {
    <#
    .FUNCTIONALITY
        Entrypoint,AnyTenant
    .ROLE
        Exchange.Mailbox.ReadWrite
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    $Headers = $Request.Headers

    try {
        $Result = Start-DmarcOrchestrator
        if ($Result -eq 0) {
            $Message = 'No tenants enrolled for DMARC processing'
        } elseif ($Result -eq $false) {
            $Message = 'DMARC Processor failed to start'
        } else {
            $Message = 'DMARC Processor started successfully'
        }
        Write-LogMessage -API $APIName -headers $Headers -message $Message -sev Info
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -API $APIName -headers $Headers -message "Failed to start DMARC Processor: $($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage
        return [HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::InternalServerError
            Body       = @{ Results = "Failed: $($ErrorMessage.NormalizedError)" }
        }
    }

    return [HttpResponseContext]@{
        StatusCode = [HttpStatusCode]::OK
        Body       = @{ Results = $Message }
    }
}
