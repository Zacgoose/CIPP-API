function Read-CIPPDmarcReport {
    <#
    .SYNOPSIS
        Read and parse DMARC aggregate reports from a per-tenant shared mailbox
    .DESCRIPTION
        Uses Graph API to read messages from the DMARC shared mailbox, downloads
        attachments, decompresses gzip/zip, parses the RFC 7489 XML, and returns
        structured DMARC report records. Optionally moves processed messages to a
        subfolder or deletes them.
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$TenantFilter,

        [Parameter(Mandatory = $false)]
        [string]$MailboxAddress,

        [Parameter(Mandatory = $false)]
        [ValidateSet('Move', 'Delete')]
        [string]$PostProcessAction = 'Move',

        [Parameter(Mandatory = $false)]
        [string]$ProcessedFolderName = 'DMARC Processed'
    )

    # Resolve mailbox address
    if ([string]::IsNullOrWhiteSpace($MailboxAddress)) {
        $MailboxAddress = "dmarc-reports@$TenantFilter"
    }

    $ParsedRecords = [System.Collections.Generic.List[object]]::new()
    $Errors = [System.Collections.Generic.List[object]]::new()

    # Get all messages from the inbox with attachments expanded
    try {
        $Messages = @(New-GraphGetRequest -uri "https://graph.microsoft.com/v1.0/users/$MailboxAddress/mailFolders/inbox/messages?`$expand=attachments&`$top=999&`$select=id,subject,receivedDateTime,from" -tenantid $TenantFilter -AsApp $true)
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -API 'DmarcProcessor' -tenant $TenantFilter -message "Failed to read inbox for $MailboxAddress : $($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage
        return [PSCustomObject]@{
            Records = @()
            Errors  = @([PSCustomObject]@{
                    Step    = 'ReadInbox'
                    Message = $ErrorMessage.NormalizedError
                    Data    = $ErrorMessage
                })
        }
    }

    if ($Messages.Count -eq 0) {
        return [PSCustomObject]@{
            Records = @()
            Errors  = @()
        }
    }

    # Resolve or create the processed folder for move operations
    $ProcessedFolderId = $null
    if ($PostProcessAction -eq 'Move') {
        try {
            $Folders = @(New-GraphGetRequest -uri "https://graph.microsoft.com/v1.0/users/$MailboxAddress/mailFolders?`$filter=displayName eq '$ProcessedFolderName'" -tenantid $TenantFilter -AsApp $true)
            if ($Folders.Count -gt 0) {
                $ProcessedFolderId = $Folders[0].id
            } else {
                $NewFolder = New-GraphPostRequest -uri "https://graph.microsoft.com/v1.0/users/$MailboxAddress/mailFolders" -tenantid $TenantFilter -AsApp $true -Body @{
                    displayName = $ProcessedFolderName
                } -Type POST
                $ProcessedFolderId = $NewFolder.id
            }
        } catch {
            $ErrorMessage = Get-CippException -Exception $_
            $Errors.Add([PSCustomObject]@{
                    Step    = 'CreateProcessedFolder'
                    Message = "Failed to create '$ProcessedFolderName' folder: $($ErrorMessage.NormalizedError)"
                    Data    = $ErrorMessage
                })
            Write-LogMessage -API 'DmarcProcessor' -tenant $TenantFilter -message "Failed to create processed folder: $($ErrorMessage.NormalizedError)" -sev Warning -LogData $ErrorMessage
        }
    }

    foreach ($Message in $Messages) {
        $Attachments = @($Message.attachments | Where-Object { $_.contentBytes -and $_.name -match '\.(xml|xml\.gz|gz|zip)$' })

        if ($Attachments.Count -eq 0) {
            # No DMARC attachments — skip but don't error
            continue
        }

        foreach ($Attachment in $Attachments) {
            try {
                $XmlContent = ConvertFrom-DmarcAttachment -AttachmentName $Attachment.name -ContentBytes $Attachment.contentBytes
                $Records = ConvertFrom-DmarcXml -XmlContent $XmlContent -TenantFilter $TenantFilter -SourceMessageId $Message.id
                foreach ($Record in $Records) {
                    $ParsedRecords.Add($Record)
                }
            } catch {
                $ErrorMessage = Get-CippException -Exception $_
                $Errors.Add([PSCustomObject]@{
                        Step      = 'ParseAttachment'
                        MessageId = $Message.id
                        FileName  = $Attachment.name
                        Message   = "Failed to parse attachment: $($ErrorMessage.NormalizedError)"
                        Data      = $ErrorMessage
                    })
            }
        }

        # Post-process the message (move or delete)
        try {
            switch ($PostProcessAction) {
                'Move' {
                    if ($ProcessedFolderId) {
                        $null = New-GraphPostRequest -uri "https://graph.microsoft.com/v1.0/users/$MailboxAddress/messages/$($Message.id)/move" -tenantid $TenantFilter -AsApp $true -Body @{
                            destinationId = $ProcessedFolderId
                        } -Type POST
                    }
                }
                'Delete' {
                    $null = New-GraphPostRequest -uri "https://graph.microsoft.com/v1.0/users/$MailboxAddress/messages/$($Message.id)" -tenantid $TenantFilter -AsApp $true -Type DELETE
                }
            }
        } catch {
            $ErrorMessage = Get-CippException -Exception $_
            $Errors.Add([PSCustomObject]@{
                    Step      = 'PostProcess'
                    MessageId = $Message.id
                    Message   = "Failed to $($PostProcessAction.ToLower()) message: $($ErrorMessage.NormalizedError)"
                    Data      = $ErrorMessage
                })
        }
    }

    return [PSCustomObject]@{
        Records = @($ParsedRecords)
        Errors  = @($Errors)
    }
}

function ConvertFrom-DmarcAttachment {
    <#
    .SYNOPSIS
        Decompress a DMARC report attachment and return the XML content
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$AttachmentName,

        [Parameter(Mandatory = $true)]
        [string]$ContentBytes
    )

    $Bytes = [System.Convert]::FromBase64String($ContentBytes)

    if ($AttachmentName -match '\.gz$') {
        # Gzip compressed
        $MemoryStream = [System.IO.MemoryStream]::new($Bytes)
        try {
            $GzipStream = [System.IO.Compression.GZipStream]::new($MemoryStream, [System.IO.Compression.CompressionMode]::Decompress)
            $Reader = [System.IO.StreamReader]::new($GzipStream)
            return $Reader.ReadToEnd()
        } finally {
            if ($Reader) { $Reader.Dispose() }
            if ($GzipStream) { $GzipStream.Dispose() }
            $MemoryStream.Dispose()
        }
    } elseif ($AttachmentName -match '\.zip$') {
        # Zip archive — extract the first XML file
        $MemoryStream = [System.IO.MemoryStream]::new($Bytes)
        try {
            $ZipArchive = [System.IO.Compression.ZipArchive]::new($MemoryStream, [System.IO.Compression.ZipArchiveMode]::Read)
            $XmlEntry = $ZipArchive.Entries | Where-Object { $_.Name -match '\.xml$' } | Select-Object -First 1
            if (-not $XmlEntry) {
                throw "No XML file found in zip attachment '$AttachmentName'"
            }
            $EntryStream = $XmlEntry.Open()
            $Reader = [System.IO.StreamReader]::new($EntryStream)
            return $Reader.ReadToEnd()
        } finally {
            if ($Reader) { $Reader.Dispose() }
            if ($EntryStream) { $EntryStream.Dispose() }
            if ($ZipArchive) { $ZipArchive.Dispose() }
            $MemoryStream.Dispose()
        }
    } elseif ($AttachmentName -match '\.xml$') {
        # Plain XML
        return [System.Text.Encoding]::UTF8.GetString($Bytes)
    } else {
        throw "Unsupported attachment format: '$AttachmentName'"
    }
}

function ConvertFrom-DmarcXml {
    <#
    .SYNOPSIS
        Parse RFC 7489 DMARC aggregate report XML into structured records
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$XmlContent,

        [Parameter(Mandatory = $true)]
        [string]$TenantFilter,

        [Parameter(Mandatory = $false)]
        [string]$SourceMessageId
    )

    $Xml = [xml]$XmlContent
    $Feedback = $Xml.feedback

    if (-not $Feedback) {
        throw 'Invalid DMARC report: missing <feedback> root element'
    }

    # Extract report metadata
    $ReportMetadata = $Feedback.report_metadata
    $PolicyPublished = $Feedback.policy_published

    $ReportId = $ReportMetadata.report_id ?? (New-Guid).ToString()
    $ReportingOrg = $ReportMetadata.org_name
    $DateRangeStart = $null
    $DateRangeEnd = $null

    if ($ReportMetadata.date_range) {
        $DateRangeStart = [DateTimeOffset]::FromUnixTimeSeconds([long]$ReportMetadata.date_range.begin).UtcDateTime
        $DateRangeEnd = [DateTimeOffset]::FromUnixTimeSeconds([long]$ReportMetadata.date_range.end).UtcDateTime
    }

    $PolicyDomain = $PolicyPublished.domain
    $PolicyP = $PolicyPublished.p
    $PolicySP = $PolicyPublished.sp
    $PolicyPct = $PolicyPublished.pct

    # Parse each record row
    $Records = foreach ($Record in @($Feedback.record)) {
        $Row = $Record.row
        $AuthResults = $Record.auth_results
        $Identifiers = $Record.identifiers

        [PSCustomObject]@{
            PartitionKey     = $TenantFilter
            RowKey           = "$ReportId-$($Row.source_ip)-$($Identifiers.header_from ?? $PolicyDomain)"
            ReportId         = $ReportId
            ReportingOrg     = $ReportingOrg
            DateRangeStart   = $DateRangeStart
            DateRangeEnd     = $DateRangeEnd
            SourceIP         = $Row.source_ip
            MessageCount     = [int]($Row.count ?? 1)
            Disposition      = $Row.policy_evaluated.disposition
            DMARCResult      = if ($Row.policy_evaluated.dkim -eq 'pass' -or $Row.policy_evaluated.spf -eq 'pass') { 'pass' } else { 'fail' }
            DKIMResult       = $Row.policy_evaluated.dkim
            SPFResult        = $Row.policy_evaluated.spf
            DKIMAuthResult   = [string](($AuthResults.dkim.result | Select-Object -First 1) ?? 'none')
            SPFAuthResult    = [string](($AuthResults.spf.result | Select-Object -First 1) ?? 'none')
            DKIMDomain       = [string]($AuthResults.dkim.domain | Select-Object -First 1)
            SPFDomain        = [string]($AuthResults.spf.domain | Select-Object -First 1)
            HeaderFrom       = $Identifiers.header_from
            EnvelopeFrom     = $Identifiers.envelope_from
            PolicyDomain     = $PolicyDomain
            PolicyPublished  = $PolicyP
            PolicySP         = $PolicySP
            PolicyPct        = $PolicyPct
            TenantId         = $TenantFilter
            ProcessedAt      = [int64](Get-Date -UFormat %s)
            SourceMessageId  = $SourceMessageId
        }
    }

    return @($Records)
}
