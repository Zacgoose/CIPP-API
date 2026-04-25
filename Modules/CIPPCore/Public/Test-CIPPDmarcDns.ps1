function Test-CIPPDmarcDns {
    <#
    .SYNOPSIS
        Validate DMARC DNS configuration for a tenant's configured domains using live DNS lookups
    .DESCRIPTION
        Uses the DNSHealth module (Read-DmarcPolicy, Resolve-DnsHttpsQuery) to perform live
        DNS validation against the tenant's configured domains. Returns an array of result
        objects with resultText/state for frontend display and a structured validation array
        for storage.
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [array]$ConfiguredDomains,

        [Parameter(Mandatory = $true)]
        [string]$MailboxAddress
    )

    $MailboxDomain = ($MailboxAddress -split '@')[1]

    # Ensure DNSHealth is available
    $DnsModuleLoaded = $false
    if (-not (Get-Command 'Read-DmarcPolicy' -ErrorAction SilentlyContinue)) {
        Import-Module DNSHealth -ErrorAction Stop
        $DnsModuleLoaded = $true
    }

    try {
        $Results = [System.Collections.Generic.List[object]]::new()
        $Validation = [System.Collections.Generic.List[object]]::new()

        if ($ConfiguredDomains.Count -eq 0) {
            $Results.Add(@{ resultText = 'No domains configured. Re-provision this tenant to discover domains.'; state = 'error' })
            return [PSCustomObject]@{ Results = @($Results); Validation = @($Validation) }
        }

        foreach ($DomainConfig in $ConfiguredDomains) {
            $DomainName = $DomainConfig.Domain
            $IsEnabled = [bool]$DomainConfig.Enabled
            $NeedsEdv = [bool]$DomainConfig.NeedsEdv

            # Skip disabled domains
            if (-not $IsEnabled) {
                $Results.Add(@{ resultText = "$DomainName — DMARC reporting disabled for this domain"; state = 'info' })
                $Validation.Add([PSCustomObject]@{
                    Domain      = $DomainName
                    Enabled     = $false
                    Status      = 'Disabled'
                    DmarcRecord = $null
                    DmarcPolicy = $null
                    RuaMatch    = $false
                    EdvOk       = $true
                    Issues      = @()
                })
                continue
            }

            # Live DNS lookup
            $DmarcLookup = Read-DmarcPolicy -Domain $DomainName -ErrorAction SilentlyContinue
            $CurrentRecord = $DmarcLookup.Record
            $CurrentPolicy = $DmarcLookup.Policy ?? 'none'
            $ReportingEmails = @($DmarcLookup.ReportingEmails | Where-Object { $_ })

            # Build the required DMARC record
            $RequiredRua = "rua=mailto:$MailboxAddress"
            $RecommendedRecord = "v=DMARC1; p=reject; $RequiredRua"

            # Validate RUA tag — ReportingEmails may contain mailto: URIs or bare addresses
            $RuaMatch = ($ReportingEmails -contains "mailto:$MailboxAddress") -or ($ReportingEmails -contains $MailboxAddress)

            # Check EDV record for non-primary domains
            $EdvOk = $true
            if ($NeedsEdv) {
                $EdvHost = "$MailboxDomain._report._dmarc.$DomainName"
                $EdvLookup = Resolve-DnsHttpsQuery -Domain $EdvHost -RecordType TXT -ErrorAction SilentlyContinue
                $EdvRecords = @($EdvLookup.Answer.data | Where-Object { $_ -match 'v=DMARC1' })
                $EdvOk = $EdvRecords.Count -gt 0
            }

            # Collect issues
            $Issues = [System.Collections.Generic.List[string]]::new()
            if (-not $CurrentRecord) {
                $Issues.Add('No DMARC record found')
            } else {
                if (-not $RuaMatch) { $Issues.Add("RUA tag missing or does not include $MailboxAddress") }
                if ($CurrentPolicy -eq 'none') { $Issues.Add("Policy is 'none' (monitoring only, no enforcement)") }
            }
            if ($NeedsEdv -and -not $EdvOk) {
                $Issues.Add('External domain verification (EDV) TXT record not found')
            }

            $AllOk = $Issues.Count -eq 0
            $Status = if ($AllOk) { 'OK' } else { 'Issues' }

            # Build result cards for frontend
            $HeaderState = if ($AllOk) { 'success' } else { 'error' }
            $HeaderLabel = if ($AllOk) { 'OK' } else { "$($Issues.Count) issue(s) found" }
            $Results.Add(@{ resultText = "$DomainName — $HeaderLabel"; state = $HeaderState })

            if ($CurrentRecord) {
                $Results.Add(@{ resultText = "Current DMARC record: $CurrentRecord"; state = if ($AllOk) { 'success' } else { 'info' } })
            } else {
                $Results.Add(@{ resultText = "No DMARC TXT record found for _dmarc.$DomainName"; state = 'error' })
            }
            if (-not $AllOk) {
                $Results.Add(@{ resultText = "Required DMARC record: $RecommendedRecord"; state = 'info' })
            }

            foreach ($Issue in $Issues) {
                $Results.Add(@{ resultText = $Issue; state = 'error' })
            }

            if ($NeedsEdv -and -not $EdvOk) {
                $EdvHost = "$MailboxDomain._report._dmarc.$DomainName"
                $Results.Add(@{ resultText = "Create TXT record: $EdvHost = 'v=DMARC1'"; state = 'error' })
            }

            # Build structured validation for storage
            $Validation.Add([PSCustomObject]@{
                Domain      = $DomainName
                Enabled     = $true
                Status      = $Status
                DmarcRecord = $CurrentRecord
                DmarcPolicy = $CurrentPolicy
                RuaMatch    = $RuaMatch
                EdvOk       = $EdvOk
                Issues      = @($Issues)
            })
        }

        return [PSCustomObject]@{ Results = @($Results); Validation = @($Validation) }
    } finally {
        if ($DnsModuleLoaded) {
            Remove-Module DNSHealth -ErrorAction SilentlyContinue
        }
    }
}
