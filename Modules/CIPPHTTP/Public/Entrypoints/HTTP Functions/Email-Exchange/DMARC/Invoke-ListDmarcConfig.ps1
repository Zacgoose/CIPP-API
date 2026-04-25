function Invoke-ListDmarcConfig {
    <#
    .FUNCTIONALITY
        Entrypoint,AnyTenant
    .ROLE
        Exchange.Mailbox.Read
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $TenantFilter = $Request.Query.tenantFilter

    $DmarcConfigTable = Get-CIPPTable -tablename 'DmarcConfig'

    try {
        if ($TenantFilter -and $TenantFilter -ne 'AllTenants') {
            $Filter = "PartitionKey eq 'DmarcTenant' and RowKey eq '$TenantFilter'"
        } else {
            $Filter = "PartitionKey eq 'DmarcTenant'"
        }

        $Configs = @(Get-CIPPAzDataTableEntity @DmarcConfigTable -Filter $Filter)

        $Results = foreach ($Config in $Configs) {
            $ParsedConfig = if ($Config.Config) { $Config.Config | ConvertFrom-Json -ErrorAction SilentlyContinue } else { $null }
            $DnsValidation = if ($Config.DnsValidation) { $Config.DnsValidation | ConvertFrom-Json -ErrorAction SilentlyContinue } else { $null }
            $Domains = if ($ParsedConfig.Domains) { @($ParsedConfig.Domains | Where-Object { $_ }) } else { @() }

            [PSCustomObject]@{
                TenantFilter      = $Config.RowKey
                Status            = $Config.Status ?? 'Unknown'
                MailboxAddress    = $ParsedConfig.MailboxAddress ?? "dmarc-reports@$($Config.RowKey)"
                PostProcessAction = $ParsedConfig.PostProcessAction ?? 'Move'
                DisplayName       = $ParsedConfig.DisplayName ?? 'CIPP DMARC Reports'
                Domains           = $Domains
                DomainCount       = $Domains.Count
                ProvisionedAt     = $Config.ProvisionedAt ?? $null
                LastRunTime       = $Config.LastRunTime ?? $null
                LastRunRecords    = $Config.LastRunRecords ?? $null
                LastRunErrors     = $Config.LastRunErrors ?? $null
                DnsValidation     = $DnsValidation
            }
        }
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -API $Request.Params.CIPPEndpoint -message "Failed to list DMARC config: $($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage
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
