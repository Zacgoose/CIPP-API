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

        # Execute script (lookup happens inside Exec-CippCustomScript)
        $Result = Exec-CippCustomScript -ScriptGuid $ScriptGuid -TenantFilter $TenantFilter -Parameters $Parameters

        # Format alert data - script should return array of objects or single object
        if ($null -ne $Result) {
            # Ensure result is an array
            $AlertData = @($Result)

            # Add metadata to each result item if it's an object
            $AlertData = foreach ($item in $AlertData) {
                if ($item -is [hashtable] -or $item -is [pscustomobject]) {
                    # Add tenant info if not present
                    if (-not $item.Tenant) {
                        $item | Add-Member -NotePropertyName 'Tenant' -NotePropertyValue $TenantFilter -Force
                    }
                    if (-not $item.ScriptGuid) {
                        $item | Add-Member -NotePropertyName 'ScriptGuid' -NotePropertyValue $ScriptGuid -Force
                    }
                    $item
                } else {
                    [PSCustomObject]@{
                        Result     = $item
                        ScriptGuid = $ScriptGuid
                        Tenant     = $TenantFilter
                    }
                }
            }

            # Write to alert trace only if there are results
            if ($AlertData.Count -gt 0) {
                Write-AlertTrace -cmdletName $MyInvocation.MyCommand -tenantFilter $TenantFilter -data $AlertData
            }
        }

    } catch {
        Write-AlertMessage -tenant $($TenantFilter) -message "Failed to execute custom script alert: $($TenantFilter): $(Get-NormalizedError -message $_.Exception.message)"
    }
}
