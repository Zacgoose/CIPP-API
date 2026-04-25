function Invoke-ListDmarcReports {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Exchange.Mailbox.Read
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $TenantFilter = $Request.Query.tenantFilter
    $Domain = $Request.Query.Domain
    $StartDate = $Request.Query.StartDate
    $EndDate = $Request.Query.EndDate

    $DmarcReportsTable = Get-CIPPTable -tablename 'DmarcReports'

    try {
        # Build server-side OData filter — DateRangeStart may be DateTime or int64 depending on when data was written
        $FilterParts = [System.Collections.Generic.List[string]]::new()
        $FilterParts.Add("PartitionKey eq '$TenantFilter'")

        if ($StartDate) {
            $ParsedStart = [datetime]::ParseExact($StartDate, 'yyyyMMdd', $null)
            $FilterParts.Add("DateRangeStart ge datetime'$($ParsedStart.ToString('yyyy-MM-ddTHH:mm:ssZ'))'")
        }
        if ($EndDate) {
            $ParsedEnd = [datetime]::ParseExact($EndDate, 'yyyyMMdd', $null).AddDays(1)
            $FilterParts.Add("DateRangeStart lt datetime'$($ParsedEnd.ToString('yyyy-MM-ddTHH:mm:ssZ'))'")
        }

        $Filter = $FilterParts -join ' and '
        $Results = @(Get-CIPPAzDataTableEntity @DmarcReportsTable -Filter $Filter)

        # Apply domain filter client-side (not indexed in table)
        if ($Domain) {
            $Results = @($Results | Where-Object { $_.PolicyDomain -eq $Domain -or $_.HeaderFrom -eq $Domain })
        }
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -API $Request.Params.CIPPEndpoint -tenant $TenantFilter -message "Failed to list DMARC reports: $($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage
        return [HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::InternalServerError
            Body       = @{ Results = "Failed: $($ErrorMessage.NormalizedError)" }
        }
    }

    return [HttpResponseContext]@{
        StatusCode = [HttpStatusCode]::OK
        Body       = @($Results)
    }
}
