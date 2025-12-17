param(
    [string]$ModulePath = (Join-Path $PSScriptRoot '..' 'Modules' 'CIPPCore'),
    [string]$OutputPath,
    [string]$ModuleName
)

$ErrorActionPreference = 'Stop'

function Resolve-ModuleImportPath {
    param(
        [Parameter(Mandatory = $true)][string]$Root,
        [Parameter(Mandatory = $true)][string]$Name
    )

    $psd1 = Join-Path $Root "$Name.psd1"
    if (Test-Path $psd1) { return $psd1 }

    $psm1 = Join-Path $Root "$Name.psm1"
    if (Test-Path $psm1) { return $psm1 }

    throw "Module files not found for '$Name' in '$Root'. Expected $Name.psd1 or $Name.psm1."
}

# Resolve defaults
$ModulePath = (Resolve-Path -Path $ModulePath).ProviderPath
if (-not $ModuleName) { $ModuleName = (Split-Path -Path $ModulePath -Leaf) }
if (-not $OutputPath) {
    $OutputPath = Join-Path $ModulePath 'lib' 'data' 'function-permissions.json'
}

# Ensure destination directory exists
$null = New-Item -ItemType Directory -Path (Split-Path -Parent $OutputPath) -Force

# Import target module so Get-Help can read Role/Functionality metadata
$ModuleImportPath = Resolve-ModuleImportPath -Root $ModulePath -Name $ModuleName
Import-Module -Name $ModuleImportPath -Force

$commands = Get-Command -Module $ModuleName -CommandType Function
$permissions = [ordered]@{}

foreach ($command in $commands | Sort-Object -Property Name -Unique) {
    $help = Get-Help -Name $command.Name -ErrorAction SilentlyContinue
    if ($help) {
        $roleProperty = $help.PSObject.Properties['Role']
        $functionalityProperty = $help.PSObject.Properties['Functionality']
        $role = if ($roleProperty) { $roleProperty.Value } else { '' }
        $functionality = if ($functionalityProperty) { $functionalityProperty.Value } else { '' }
    } else {
        $role = ''
        $functionality = ''
    }

    $permissions[$command.Name] = @{
        Role          = $role
        Functionality = $functionality
    }
}

# Depth 3 is sufficient for the flat hashtable of functions -> (Role, Functionality)
$json = $permissions | ConvertTo-Json -Depth 3
Set-Content -Path $OutputPath -Value $json -Encoding UTF8

Write-Host "Wrote permissions for $($permissions.Count) functions to $OutputPath"
