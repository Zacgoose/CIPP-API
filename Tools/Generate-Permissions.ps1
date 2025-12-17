#Requires -Version 7
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$SourcePath,
    
    [Parameter(Mandatory)]
    [string]$OutputPath
)

Write-Host "Generating function permissions cache from source files..."
$sw = [System.Diagnostics.Stopwatch]::StartNew()

# Get all function files from Public folder
$PublicPath = Join-Path $SourcePath "Public"
if (-not (Test-Path $PublicPath)) {
    Write-Warning "Public functions path not found: $PublicPath"
    return
}

$FunctionFiles = Get-ChildItem -Path $PublicPath -Filter "*.ps1" -Recurse -File
Write-Host "Processing $($FunctionFiles.Count) function files..."

# Build permissions by parsing comment-based help directly
$Permissions = [ordered]@{}
$Count = 0

foreach ($File in $FunctionFiles) {
    $Content = Get-Content -Path $File.FullName -Raw
    $FunctionName = $File.BaseName
    
    # Extract .ROLE using regex
    $Role = ''
    if ($Content -match '(?m)^\s*\.ROLE\s*$\s*^([^\r\n.]+?)(?=\s*(?:^$|^\s*\.|\s*#>))') {
        $Role = $Matches[1].Trim() -replace '\s+', ' '
    }
    
    # Extract .FUNCTIONALITY using regex
    $Functionality = ''
    if ($Content -match '(?m)^\s*\.FUNCTIONALITY\s*$\s*^([^\r\n.]+?)(?=\s*(?:^$|^\s*\.|\s*#>))') {
        $Functionality = $Matches[1].Trim() -replace '\s+', ' '
    }
    
    # Only store if at least one property exists
    if ($Role -or $Functionality) {
        $Permissions[$FunctionName] = @{
            Role          = $Role
            Functionality = $Functionality
        }
        $Count++
    }
}

# Create lib/data directory in output
$DataPath = Join-Path $OutputPath "lib" "data"
if (-not (Test-Path $DataPath)) {
    New-Item -Path $DataPath -ItemType Directory -Force | Out-Null
}

# Generate JSON file (more reliable than PSD1 for large datasets)
$PermissionsFile = Join-Path $DataPath "function-permissions.json"

# Convert to JSON and write
$JsonContent = $Permissions | ConvertTo-Json -Depth 3 -Compress
[System.IO.File]::WriteAllText($PermissionsFile, $JsonContent, [System.Text.UTF8Encoding]::new($false))

# Verify the file is valid JSON
try {
    $TestLoad = Get-Content -Path $PermissionsFile -Raw | ConvertFrom-Json -AsHashtable
    Write-Host "✓ Verified JSON file is valid"
    Write-Host "✓ Contains $($TestLoad.Count) entries"
} catch {
    Write-Error "Generated JSON file is invalid: $_"
    throw
}

$sw.Stop()
$FileSize = [math]::Round((Get-Item $PermissionsFile).Length / 1KB, 2)

Write-Host "✓ Generated permissions for $Count functions in $($sw.ElapsedMilliseconds)ms"
Write-Host "  Output: $PermissionsFile ($FileSize KB)"