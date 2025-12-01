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
$Pattern = '    FunctionsToExport\s*=\s*@\([^)]*\)'
if ($ManifestContent -match $Pattern) {
    $NewContent = [regex]::Replace($ManifestContent, $Pattern, $FunctionsArray, [System.Text.RegularExpressions.RegexOptions]::Singleline)
} else {
    Write-Error "Could not find FunctionsToExport section in manifest"
    return
}

# Write the updated manifest
Set-Content -Path $ManifestPath -Value $NewContent -NoNewline

Write-Host "Updated $ManifestPath with $($FunctionNames.Count) functions" -ForegroundColor Green

# Verify the manifest is valid
try {
    $Manifest = Test-ModuleManifest -Path $ManifestPath -ErrorAction SilentlyContinue
    if ($Manifest.ExportedFunctions.Count -eq $FunctionNames.Count) {
        Write-Host "Manifest validation passed - $($Manifest.ExportedFunctions.Count) functions exported" -ForegroundColor Green
    } else {
        Write-Warning "Function count mismatch: Expected $($FunctionNames.Count), got $($Manifest.ExportedFunctions.Count)"
    }
} catch {
    Write-Warning "Manifest validation warning: $_"
}
