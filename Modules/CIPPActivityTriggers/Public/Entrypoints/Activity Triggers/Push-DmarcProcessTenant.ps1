function Push-DmarcProcessTenant {
    <#
    .SYNOPSIS
        Process DMARC reports for a single tenant
    .DESCRIPTION
        Activity trigger that tests mailbox access, reads and parses DMARC
        aggregate reports, writes parsed records to DmarcReports table,
        logs errors to DmarcErrors table, and validates DNS via Domain Analyser data.
    .FUNCTIONALITY
        Entrypoint
    #>
    [CmdletBinding()]
    param($Item)

    $TenantFilter = $Item.TenantFilter
    $MailboxAddress = $Item.MailboxAddress
    $PostProcessAction = $Item.PostProcessAction ?? 'Move'

    $DmarcReportsTable = Get-CIPPTable -tablename 'DmarcReports'
    $DmarcErrorsTable = Get-CIPPTable -tablename 'DmarcErrors'
    $DmarcConfigTable = Get-CIPPTable -tablename 'DmarcConfig'

    # Step 1: Verify mailbox is accessible
    try {
        $null = New-ExoRequest -tenantid $TenantFilter -cmdlet 'Get-Mailbox' -cmdParams @{ Identity = $MailboxAddress } -useSystemMailbox $true
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -API 'DmarcProcessor' -tenant $TenantFilter -message "DMARC mailbox $MailboxAddress not accessible: $($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage
        Add-CIPPAzDataTableEntity @DmarcErrorsTable -Entity @{
            PartitionKey = $TenantFilter
            RowKey       = "mailbox-$(Get-Date -Format 'yyyyMMddHHmmss')"
            Error        = "Mailbox not accessible: $($ErrorMessage.NormalizedError)"
            Timestamp    = [int64](Get-Date -UFormat %s)
        } -Force
        return "Failed: mailbox not accessible for $TenantFilter"
    }

    # Step 2: Read and parse DMARC reports
    $ReportResult = Read-CIPPDmarcReport -TenantFilter $TenantFilter -MailboxAddress $MailboxAddress -PostProcessAction $PostProcessAction

    # Step 3: Write parsed records to DmarcReports table
    $RecordCount = 0
    if ($ReportResult.Records.Count -gt 0) {
        foreach ($Record in $ReportResult.Records) {
            try {
                Add-CIPPAzDataTableEntity @DmarcReportsTable -Entity $Record -Force
                $RecordCount++
            } catch {
                $ErrorMessage = Get-CippException -Exception $_
                Write-LogMessage -API 'DmarcProcessor' -tenant $TenantFilter -message "Failed to write DMARC record: $($ErrorMessage.NormalizedError)" -sev Warning -LogData $ErrorMessage
            }
        }
    }

    # Step 4: Write any processing errors to DmarcErrors table
    foreach ($Error in $ReportResult.Errors) {
        try {
            Add-CIPPAzDataTableEntity @DmarcErrorsTable -Entity @{
                PartitionKey = $TenantFilter
                RowKey       = "parse-$(Get-Date -Format 'yyyyMMddHHmmss')-$([guid]::NewGuid().ToString('N').Substring(0,8))"
                Step         = $Error.Step
                Error        = $Error.Message
                FileName     = $Error.FileName ?? ''
                MessageId    = $Error.MessageId ?? ''
                Timestamp    = [int64](Get-Date -UFormat %s)
            } -Force
        } catch {}
    }

    # Step 5: Read Domain Analyser data for DNS validation — only for enabled domains
    try {
        # Load enabled domains from DmarcConfig
        $TenantConfig = Get-CIPPAzDataTableEntity @DmarcConfigTable -Filter "PartitionKey eq 'DmarcTenant' and RowKey eq '$TenantFilter'"
        $ParsedConfig = if ($TenantConfig.Config) { $TenantConfig.Config | ConvertFrom-Json -ErrorAction SilentlyContinue } else { $null }
        $ConfiguredDomains = @($ParsedConfig.Domains | Where-Object { $_ })

        # Live DNS validation via shared helper (DNSHealth is loaded for activity triggers)
        $DnsCheck = Test-CIPPDmarcDns -ConfiguredDomains $ConfiguredDomains -MailboxAddress $MailboxAddress

        # Update DmarcConfig with last run info
        Add-CIPPAzDataTableEntity @DmarcConfigTable -Entity @{
            PartitionKey   = 'DmarcTenant'
            RowKey         = $TenantFilter
            Status         = 'Active'
            LastRunTime    = [int64](Get-Date -UFormat %s)
            LastRunRecords = $RecordCount
            LastRunErrors  = $ReportResult.Errors.Count
            DnsValidation  = [string](@($DnsCheck.Validation) | ConvertTo-Json -Compress -Depth 5)
        } -OperationType 'UpsertMerge'
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -API 'DmarcProcessor' -tenant $TenantFilter -message "DNS validation check failed: $($ErrorMessage.NormalizedError)" -sev Warning -LogData $ErrorMessage
    }

    $Message = "DMARC: $TenantFilter - $RecordCount records processed, $($ReportResult.Errors.Count) errors"
    Write-LogMessage -API 'DmarcProcessor' -tenant $TenantFilter -message $Message -sev Info
    return $Message
}
