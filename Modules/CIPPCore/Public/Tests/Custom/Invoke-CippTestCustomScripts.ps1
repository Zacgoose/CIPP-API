function Invoke-CippTestCustomScripts {
    <#
    .SYNOPSIS
    Run enabled custom scripts as CIPP tests
    #>
    param($Tenant)

    function Resolve-CippTemplatePath {
        param(
            $RootValue,
            [string]$Path
        )

        if ([string]::IsNullOrWhiteSpace($Path) -or -not $Path.StartsWith('Result')) {
            return $null
        }

        if ($Path -eq 'Result') {
            return $RootValue
        }

        $Remainder = $Path.Substring(6)
        $Segments = New-Object System.Collections.Generic.List[object]
        $Cursor = 0

        while ($Cursor -lt $Remainder.Length) {
            if ($Remainder[$Cursor] -eq '.') {
                $NameMatch = [regex]::Match($Remainder.Substring($Cursor), '^\.([A-Za-z_][A-Za-z0-9_]*)')
                if (-not $NameMatch.Success) {
                    return $null
                }
                [void]$Segments.Add($NameMatch.Groups[1].Value)
                $Cursor += $NameMatch.Length
                continue
            }

            if ($Remainder[$Cursor] -eq '[') {
                $IndexMatch = [regex]::Match($Remainder.Substring($Cursor), '^\[(\d+|\*)\]')
                if (-not $IndexMatch.Success) {
                    return $null
                }

                $IndexValue = $IndexMatch.Groups[1].Value
                if ($IndexValue -eq '*') {
                    [void]$Segments.Add('*')
                } else {
                    [void]$Segments.Add([int]$IndexValue)
                }

                $Cursor += $IndexMatch.Length
                continue
            }

            return $null
        }

        $CurrentValues = @($RootValue)
        foreach ($Segment in $Segments) {
            $NextValues = @()

            foreach ($Current in $CurrentValues) {
                if ($Segment -eq '*') {
                    if ($null -ne $Current -and $Current -is [System.Collections.IEnumerable] -and $Current -isnot [string]) {
                        $NextValues += @($Current)
                    }
                    continue
                }

                if ($Segment -is [int]) {
                    if ($Current -is [System.Array] -and $Segment -ge 0 -and $Segment -lt $Current.Length) {
                        $NextValues += $Current[$Segment]
                    }
                    continue
                }

                if ($Current -is [System.Collections.IDictionary]) {
                    if ($Current.Contains($Segment)) {
                        $NextValues += $Current[$Segment]
                    }
                } elseif ($null -ne $Current) {
                    $Property = $Current.PSObject.Properties[$Segment]
                    if ($null -ne $Property) {
                        $NextValues += $Property.Value
                    }
                }
            }

            $CurrentValues = @($NextValues)
        }

        if ($CurrentValues.Count -eq 0) {
            return $null
        }

        if ($CurrentValues.Count -eq 1) {
            return $CurrentValues[0]
        }

        return @($CurrentValues)
    }

    function Convert-CippTemplateValueToString {
        param($Value)

        if ($null -eq $Value) {
            return ''
        }

        if ($Value -is [string]) {
            return $Value
        }

        if ($Value -is [bool] -or $Value -is [int] -or $Value -is [long] -or $Value -is [decimal] -or $Value -is [double]) {
            return $Value.ToString()
        }

        return ($Value | ConvertTo-Json -Depth 10 -Compress)
    }

    function Resolve-CippTemplateToken {
        param(
            $RootValue,
            [string]$TokenExpression
        )

        $Expression = $TokenExpression.Trim()

        if ($Expression -eq 'ResultJson') {
            $PrettyJson = $RootValue | ConvertTo-Json -Depth 10
            return "~~~json`n$PrettyJson`n~~~"
        }

        if ($Expression -eq 'Result') {
            return ($RootValue | ConvertTo-Json -Depth 10 -Compress)
        }

        $FallbackMatch = [regex]::Match($Expression, '^(.*?)\s*\?\?\s*(["''])([\s\S]*)\2$')
        if ($FallbackMatch.Success) {
            $ResolvedValue = Resolve-CippTemplateToken -RootValue $RootValue -TokenExpression $FallbackMatch.Groups[1].Value
            if ([string]::IsNullOrEmpty($ResolvedValue)) {
                return $FallbackMatch.Groups[3].Value
            }
            return $ResolvedValue
        }

        $JoinMatch = [regex]::Match($Expression, '^join\((.+?),\s*(["''])([\s\S]*?)\2\)$')
        if ($JoinMatch.Success) {
            $PathValue = Resolve-CippTemplatePath -RootValue $RootValue -Path $JoinMatch.Groups[1].Value.Trim()
            $Separator = $JoinMatch.Groups[3].Value

            $Values = @()
            if ($null -eq $PathValue) {
                $Values = @()
            } elseif ($PathValue -is [System.Collections.IEnumerable] -and $PathValue -isnot [string]) {
                $Values = @($PathValue)
            } else {
                $Values = @($PathValue)
            }

            return (($Values | ForEach-Object { Convert-CippTemplateValueToString -Value $_ }) -join $Separator)
        }

        $CountMatch = [regex]::Match($Expression, '^count\((.+)\)$')
        if ($CountMatch.Success) {
            $CountPathValue = Resolve-CippTemplatePath -RootValue $RootValue -Path $CountMatch.Groups[1].Value.Trim()
            if ($null -eq $CountPathValue) {
                return '0'
            }
            if ($CountPathValue -is [System.Collections.IEnumerable] -and $CountPathValue -isnot [string]) {
                return (@($CountPathValue).Count).ToString()
            }
            return '1'
        }

        return (Convert-CippTemplateValueToString -Value (Resolve-CippTemplatePath -RootValue $RootValue -Path $Expression))
    }

    function New-CippCustomScriptResultMarkdown {
        param(
            $FailedRows,
            $ReturnType,
            $MarkdownTemplate
        )

        if ([string]::IsNullOrWhiteSpace($ReturnType)) {
            $ReturnType = 'JSON'
        }

        if ($ReturnType -eq 'Markdown') {
            if (-not [string]::IsNullOrWhiteSpace($MarkdownTemplate)) {
                return [regex]::Replace($MarkdownTemplate, '\{\{\s*([\s\S]*?)\s*\}\}', {
                        param($Match)
                        Resolve-CippTemplateToken -RootValue $FailedRows -TokenExpression $Match.Groups[1].Value
                    })
            }

            if ($FailedRows.Count -eq 1 -and $FailedRows[0] -is [string] -and -not [string]::IsNullOrWhiteSpace($FailedRows[0])) {
                return $FailedRows[0]
            }
        }

        return "Custom script returned failure result:`n$($FailedRows | ConvertTo-Json -Depth 10)"
    }

    try {
        $Table = Get-CippTable -tablename 'CustomPowershellScripts'
        $Scripts = @(Get-CIPPAzDataTableEntity @Table -Filter "PartitionKey eq 'CustomScript'")
        if (-not $Scripts) {
            return
        }

        $LatestScripts = $Scripts | Group-Object -Property ScriptGuid | ForEach-Object {
            $_.Group | Sort-Object -Property Version -Descending | Select-Object -First 1
        }

        foreach ($Script in $LatestScripts) {
            $IsEnabled = if ($Script.PSObject.Properties['Enabled']) { [bool]$Script.Enabled } else { $true }
            if (-not $IsEnabled) {
                continue
            }
            $ShouldAlert = $false
            if ($Script.PSObject.Properties['AlertOnFailure']) {
                $ShouldAlert = [bool]$Script.AlertOnFailure
            }

            $TestId = "CustomScript-$($Script.ScriptGuid)"
            $ScriptName = if ([string]::IsNullOrWhiteSpace($Script.ScriptName)) { $TestId } else { $Script.ScriptName }
            $ReturnType = if ($Script.PSObject.Properties['ReturnType']) { $Script.ReturnType } else { 'JSON' }
            $MarkdownTemplate = if ($Script.PSObject.Properties['MarkdownTemplate']) { $Script.MarkdownTemplate } else { '' }
            try {
                $Result = New-CippCustomScriptExecution -ScriptGuid $Script.ScriptGuid -TenantFilter $Tenant -Parameters @{}
                $FailedRows = @($Result) | Where-Object {
                    $null -ne $_ -and
                    -not ($_ -is [bool] -and -not $_) -and
                    -not ($_ -is [string] -and [string]::IsNullOrWhiteSpace($_))
                }

                if ($FailedRows.Count -gt 0) {
                    $ResultDataJson = $FailedRows | ConvertTo-Json -Depth 10 -Compress
                    Add-CippTestResult -TenantFilter $Tenant -TestId $TestId -TestType 'Custom' -Status 'Failed' -ResultDataJson $ResultDataJson -Risk ($Script.Risk ?? 'Medium') -Name $ScriptName -Pillar $Script.Pillar -UserImpact $Script.UserImpact -ImplementationEffort $Script.ImplementationEffort -Category 'Custom Script'
                    if ($ShouldAlert) {
                        Write-AlertMessage -tenant $Tenant -message "Custom script test failed: $ScriptName ($($Script.ScriptGuid))"
                    }
                } else {
                    Add-CippTestResult -TenantFilter $Tenant -TestId $TestId -TestType 'Custom' -Status 'Passed' -ResultDataJson '[]' -Risk ($Script.Risk ?? 'Medium') -Name $ScriptName -Pillar $Script.Pillar -UserImpact $Script.UserImpact -ImplementationEffort $Script.ImplementationEffort -Category 'Custom Script'
                }
            } catch {
                $ErrorMessage = Get-CippException -Exception $_
                Add-CippTestResult -TenantFilter $Tenant -TestId $TestId -TestType 'Custom' -Status 'Failed' -ResultMarkdown "Custom script execution failed: $($ErrorMessage.NormalizedError)" -Risk ($Script.Risk ?? 'Medium') -Name $ScriptName -Pillar $Script.Pillar -UserImpact $Script.UserImpact -ImplementationEffort $Script.ImplementationEffort -Category 'Custom Script'
                if ($ShouldAlert) {
                    Write-AlertMessage -tenant $Tenant -message "Custom script execution failed: $ScriptName ($($Script.ScriptGuid)) - $($ErrorMessage.NormalizedError)"
                }
            }
        }
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -API 'Tests' -tenant $Tenant -message "Failed to run custom script tests: $($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage
    }
}
