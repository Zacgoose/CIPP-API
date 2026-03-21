function Set-CIPPDBCacheDomains {
    <#
    .SYNOPSIS
        Caches domains for a tenant

    .PARAMETER TenantFilter
        The tenant to cache domains for

    .PARAMETER QueueId
        The queue ID to update with total tasks (optional)
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$TenantFilter,
        [string]$QueueId
    )

    try {
        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message 'Caching domains' -sev Debug
        $Domains = New-GraphGetRequest -uri 'https://graph.microsoft.com/beta/domains' -tenantid $TenantFilter

        # Normalize cache partition key to defaultDomainName so readers can query consistently.
        $CacheTenantFilter = $TenantFilter
        try {
            $Tenant = Get-Tenants -TenantFilter $TenantFilter -IncludeAll
            if ($Tenant -and $Tenant.defaultDomainName) {
                $CacheTenantFilter = $Tenant.defaultDomainName
            }
        } catch {
            # Fallback to provided tenant filter if tenant lookup fails
            $CacheTenantFilter = $TenantFilter
        }

        Add-CIPPDbItem -TenantFilter $CacheTenantFilter -Type 'Domains' -Data @($Domains)
        $Domains = $null

        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message 'Cached domains successfully' -sev Debug

    } catch {
        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "Failed to cache domains: $($_.Exception.Message)" -sev Error
    }
}
