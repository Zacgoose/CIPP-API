<#
.SYNOPSIS
    Updates the FunctionsToExport list in CIPPCore.psd1

.DESCRIPTION
    This script scans all .ps1 files in the CIPPCore Public directory and updates
    the FunctionsToExport array in the module manifest. This improves module loading
    performance by providing an explicit list of exports rather than using wildcards.

    Run this script after adding or removing public functions to keep the manifest
    in sync with the actual function files.

.EXAMPLE
    .\Update-CIPPCoreFunctionsExport.ps1
#>

[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

# Get paths
$ScriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$RepoRoot = Split-Path -Parent $ScriptRoot
$ModulePath = Join-Path $RepoRoot 'Modules' 'CIPPCore'
$ManifestPath = Join-Path $ModulePath 'CippCore.psd1'
$PublicPath = Join-Path $ModulePath 'Public'

Write-Host "Scanning for public functions in: $PublicPath" -ForegroundColor Cyan

# Get all public function names
$FunctionNames = Get-ChildItem -Path $PublicPath -Filter '*.ps1' -Recurse |
    Select-Object -ExpandProperty BaseName |
    Sort-Object -Unique

Write-Host "Found $($FunctionNames.Count) public functions" -ForegroundColor Cyan

# Read the current manifest
$ManifestContent = Get-Content -Path $ManifestPath -Raw

# Build the new FunctionsToExport array with proper formatting
$FunctionLines = $FunctionNames | ForEach-Object { "        '$_'" }
$FunctionsArray = "    FunctionsToExport = @(`n" + ($FunctionLines -join "`n") + "`n    )"

# Replace existing FunctionsToExport using a regex that matches multiline arrays
# Pattern matches: FunctionsToExport = @( ... ) including newlines and nested content
$Pattern = '(?s)    FunctionsToExport\s*=\s*@\(.*?\n    \)'
if ([regex]::IsMatch($ManifestContent, $Pattern)) {
    $NewContent = [regex]::Replace($ManifestContent, $Pattern, $FunctionsArray)
} else {
    Write-Error "Could not find FunctionsToExport section in manifest. Ensure the manifest has 'FunctionsToExport = @(...)' defined."
    return
}

# Write the updated manifest
Set-Content -Path $ManifestPath -Value $NewContent -NoNewline

Write-Host "Updated $ManifestPath with $($FunctionNames.Count) functions" -ForegroundColor Green

# Verify the manifest is valid using Import-PowerShellDataFile for faster validation
try {
    $ManifestData = Import-PowerShellDataFile -Path $ManifestPath
    $ExportedCount = $ManifestData.FunctionsToExport.Count
    if ($ExportedCount -eq $FunctionNames.Count) {
        Write-Host "Manifest validation passed - $ExportedCount functions exported" -ForegroundColor Green
    } else {
        Write-Warning "Function count mismatch: Expected $($FunctionNames.Count), got $ExportedCount"
    }
} catch {
    Write-Warning "Manifest validation warning: $_"
}
