#Requires -Version 7.0
<#
.SYNOPSIS
    Creates a versioned snapshot of API endpoint functions only
.DESCRIPTION
    Copies and renames only Invoke-*.ps1 files to create a locked version.
    Supporting scripts and helper functions remain in the latest version only.
.PARAMETER Version
    The version number to create (e.g., "v1", "v2")
.PARAMETER Force
    Overwrite existing version if it exists
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidatePattern('^v\d+$')]
    [string]$Version,
    [Parameter()]
    [switch]$Force
)

# Find source path
$SourcePath = Join-Path $PSScriptRoot "Modules\CIPPCore\Public"
if (-not (Test-Path $SourcePath)) {
    $SourcePath = "Modules\CIPPCore\Public"
}
if (-not (Test-Path $SourcePath)) {
    throw "Could not find CIPPCore Public folder at: $SourcePath"
}

$EntrypointsSource = Join-Path $SourcePath "Entrypoints"
$VersionTarget = Join-Path $SourcePath $Version
$VersionEntrypoints = Join-Path $VersionTarget "Entrypoints"

# Validation
if (-not (Test-Path $EntrypointsSource)) {
    throw "Source Entrypoints folder not found: $EntrypointsSource"
}

if ((Test-Path $VersionTarget) -and -not $Force) {
    throw "Version $Version already exists. Use -Force to overwrite."
}

# Remove existing version if Force is specified
if ((Test-Path $VersionTarget) -and $Force) {
    Remove-Item $VersionTarget -Recurse -Force
    Write-Host "Removed existing version $Version" -ForegroundColor Yellow
}

# Get only Invoke-*.ps1 files to copy (skip supporting scripts)
$InvokeFiles = Get-ChildItem -Path $EntrypointsSource -Recurse -File -Filter "Invoke-*.ps1"

Write-Host "Creating version $Version..." -ForegroundColor Cyan
Write-Host "Found $($InvokeFiles.Count) Invoke-*.ps1 files to version" -ForegroundColor Cyan

# Create base directory structure
New-Item -Path $VersionTarget -ItemType Directory -Force | Out-Null
New-Item -Path $VersionEntrypoints -ItemType Directory -Force | Out-Null

# Copy and rename only Invoke-*.ps1 files
$renamedFiles = 0
foreach ($file in $InvokeFiles) {
    # Calculate relative path from EntrypointsSource
    $relativePath = $file.FullName.Substring($EntrypointsSource.Length).TrimStart('\', '/')

    # Extract endpoint name from Invoke-*.ps1 filename
    if ($file.Name -match '^Invoke-(.+)\.ps1$') {
        $endpointName = $matches[1]
        $newFileName = "Invoke-" + $endpointName + "_" + $Version + ".ps1"

        # Build target path maintaining folder structure
        $relativeFolder = Split-Path $relativePath -Parent
        if ($relativeFolder) {
            $targetFolder = Join-Path $VersionEntrypoints $relativeFolder
            $targetFile = Join-Path $targetFolder $newFileName
        } else {
            $targetFile = Join-Path $VersionEntrypoints $newFileName
        }

        # Create target directory if it doesn't exist
        $targetDir = Split-Path $targetFile -Parent
        if (-not (Test-Path $targetDir)) {
            New-Item -Path $targetDir -ItemType Directory -Force | Out-Null
        }

        # Read file content and update function name
        $content = Get-Content $file.FullName -Raw
        $originalFunctionName = "Invoke-$endpointName"
        $newFunctionName = "Invoke-" + $endpointName + "_" + $Version

        # Replace function definition
        $updatedContent = $content -replace "function\s+$originalFunctionName\b", "function $newFunctionName"

        # Write updated content to new file
        Set-Content -Path $targetFile -Value $updatedContent -Encoding UTF8
        $renamedFiles++

        Write-Verbose "Versioned: $($file.Name) -> $newFileName (function: $originalFunctionName -> $newFunctionName)"
    }
}

# Count unique folders created
$foldersCreated = Get-ChildItem -Path $VersionEntrypoints -Recurse -Directory | Measure-Object | Select-Object -ExpandProperty Count

# Create version metadata
$versionInfo = @{
    Version = $Version
    CreatedDate = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss UTC')
    InvokeFileCount = $InvokeFiles.Count
    RenamedFiles = $renamedFiles
    FolderCount = $foldersCreated
    Note = "Only Invoke-*.ps1 files are versioned, supporting scripts remain in latest"
}

$versionInfoPath = Join-Path $VersionTarget "version-info.json"
$versionInfo | ConvertTo-Json -Depth 2 | Set-Content $versionInfoPath

Write-Host "Created version $Version successfully!" -ForegroundColor Green
Write-Host "  - Invoke files versioned: $($InvokeFiles.Count)" -ForegroundColor Green
Write-Host "  - Functions renamed: $renamedFiles" -ForegroundColor Green
Write-Host "  - Folders created: $foldersCreated" -ForegroundColor Green
Write-Host "  - Version directory: $VersionTarget" -ForegroundColor Gray
Write-Host "  - Supporting scripts remain in latest version only" -ForegroundColor Gray
Write-Host ""
Write-Warning "IMPORTANT: Remember to update the supported versions list in your entrypoints file!"
Write-Host "Add '$Version' to the " -NoNewline
Write-Host "`$SupportedAPIVersions" -ForegroundColor Yellow -NoNewline
Write-Host " array in your Receive-CippHttpTrigger function"
