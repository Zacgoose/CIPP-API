function Invoke-ExecDmarcSetup {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Exchange.Mailbox.ReadWrite
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    $Headers = $Request.Headers
    $TenantFilter = $Request.Body.tenantFilter.value ?? $Request.Body.tenantFilter ?? $Request.Query.tenantFilter
    $Action = $Request.Body.Action ?? $Request.Query.Action

    $DmarcConfigTable = Get-CIPPTable -tablename 'DmarcConfig'

    $MailboxAddress = if ([string]::IsNullOrWhiteSpace($Request.Body.MailboxAddress)) { "dmarc-reports@$TenantFilter" } else { $Request.Body.MailboxAddress }
    $PostProcessAction = $Request.Body.PostProcessAction.value ?? $Request.Body.PostProcessAction ?? 'Move'
    $DisplayName = $Request.Body.DisplayName ?? 'CIPP DMARC Reports'
    $MailboxDomain = ($MailboxAddress -split '@')[1]

    # Convert internal Step/Success/Message results to frontend-friendly resultText/state format
    function ConvertTo-ResultOutput {
        param([array]$Results)
        @($Results | ForEach-Object {
            @{
                resultText = $_.Message
                state      = if ($_.Success) { 'success' } else { 'error' }
            }
        })
    }

    switch ($Action) {
        'Provision' {
            # Create shared mailbox + RBAC in one call
            try {
                $Results = Set-CIPPDmarcMailbox -TenantFilter $TenantFilter -MailboxAddress $MailboxAddress -DisplayName $DisplayName -CreateMailbox -CreateRbac
                $Failures = @($Results | Where-Object { -not $_.Success })

                if ($Results.Count -gt 0 -and $Failures.Count -eq 0) {
                    # Discover tenant domains — try Domain Analyser cache first, fall back to Graph
                    $DomainsTable = Get-CIPPTable -tablename 'Domains'
                    $TenantDomains = @(Get-CIPPAzDataTableEntity @DomainsTable -Filter "PartitionKey eq 'TenantDomains' and TenantId eq '$TenantFilter'" -Property RowKey)

                    if ($TenantDomains.Count -eq 0) {
                        # Domain Analyser hasn't run yet — fetch directly from Graph
                        $GraphDomains = New-GraphGetRequest -uri 'https://graph.microsoft.com/v1.0/domains?$select=id,isDefault,isVerified' -tenantid $TenantFilter -AsApp $true
                        $TenantDomains = @($GraphDomains | Where-Object { $_.isVerified } | ForEach-Object {
                            [PSCustomObject]@{ RowKey = $_.id; IsDefault = $_.isDefault }
                        })
                    }

                    $DomainList = foreach ($Domain in $TenantDomains) {
                        $DomainName = $Domain.RowKey
                        $IsPrimary = $DomainName -eq $MailboxDomain
                        @{
                            Domain    = $DomainName
                            Enabled   = $IsPrimary
                            IsPrimary = $IsPrimary
                            NeedsEdv  = -not $IsPrimary
                            EdvRecord = if (-not $IsPrimary) { "$MailboxDomain._report._dmarc.$DomainName" } else { $null }
                            EdvValue  = if (-not $IsPrimary) { 'v=DMARC1' } else { $null }
                        }
                    }

                    # Save config to DmarcConfig table
                    [string]$Config = @{
                        MailboxAddress    = $MailboxAddress
                        PostProcessAction = $PostProcessAction
                        DisplayName       = $DisplayName
                        Domains           = @($DomainList)
                    } | ConvertTo-Json -Compress -Depth 10

                    Add-CIPPAzDataTableEntity @DmarcConfigTable -Entity @{
                        PartitionKey  = 'DmarcTenant'
                        RowKey        = $TenantFilter
                        Status        = 'Provisioning'
                        Config        = $Config
                        ProvisionedAt = [int64](Get-Date -UFormat %s)
                    } -Force

                    Write-LogMessage -API $APIName -tenant $TenantFilter -headers $Headers -message "DMARC provisioned for $TenantFilter" -sev Info

                    # Auto-run test access after successful provisioning
                    $TestResults = Set-CIPPDmarcMailbox -TenantFilter $TenantFilter -MailboxAddress $MailboxAddress -TestAccess
                    $TestFailures = @($TestResults | Where-Object { -not $_.Success })
                    if ($TestResults.Count -gt 0 -and $TestFailures.Count -eq 0) {
                        Add-CIPPAzDataTableEntity @DmarcConfigTable -Entity @{
                            PartitionKey = 'DmarcTenant'
                            RowKey       = $TenantFilter
                            Status       = 'Active'
                        } -OperationType 'UpsertMerge'
                    }
                    $Results = @($Results) + @($TestResults)
                }
                $Body = @{ Results = ConvertTo-ResultOutput $Results }
            } catch {
                $ErrorMessage = Get-CippException -Exception $_
                Write-LogMessage -API $APIName -tenant $TenantFilter -headers $Headers -message "DMARC provision failed: $($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage
                $Body = @{ Results = @(@{ resultText = "Provisioning failed: $($ErrorMessage.NormalizedError)"; state = 'error' }) }
            }
        }

        'TestAccess' {
            try {
                $Results = Set-CIPPDmarcMailbox -TenantFilter $TenantFilter -MailboxAddress $MailboxAddress -TestAccess
                $AllPassed = ($Results | Where-Object { -not $_.Success }).Count -eq 0

                if ($AllPassed) {
                    Add-CIPPAzDataTableEntity @DmarcConfigTable -Entity @{
                        PartitionKey = 'DmarcTenant'
                        RowKey       = $TenantFilter
                        Status       = 'Active'
                    } -OperationType 'UpsertMerge'
                }
                $Body = @{ Results = ConvertTo-ResultOutput $Results }
            } catch {
                $ErrorMessage = Get-CippException -Exception $_
                $Body = @{ Results = @(@{ resultText = "Test access failed: $($ErrorMessage.NormalizedError)"; state = 'error' }) }
            }
        }

        'ValidateDns' {
            try {
                # Load config for this tenant
                $ExistingConfig = Get-CIPPAzDataTableEntity @DmarcConfigTable -Filter "PartitionKey eq 'DmarcTenant' and RowKey eq '$TenantFilter'"
                $ParsedConfig = if ($ExistingConfig.Config) { $ExistingConfig.Config | ConvertFrom-Json -ErrorAction SilentlyContinue } else { $null }
                $ConfiguredDomains = @($ParsedConfig.Domains | Where-Object { $_ })

                # Live DNS validation via shared helper
                $DnsCheck = Test-CIPPDmarcDns -ConfiguredDomains $ConfiguredDomains -MailboxAddress $MailboxAddress

                # Save validation results to config
                [string]$DnsValidationJson = @($DnsCheck.Validation) | ConvertTo-Json -Compress -Depth 5
                Add-CIPPAzDataTableEntity @DmarcConfigTable -Entity @{
                    PartitionKey  = 'DmarcTenant'
                    RowKey        = $TenantFilter
                    DnsValidation = $DnsValidationJson
                } -OperationType 'UpsertMerge'

                $Body = @{ Results = @($DnsCheck.Results) }
            } catch {
                $ErrorMessage = Get-CippException -Exception $_
                $Body = @{ Results = @(@{ resultText = "DNS validation failed: $($ErrorMessage.NormalizedError)"; state = 'error' }) }
            }
        }

        'UpdateConfig' {
            try {
                # Merge incoming domain enable/disable changes with existing config
                $ExistingConfig = Get-CIPPAzDataTableEntity @DmarcConfigTable -Filter "PartitionKey eq 'DmarcTenant' and RowKey eq '$TenantFilter'"
                $ParsedConfig = if ($ExistingConfig.Config) { $ExistingConfig.Config | ConvertFrom-Json -ErrorAction SilentlyContinue } else { $null }
                $ExistingDomains = @($ParsedConfig.Domains)

                # Preserve existing values if not provided in the request
                $UpdateMailbox = if ([string]::IsNullOrWhiteSpace($Request.Body.MailboxAddress)) { $ParsedConfig.MailboxAddress ?? "dmarc-reports@$TenantFilter" } else { $Request.Body.MailboxAddress }
                $UpdatePostProcess = $Request.Body.PostProcessAction.value ?? $Request.Body.PostProcessAction ?? $ParsedConfig.PostProcessAction ?? 'Move'
                $UpdateDisplayName = if ([string]::IsNullOrWhiteSpace($Request.Body.DisplayName)) { $ParsedConfig.DisplayName ?? 'CIPP DMARC Reports' } else { $Request.Body.DisplayName }

                # If caller sends Domains array, merge it; otherwise keep existing
                $IncomingDomains = $Request.Body.Domains
                if ($IncomingDomains) {
                    $UpdatedDomains = foreach ($D in $ExistingDomains) {
                        $Incoming = $IncomingDomains | Where-Object { $_.Domain -eq $D.Domain }
                        if ($Incoming) {
                            @{
                                Domain    = $D.Domain
                                Enabled   = [bool]$Incoming.Enabled
                                IsPrimary = [bool]$D.IsPrimary
                                NeedsEdv  = [bool]$D.NeedsEdv
                                EdvRecord = $D.EdvRecord
                                EdvValue  = $D.EdvValue
                            }
                        } else {
                            $D
                        }
                    }
                } else {
                    $UpdatedDomains = $ExistingDomains
                }

                [string]$Config = @{
                    MailboxAddress    = $UpdateMailbox
                    PostProcessAction = $UpdatePostProcess
                    DisplayName       = $UpdateDisplayName
                    Domains           = @($UpdatedDomains)
                } | ConvertTo-Json -Compress -Depth 10

                Add-CIPPAzDataTableEntity @DmarcConfigTable -Entity @{
                    PartitionKey = 'DmarcTenant'
                    RowKey       = $TenantFilter
                    Config       = $Config
                } -OperationType 'UpsertMerge'

                Write-LogMessage -API $APIName -tenant $TenantFilter -headers $Headers -message "Updated DMARC config for $TenantFilter" -sev Info
                $Body = @{ Results = @(@{ resultText = "Updated DMARC configuration for $TenantFilter"; state = 'success' }) }
            } catch {
                $ErrorMessage = Get-CippException -Exception $_
                $Body = @{ Results = @(@{ resultText = "Config update failed: $($ErrorMessage.NormalizedError)"; state = 'error' }) }
            }
        }

        'Remove' {
            try {
                $Results = Set-CIPPDmarcMailbox -TenantFilter $TenantFilter -MailboxAddress $MailboxAddress -RemoveRbac -RemoveMailbox
                # Mark tenant as removed
                Add-CIPPAzDataTableEntity @DmarcConfigTable -Entity @{
                    PartitionKey = 'DmarcTenant'
                    RowKey       = $TenantFilter
                    Status       = 'Removed'
                    RemovedAt    = [int64](Get-Date -UFormat %s)
                } -Force
                Write-LogMessage -API $APIName -tenant $TenantFilter -headers $Headers -message "DMARC removed for $TenantFilter" -sev Info
                $Body = @{ Results = ConvertTo-ResultOutput $Results }
            } catch {
                $ErrorMessage = Get-CippException -Exception $_
                $Body = @{ Results = @(@{ resultText = "Remove failed: $($ErrorMessage.NormalizedError)"; state = 'error' }) }
            }
        }

        'ProcessTenant' {
            try {
                $ExistingConfig = Get-CIPPAzDataTableEntity @DmarcConfigTable -Filter "PartitionKey eq 'DmarcTenant' and RowKey eq '$TenantFilter'"
                if (-not $ExistingConfig -or $ExistingConfig.Status -ne 'Active') {
                    $Body = @{ Results = @(@{ resultText = "Tenant $TenantFilter is not enrolled or not active"; state = 'error' }) }
                } else {
                    $ParsedConfig = $ExistingConfig.Config | ConvertFrom-Json -ErrorAction SilentlyContinue
                    $ActivityInput = @{
                        TenantFilter      = $TenantFilter
                        MailboxAddress    = $ParsedConfig.MailboxAddress
                        PostProcessAction = $ParsedConfig.PostProcessAction
                        Config            = $ParsedConfig
                    }
                    Push-DmarcProcessTenant -Item $ActivityInput
                    Write-LogMessage -API $APIName -tenant $TenantFilter -headers $Headers -message "DMARC processing triggered for $TenantFilter" -sev Info
                    $Body = @{ Results = @(@{ resultText = "DMARC processing started for $TenantFilter"; state = 'success' }) }
                }
            } catch {
                $ErrorMessage = Get-CippException -Exception $_
                $Body = @{ Results = @(@{ resultText = "Process failed: $($ErrorMessage.NormalizedError)"; state = 'error' }) }
            }
        }

        default {
            return [HttpResponseContext]@{
                StatusCode = [HttpStatusCode]::BadRequest
                Body       = @{ Results = "Unknown action: $Action. Valid actions: Provision, TestAccess, ValidateDns, UpdateConfig, ProcessTenant, Remove" }
            }
        }
    }

    return [HttpResponseContext]@{
        StatusCode = [HttpStatusCode]::OK
        Body       = $Body
    }
}
