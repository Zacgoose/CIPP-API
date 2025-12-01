$StartTime = Get-Date
$Timings = @{}

Write-Information '#### CIPP-API Start ####'

# Time: Module imports
$ModuleStartTime = Get-Date
@('CIPPCore', 'CippExtensions', 'Az.KeyVault', 'Az.Accounts', 'AzBobbyTables') | ForEach-Object {
    $ModuleImportStart = Get-Date
    try {
        $Module = $_
        Import-Module -Name $_ -ErrorAction Stop
        $Timings["Import-$Module"] = (Get-Date) - $ModuleImportStart
    } catch {
        Write-LogMessage -message "Failed to import module - $Module" -LogData (Get-CippException -Exception $_) -Sev 'debug'
        $_.Exception.Message
    }
}
$Timings["AllModules"] = (Get-Date) - $ModuleStartTime

if ($env:ExternalDurablePowerShellSDK -eq $true) {
    $DurableStart = Get-Date
    try {
        Import-Module AzureFunctions.PowerShell.Durable.SDK -ErrorAction Stop
        $Timings["Import-DurableSDK"] = (Get-Date) - $DurableStart
        Write-Information 'External Durable SDK enabled'
    } catch {
        Write-LogMessage -message 'Failed to import module - AzureFunctions.PowerShell.Durable.SDK' -LogData (Get-CippException -Exception $_) -Sev 'debug'
        $_.Exception.Message
    }
}

try {
    Disable-AzContextAutosave -Scope Process | Out-Null
} catch {}

# Time: KeyVault authentication
$AuthStart = Get-Date
try {
    if (!$env:SetFromProfile) {
        Write-Information "We're reloading from KV"
        $Auth = Get-CIPPAuthentication
        $Timings["KeyVault-Auth"] = (Get-Date) - $AuthStart
    }
} catch {
    Write-LogMessage -message 'Could not retrieve keys from Keyvault' -LogData (Get-CippException -Exception $_) -Sev 'debug'
    $Timings["KeyVault-Auth"] = (Get-Date) - $AuthStart
}

Set-Location -Path $PSScriptRoot
$CurrentVersion = (Get-Content .\version_latest.txt).trim()

# Time: Table operations
$TableStart = Get-Date
$Table = Get-CippTable -tablename 'Version'
Write-Information "Function App: $($env:WEBSITE_SITE_NAME) | API Version: $CurrentVersion | PS Version: $($PSVersionTable.PSVersion)"
$LastStartup = Get-CIPPAzDataTableEntity @Table -Filter "PartitionKey eq 'Version' and RowKey eq '$($env:WEBSITE_SITE_NAME)'"
if (!$LastStartup -or $CurrentVersion -ne $LastStartup.Version) {
    Write-Information "Version has changed from $($LastStartup.Version ?? 'None') to $CurrentVersion"
    if ($LastStartup) {
        $LastStartup.Version = $CurrentVersion
        $LastStartup | Add-Member -MemberType NoteProperty -Name 'PSVersion' -Value $PSVersionTable.PSVersion.ToString() -Force
    } else {
        $LastStartup = [PSCustomObject]@{
            PartitionKey = 'Version'
            RowKey       = $env:WEBSITE_SITE_NAME
            Version      = $CurrentVersion
            PSVersion    = $PSVersionTable.PSVersion.ToString()
        }
    }
    Update-AzDataTableEntity @Table -Entity $LastStartup -Force -ErrorAction SilentlyContinue
    try {
        Clear-CippDurables
    } catch {
        Write-LogMessage -message 'Failed to clear durables after update' -LogData (Get-CippException -Exception $_) -Sev 'Error'
    }
    $ReleaseTable = Get-CippTable -tablename 'cacheGitHubReleaseNotes'
    Remove-AzDataTableEntity @ReleaseTable -Entity @{ PartitionKey = 'GitHubReleaseNotes'; RowKey = 'GitHubReleaseNotes' } -ErrorAction SilentlyContinue
    Write-Host 'Cleared GitHub release notes cache to force refresh on version update.'
}
$Timings["TableOperations"] = (Get-Date) - $TableStart

# Total startup time
$TotalTime = (Get-Date) - $StartTime
$Timings["TotalStartup"] = $TotalTime

# Log all timings
$TimingMessage = $Timings.GetEnumerator() | ForEach-Object { "$($_.Key): $($_.Value.TotalMilliseconds)ms" } | Out-String
Write-Information "=== Startup Timings ===`n$TimingMessage"

# Send to Application Insights for analysis
$customDimensions = @{}
$Timings.GetEnumerator() | ForEach-Object {
    $customDimensions[$_.Key] = $_.Value.TotalMilliseconds
}
Write-Information "Startup completed in $($TotalTime.TotalSeconds) seconds" -Tags @{ 'StartupTimings' = ($customDimensions | ConvertTo-Json -Compress) }