[CmdletBinding()]
param(
    [int]$Rounds = 1,
    [switch]$IncludeCurrentOnly,
    [switch]$IncludeOutputOnly,
    [string]$CsvPath
)

$ErrorActionPreference = 'Stop'

function Get-ModuleManifestPath {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Directory,
        [Parameter(Mandatory = $true)]
        [string]$ModuleName
    )

    $manifest = Join-Path $Directory "$ModuleName.psd1"
    if (Test-Path $manifest) {
        return $manifest
    }

    $moduleFile = Join-Path $Directory "$ModuleName.psm1"
    if (Test-Path $moduleFile) {
        return $moduleFile
    }

    return $null
}

function Measure-ImportMs {
    param(
        [Parameter(Mandatory = $true)]
        [string]$ModuleName,
        [Parameter(Mandatory = $true)]
        [string]$ModulePath
    )

    Remove-Module -Name $ModuleName -Force -ErrorAction SilentlyContinue
    [System.GC]::Collect()
    [System.GC]::WaitForPendingFinalizers()

    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    Import-Module -Name $ModulePath -Force -ErrorAction Stop | Out-Null
    $sw.Stop()

    return [math]::Round($sw.Elapsed.TotalMilliseconds, 2)
}

$repoRoot = Split-Path -Parent $PSScriptRoot
$modulesRoot = Join-Path $repoRoot 'Modules'
$outputRoot = Join-Path $repoRoot 'Output'

if (-not (Test-Path $modulesRoot)) {
    throw "Modules folder not found: $modulesRoot"
}
if (-not (Test-Path $outputRoot)) {
    throw "Output folder not found: $outputRoot"
}

$currentModuleDirs = Get-ChildItem -Path $modulesRoot -Directory | Where-Object { $_.Name -like 'CIPP*' }
$currentMap = @{}
foreach ($dir in $currentModuleDirs) {
    $moduleName = $dir.Name
    $modulePath = Get-ModuleManifestPath -Directory $dir.FullName -ModuleName $moduleName
    if ($modulePath) {
        $currentMap[$moduleName] = $modulePath
    }
}

$outputModuleDirs = Get-ChildItem -Path $outputRoot -Directory | Where-Object { $_.Name -like 'CIPP*-code' }
$outputMap = @{}
foreach ($dir in $outputModuleDirs) {
    $moduleName = $dir.Name -replace '-code$', ''
    $modulePath = Get-ModuleManifestPath -Directory $dir.FullName -ModuleName $moduleName
    if ($modulePath) {
        $outputMap[$moduleName] = $modulePath
    }
}

$allModuleNames = @($currentMap.Keys + $outputMap.Keys | Sort-Object -Unique)
if (-not $allModuleNames -or $allModuleNames.Count -eq 0) {
    throw 'No CIPP* modules found in either Modules or Output.'
}

$results = [System.Collections.Generic.List[object]]::new()

foreach ($moduleName in $allModuleNames) {
    $hasCurrent = $currentMap.ContainsKey($moduleName)
    $hasOutput = $outputMap.ContainsKey($moduleName)

    if (-not $hasCurrent -and -not $IncludeOutputOnly) {
        continue
    }
    if (-not $hasOutput -and -not $IncludeCurrentOnly) {
        continue
    }

    $currentSamples = [System.Collections.Generic.List[double]]::new()
    $outputSamples = [System.Collections.Generic.List[double]]::new()

    for ($i = 1; $i -le $Rounds; $i++) {
        $runOrder = @('Current', 'Output')
        if (Get-Random -Minimum 0 -Maximum 2) {
            $runOrder = @('Output', 'Current')
        }

        foreach ($source in $runOrder) {
            if ($source -eq 'Current' -and $hasCurrent) {
                $ms = Measure-ImportMs -ModuleName $moduleName -ModulePath $currentMap[$moduleName]
                $currentSamples.Add($ms)
            }

            if ($source -eq 'Output' -and $hasOutput) {
                $ms = Measure-ImportMs -ModuleName $moduleName -ModulePath $outputMap[$moduleName]
                $outputSamples.Add($ms)
            }
        }
    }

    $currentAvg = if ($currentSamples.Count -gt 0) { [math]::Round((($currentSamples | Measure-Object -Average).Average), 2) } else { $null }
    $currentMin = if ($currentSamples.Count -gt 0) { [math]::Round((($currentSamples | Measure-Object -Minimum).Minimum), 2) } else { $null }
    $currentMax = if ($currentSamples.Count -gt 0) { [math]::Round((($currentSamples | Measure-Object -Maximum).Maximum), 2) } else { $null }

    $outputAvg = if ($outputSamples.Count -gt 0) { [math]::Round((($outputSamples | Measure-Object -Average).Average), 2) } else { $null }
    $outputMin = if ($outputSamples.Count -gt 0) { [math]::Round((($outputSamples | Measure-Object -Minimum).Minimum), 2) } else { $null }
    $outputMax = if ($outputSamples.Count -gt 0) { [math]::Round((($outputSamples | Measure-Object -Maximum).Maximum), 2) } else { $null }

    $deltaMs = if ($null -ne $currentAvg -and $null -ne $outputAvg) { [math]::Round(($outputAvg - $currentAvg), 2) } else { $null }
    $fasterSource = if ($null -eq $deltaMs) { 'N/A' } elseif ($deltaMs -lt 0) { 'Output' } elseif ($deltaMs -gt 0) { 'Current' } else { 'Equal' }

    $results.Add([PSCustomObject]@{
            Module          = $moduleName
            CurrentAvgMs    = $currentAvg
            CurrentMinMs    = $currentMin
            CurrentMaxMs    = $currentMax
            OutputAvgMs     = $outputAvg
            OutputMinMs     = $outputMin
            OutputMaxMs     = $outputMax
            DeltaMs         = $deltaMs
            FasterSource    = $fasterSource
            CurrentPath     = if ($hasCurrent) { $currentMap[$moduleName] } else { $null }
            OutputPath      = if ($hasOutput) { $outputMap[$moduleName] } else { $null }
        })
}

if ($results.Count -eq 0) {
    throw 'No benchmark results produced. Check flags and module availability.'
}

Write-Host "`nCIPP module import benchmark ($Rounds rounds):" -ForegroundColor Cyan
$results |
    Sort-Object Module |
    Select-Object Module, CurrentAvgMs, OutputAvgMs, DeltaMs, FasterSource |
    Format-Table -AutoSize

$coreModuleName = 'CIPPCore'
$splitModuleNames = @('CIPPAlerts', 'CIPPDB', 'CIPPStandards', 'CIPPTests')

$coreRow = $results | Where-Object { $_.Module -eq $coreModuleName } | Select-Object -First 1
if ($coreRow) {
    $splitRows = $results | Where-Object { $_.Module -in $splitModuleNames }
    $missingSplit = $splitModuleNames | Where-Object { -not ($splitRows.Module -contains $_) }

    $splitCurrentRows = $splitRows | Where-Object { $null -ne $_.CurrentAvgMs }
    $splitOutputRows = $splitRows | Where-Object { $null -ne $_.OutputAvgMs }

    $splitCurrentTotal = if ($splitCurrentRows.Count -gt 0) { [math]::Round((($splitCurrentRows | Measure-Object -Property CurrentAvgMs -Sum).Sum), 2) } else { $null }
    $splitOutputTotal = if ($splitOutputRows.Count -gt 0) { [math]::Round((($splitOutputRows | Measure-Object -Property OutputAvgMs -Sum).Sum), 2) } else { $null }

    Write-Host "`nCIPPCore aggregate comparison (includes CIPPAlerts + CIPPDB + CIPPStandards + CIPPTests):" -ForegroundColor Cyan

    if ($null -ne $coreRow.CurrentAvgMs -and $null -ne $splitCurrentTotal) {
        $deltaCurrent = [math]::Round(($splitCurrentTotal - $coreRow.CurrentAvgMs), 2)
        $ratioCurrent = if ($coreRow.CurrentAvgMs -ne 0) { [math]::Round(($splitCurrentTotal / $coreRow.CurrentAvgMs), 2) } else { $null }
        Write-Host "- Current: SplitTotal=$splitCurrentTotal ms, CIPPCore=$($coreRow.CurrentAvgMs) ms, Delta=$deltaCurrent ms, Ratio=${ratioCurrent}x"
    }
    else {
        Write-Host "- Current: Not enough data to compare split total against CIPPCore."
    }

    if ($null -ne $coreRow.OutputAvgMs -and $null -ne $splitOutputTotal) {
        $deltaOutput = [math]::Round(($splitOutputTotal - $coreRow.OutputAvgMs), 2)
        $ratioOutput = if ($coreRow.OutputAvgMs -ne 0) { [math]::Round(($splitOutputTotal / $coreRow.OutputAvgMs), 2) } else { $null }
        Write-Host "- Output:  SplitTotal=$splitOutputTotal ms, CIPPCore=$($coreRow.OutputAvgMs) ms, Delta=$deltaOutput ms, Ratio=${ratioOutput}x"
    }
    else {
        Write-Host "- Output:  Not enough data to compare split total against CIPPCore."
    }

    if ($missingSplit.Count -gt 0) {
        Write-Host "- Missing split modules in result set: $($missingSplit -join ', ')" -ForegroundColor Yellow
    }
}
else {
    Write-Host "`nCIPPCore aggregate comparison skipped: CIPPCore was not present in benchmark results." -ForegroundColor Yellow
}

if ($CsvPath) {
    $results | Export-Csv -Path $CsvPath -NoTypeInformation -Encoding UTF8
    Write-Host "`nDetailed results exported to: $CsvPath" -ForegroundColor Green
}

Write-Host "`nNotes:" -ForegroundColor Yellow
Write-Host "- DeltaMs = OutputAvgMs - CurrentAvgMs (negative means Output is faster)."
Write-Host "- If a module exists only on one side, the other side is blank unless include flags are used."
