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

# Import the module to get help content
$ModulePath = Join-Path $SourcePath "CIPPCore.psd1"
if (-not (Test-Path $ModulePath)) {
    Write-Warning "Module manifest not found: $ModulePath"
    return
}

Write-Host "Importing CIPPCore module..."
Import-Module $ModulePath -Force -ErrorAction Stop

# Get all exported functions
$Functions = Get-Command -Module CIPPCore -CommandType Function
Write-Host "Processing $($Functions.Count) functions..."

# Build permissions using Get-Help
$Permissions = [ordered]@{}
$Count = 0

foreach ($Function in $Functions) {
    $FunctionName = $Function.Name
    
    try {
        $Help = Get-Help $FunctionName -ErrorAction Stop
        
        $Role = if ($Help.Role) { $Help.Role.Trim() } else { '' }
        $Functionality = if ($Help.Functionality) { $Help.Functionality.Trim() } else { '' }
        
        # Only store if at least one property exists
        if ($Role -or $Functionality) {
            $Permissions[$FunctionName] = @{
                Role          = $Role
                Functionality = $Functionality
            }
            $Count++
        }
    } catch {
        Write-Warning "Failed to get help for $FunctionName : $_"
    }
}

# Create lib/data directory in output
$DataPath = Join-Path $OutputPath "lib" "data"
if (-not (Test-Path $DataPath)) {
    New-Item -Path $DataPath -ItemType Directory -Force | Out-Null
}

# Generate JSON file
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