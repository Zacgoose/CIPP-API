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
        # Parse InputValue to get ScriptGuid and optional parameters
        $ScriptGuid = $null
        $Parameters = @{}

        if ($InputValue -is [hashtable]) {
            # Handle autoComplete object structure (has value, label, etc.)
            if ($InputValue.ScriptGuid -is [hashtable] -and $InputValue.ScriptGuid.value) {
                $ScriptGuid = $InputValue.ScriptGuid.value
            } elseif ($InputValue.ScriptGuid -is [pscustomobject] -and $InputValue.ScriptGuid.value) {
                $ScriptGuid = $InputValue.ScriptGuid.value
            } else {
                $ScriptGuid = $InputValue.ScriptGuid
            }

            # Extract any additional parameters (skip ScriptGuid and Parameters)
            foreach ($key in $InputValue.Keys) {
                if ($key -ne 'ScriptGuid' -and $key -ne 'Parameters') {
                    $Parameters[$key] = $InputValue[$key]
                }
            }

            # Handle Parameters field specifically (could be JSON string or empty)
            if ($InputValue.Parameters -and -not [string]::IsNullOrWhiteSpace($InputValue.Parameters)) {
                try {
                    $ParsedParams = $InputValue.Parameters | ConvertFrom-Json -ErrorAction Stop
                    if ($ParsedParams) {
                        foreach ($prop in $ParsedParams.PSObject.Properties) {
                            $Parameters[$prop.Name] = $prop.Value
                        }
                    }
                } catch {
                    Write-LogMessage -message "Failed to parse Parameters JSON: $($_.Exception.Message)" -API 'CustomScriptAlert' -tenant $TenantFilter -sev Warning
                }
            }
        } elseif ($InputValue -is [pscustomobject]) {
            # Handle autoComplete object structure (has value, label, etc.)
            if ($InputValue.ScriptGuid -is [pscustomobject] -and $InputValue.ScriptGuid.value) {
                $ScriptGuid = $InputValue.ScriptGuid.value
            } else {
                $ScriptGuid = $InputValue.ScriptGuid
            }

            # Extract any additional parameters from PSCustomObject
            $Properties = $InputValue.PSObject.Properties | Where-Object { $_.Name -notin @('ScriptGuid', 'Parameters') }
            foreach ($prop in $Properties) {
                $Parameters[$prop.Name] = $prop.Value
            }

            # Handle Parameters field specifically
            if ($InputValue.Parameters -and -not [string]::IsNullOrWhiteSpace($InputValue.Parameters)) {
                try {
                    $ParsedParams = $InputValue.Parameters | ConvertFrom-Json -ErrorAction Stop
                    if ($ParsedParams) {
                        foreach ($prop in $ParsedParams.PSObject.Properties) {
                            $Parameters[$prop.Name] = $prop.Value
                        }
                    }
                } catch {
                    Write-LogMessage -message "Failed to parse Parameters JSON: $($_.Exception.Message)" -API 'CustomScriptAlert' -tenant $TenantFilter -sev Warning
                }
            }
        } elseif ($InputValue -is [string]) {
            # Simple string input is treated as ScriptGuid
            $ScriptGuid = $InputValue
        }

        if ([string]::IsNullOrWhiteSpace($ScriptGuid)) {
            Write-LogMessage -message 'ScriptGuid is required in InputValue for custom script alerts' -API 'CustomScriptAlert' -tenant $TenantFilter -sev Error
            return
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
