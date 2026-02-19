function Get-CIPPAlertCustomScript {
    <#
    .FUNCTIONALITY
        Entrypoint
    .DESCRIPTION
        Executes a custom PowerShell script as an alert and returns the results
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $false)]
        [Alias('input')]
        $InputValue,
        $TenantFilter
    )

    try {
        $ScriptGuid = $InputValue.ScriptGuid.value
        $Parameters = @{}

        if (-not [string]::IsNullOrWhiteSpace($InputValue.Parameters)) {
            $ParsedParams = $InputValue.Parameters | ConvertFrom-Json -ErrorAction Stop
            if ($ParsedParams) {
                foreach ($prop in $ParsedParams.PSObject.Properties) {
                    $Parameters[$prop.Name] = $prop.Value
                }
            }
        }

        Write-LogMessage -message "Custom script alert - ScriptGuid: $ScriptGuid, Parameters: $($Parameters | ConvertTo-Json -Compress)" -API 'CustomScriptAlert' -tenant $TenantFilter -sev Debug

        # Execute script (lookup happens inside New-CippCustomScriptExecution)
        $Result = New-CippCustomScriptExecution -ScriptGuid $ScriptGuid -TenantFilter $TenantFilter -Parameters $Parameters

        # Format alert data and only trigger alert trace on meaningful results
        $AlertData = @($Result) | Where-Object { $null -ne $_ }

        $AlertData = foreach ($item in $AlertData) {
            # Explicit false means no alert
            if ($item -is [bool] -and -not $item) {
                continue
            }

            # Normalize hashtables to objects for consistent property handling
            $NormalizedItem = if ($item -is [hashtable]) { [PSCustomObject]$item } else { $item }

            if ($NormalizedItem -is [pscustomobject]) {
                # Add standard metadata if not present
                if (-not $NormalizedItem.PSObject.Properties['Tenant']) {
                    $NormalizedItem | Add-Member -NotePropertyName 'Tenant' -NotePropertyValue $TenantFilter -Force
                }
                if (-not $NormalizedItem.PSObject.Properties['ScriptGuid']) {
                    $NormalizedItem | Add-Member -NotePropertyName 'ScriptGuid' -NotePropertyValue $ScriptGuid -Force
                }
                if (-not $NormalizedItem.PSObject.Properties['Message']) {
                    $NormalizedItem | Add-Member -NotePropertyName 'Message' -NotePropertyValue 'Custom script alert condition met' -Force
                }

                $NormalizedItem
                continue
            }

            # Empty string means no alert payload
            if ($NormalizedItem -is [string] -and [string]::IsNullOrWhiteSpace($NormalizedItem)) {
                continue
            }

            # Non-object output (true/string/number/etc.) is converted to a standard alert row
            [PSCustomObject]@{
                Message    = [string]$NormalizedItem
                Result     = $NormalizedItem
                ScriptGuid = $ScriptGuid
                Tenant     = $TenantFilter
            }
        }

        $AlertData = @($AlertData) | Where-Object { $null -ne $_ }

        if ($AlertData.Count -gt 0) {
            Write-AlertTrace -cmdletName $MyInvocation.MyCommand -tenantFilter $TenantFilter -data $AlertData
        }

    } catch {
        Write-AlertMessage -tenant $($TenantFilter) -message "Failed to execute custom script alert: $($TenantFilter): $(Get-NormalizedError -message $_.Exception.message)"
    }
}
