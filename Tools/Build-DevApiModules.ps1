$ErrorActionPreference = 'Stop'

$toolsRoot = $PSScriptRoot
$repoRoot = Split-Path -Parent $toolsRoot
$modulesRoot = Join-Path $repoRoot 'Modules'
$outputRoot = Join-Path $repoRoot 'Output'

Write-Host "Repo root: $repoRoot"
Set-Location -Path $repoRoot

& (Join-Path $toolsRoot 'Build-FunctionParameters.ps1')
& (Join-Path $toolsRoot 'Build-FunctionPermissions.ps1')

Build-Module -SourcePath (Join-Path $modulesRoot 'CIPPCore')
Build-Module -SourcePath (Join-Path $modulesRoot 'CIPPDB')
Build-Module -SourcePath (Join-Path $modulesRoot 'CIPPTests')
Build-Module -SourcePath (Join-Path $modulesRoot 'CIPPStandards')
Build-Module -SourcePath (Join-Path $modulesRoot 'CIPPAlerts')
Build-Module -SourcePath (Join-Path $modulesRoot 'CippExtensions')

$moduleNames = @(
    'CIPPCore',
    'CIPPDB',
    'CIPPTests',
    'CIPPStandards',
    'CIPPAlerts',
    'CippExtensions'
)

foreach ($moduleName in $moduleNames) {
    $sourceDir = Join-Path $outputRoot $moduleName
    $targetDir = Join-Path $modulesRoot $moduleName

    if (-not (Test-Path -Path $sourceDir)) {
        throw "Expected output module path not found: $sourceDir"
    }

    if (Test-Path -Path $targetDir) {
        Remove-Item -Path $targetDir -Recurse -Force
    }

    Copy-Item -Path $sourceDir -Destination $targetDir -Recurse -Force
    Write-Host "Replaced module '$moduleName' from '$sourceDir'"
}

Write-Host 'Build and module replacement complete.'
