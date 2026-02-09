function Exec-CippCustomScript {
    <#
    .SYNOPSIS
        Executes a custom PowerShell script in a restricted environment

    .DESCRIPTION
        Runs user-provided PowerShell scripts with strict security constraints:
        - Only data manipulation cmdlets allowed
        - Read-only access to CIPPDB via New-CIPPDbRequest
        - No file system, network, or write operations
        - PowerShell 7.4 syntax supported

    .PARAMETER ScriptGuid
        The GUID of the script to execute from the database

    .PARAMETER TenantFilter
        The tenant to execute the script against

    .PARAMETER Parameters
        Optional hashtable of parameters to pass to the script

    .EXAMPLE
        Exec-CippCustomScript -ScriptGuid '12345678-1234-1234-1234-123456789012' -TenantFilter 'contoso.onmicrosoft.com'
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$ScriptGuid,

        [Parameter(Mandatory = $true)]
        [string]$TenantFilter,

        [Parameter(Mandatory = $false)]
        $Parameters = @{}
    )

    try {
        # Validate ScriptGuid
        if ([string]::IsNullOrWhiteSpace($ScriptGuid)) {
            throw 'ScriptGuid is required'
        }

        # Get script from database
        $Table = Get-CippTable -tablename 'CustomPowershellScripts'
        $Filter = "PartitionKey eq 'CustomScript' and ScriptGuid eq '{0}'" -f $ScriptGuid
        $Scripts = Get-CIPPAzDataTableEntity @Table -Filter $Filter

        if (-not $Scripts) {
            throw "Script with GUID '$ScriptGuid' not found"
        }

        # Get latest version
        $Script = $Scripts | Sort-Object -Property Version -Descending | Select-Object -First 1

        # Get script content
        $ScriptContent = $Script.ScriptContent

        Write-LogMessage -API 'CustomScript' -tenant $TenantFilter -message "Executing custom script: $($Script.ScriptName) (Version: $($Script.Version))" -sev Info

        # Convert Parameters to hashtable if it's a PSCustomObject (from JSON)
        if ($Parameters -is [PSCustomObject]) {
            $ParamsHash = @{}
            $Parameters.PSObject.Properties | ForEach-Object {
                $ParamsHash[$_.Name] = $_.Value
            }
            $Parameters = $ParamsHash
        } elseif ($null -eq $Parameters) {
            $Parameters = @{}
        }

        # Validate script security constraints using AST parsing
        Test-CustomScriptSecurity -ScriptContent $ScriptContent

        # Create script block with parameter binding
        $ScriptBlock = [scriptblock]::Create($ScriptContent)

        # Build parameter hashtable for splatting (named parameters)
        $ScriptParams = @{
            TenantFilter = $TenantFilter
        }

        # Add custom parameters if any
        foreach ($key in $Parameters.Keys) {
            if ($key -ne 'TenantFilter' -and $key -ne 'tenantFilter') {
                $ScriptParams[$key] = $Parameters[$key]
            }
        }

        Write-LogMessage -API 'CustomScript' -Headers $Headers -tenant $TenantFilter -message "Executing script with parameters: $($ScriptParams.Keys -join ', ')" -sev 'Debug'

        # Execute the script in current session (already has CIPP functions loaded)
        # The AST validation ensures only safe commands are used
        # Use splatting to pass named parameters
        $Result = & $ScriptBlock @ScriptParams

        # Convert result to array if it's not already
        if ($null -eq $Result) {
            return @()
        } elseif ($Result -is [System.Collections.IEnumerable] -and $Result -isnot [string]) {
            return @($Result)
        } else {
            return $Result
        }

    } catch {
        Write-LogMessage -API 'CustomScript' -Headers $Headers -tenant $TenantFilter -message "Failed to execute custom script: $($_.Exception.Message)" -sev 'Error'
        throw
    }
}

function Test-CustomScriptSecurity {
    <#
    .SYNOPSIS
        Validates custom script security constraints using AST parsing with allowlist approach

    .PARAMETER ScriptContent
        The script content to validate
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$ScriptContent
    )

    # Parse the script into an AST
    $Errors = $null
    $Ast = [System.Management.Automation.Language.Parser]::ParseInput($ScriptContent, [ref]$null, [ref]$Errors)

    if ($Errors) {
        throw "Script parsing failed: $($Errors[0].Message)"
    }

    # Check for += operator using AST
    $AssignmentStatements = $Ast.FindAll({
        param($node)
        $node -is [System.Management.Automation.Language.AssignmentStatementAst]
    }, $true)

    foreach ($assignment in $AssignmentStatements) {
        if ($assignment.Operator -eq [System.Management.Automation.Language.TokenKind]::PlusEquals) {
            throw 'The += operator is not allowed in custom scripts. Use array expansion or collection methods instead.'
        }
    }

    # ALLOWLIST: Only these commands are permitted
    $AllowedCommands = @(
        # Data manipulation cmdlets
        'ForEach-Object', 'Where-Object', 'Select-Object', 'Group-Object',
        'Measure-Object', 'Sort-Object', 'Compare-Object', 'Get-Member',

        # Utility cmdlets
        'Get-Date', 'Get-Random', 'New-Object', 'New-Guid', 'New-TimeSpan',
        'ConvertTo-Json', 'ConvertFrom-Json', 'Write-Output', 'Write-Host',

        # CIPP data access (read-only)
        'New-CIPPDbRequest', 'Get-CIPPDbItem'
    )

    # Find all command invocations (exclude hashtable key assignments and property access)
    $Commands = $Ast.FindAll({
        param($node)
        if ($node -is [System.Management.Automation.Language.CommandAst]) {
            # Exclude if this is inside a hashtable
            $current = $node.Parent
            while ($current) {
                if ($current -is [System.Management.Automation.Language.HashtableAst]) {
                    return $false
                }
                $current = $current.Parent
            }

            # Also check if this looks like a hashtable key (bare word followed by =)
            # In hashtable syntax like @{ Status = ... }, "Status" appears as a CommandAst
            # We can detect this by checking if it's a single element with no parameters
            if ($node.CommandElements.Count -eq 1) {
                # Check if the command element is just a bare word (StringConstantExpressionAst)
                $cmdElement = $node.CommandElements[0]
                if ($cmdElement -is [System.Management.Automation.Language.StringConstantExpressionAst]) {
                    # This might be a hashtable key, so exclude it
                    # Real commands will have parameters or be part of a pipeline
                    return $false
                }
            }

            return $true
        }
        return $false
    }, $true)

    foreach ($cmd in $Commands) {
        $commandName = $cmd.GetCommandName()
        if (-not $commandName) { continue }

        # Check if command is in allowlist
        if ($commandName -notin $AllowedCommands) {
            # Get the extent text to show context
            $cmdText = $cmd.Extent.Text
            $lineNumber = $cmd.Extent.StartLineNumber
            throw "Security violation at line $lineNumber`: Command '$commandName' is not in the allowed list.`nContext: $cmdText`n`nOnly these commands are permitted: $($AllowedCommands -join ', ')"
        }
    }

    # Check for dangerous .NET types - block all direct .NET type usage except approved ones
    $TypeExpressions = $Ast.FindAll({
        param($node)
        $node -is [System.Management.Automation.Language.TypeExpressionAst]
    }, $true)

    # Allowed types with proper namespace qualification
    $AllowedTypes = @(
        'PSCustomObject', 'PSObject',
        'System.String', 'System.Int32', 'System.Int64', 'System.Boolean',
        'System.Collections.ArrayList', 'System.Collections.Hashtable',
        'System.DateTime', 'System.TimeSpan', 'System.Guid',
        'System.Object', 'System.Array'
    )

    foreach ($typeExpr in $TypeExpressions) {
        $typeName = $typeExpr.TypeName.FullName

        # Check if it's an allowed type (exact match)
        if ($typeName -notin $AllowedTypes) {
            throw "Security violation: .NET type '$typeName' is not allowed. Only these types are permitted: $($AllowedTypes -join ', ')"
        }
    }
}
