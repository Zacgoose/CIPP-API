function ConvertTo-CIPPAlertSchema {
    <#
    .SYNOPSIS
    Converts alert data to the standardized CIPP alert schema for webhook consumption.

    .DESCRIPTION
    This function transforms various alert data structures into a consistent JSON schema format
    that can be easily consumed by Power Automate, Logic Apps, and other webhook processors.
    The schema is inspired by the Write-LogMessage pattern and provides:
    - Consistent top-level metadata fields
    - Alert-specific data in a predictable structure
    - Version tracking for schema evolution
    - Optional additional context

    .PARAMETER AlertData
    The alert data to be converted. Can be a single object or array of alert objects.

    .PARAMETER AlertType
    The type/category of the alert (e.g., 'Security', 'License', 'Compliance', 'Health').

    .PARAMETER Severity
    The severity level of the alert (Info, Warning, Error, Critical, Alert).

    .PARAMETER Tenant
    The tenant associated with the alert.

    .PARAMETER TenantId
    The tenant ID (GUID) associated with the alert.

    .PARAMETER Source
    The source/origin of the alert (typically the cmdlet or function name).

    .PARAMETER Title
    The title/subject of the alert.

    .PARAMETER CIPPURL
    Optional URL to the CIPP instance for deep links.

    .FUNCTIONALITY
    Internal
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        $AlertData,

        [Parameter(Mandatory = $false)]
        [string]$AlertType = 'General',

        [Parameter(Mandatory = $false)]
        [ValidateSet('Info', 'Warning', 'Error', 'Critical', 'Alert')]
        [string]$Severity = 'Info',

        [Parameter(Mandatory = $false)]
        [string]$Tenant = 'None',

        [Parameter(Mandatory = $false)]
        [string]$TenantId = $null,

        [Parameter(Mandatory = $false)]
        [string]$Source = 'CIPP',

        [Parameter(Mandatory = $false)]
        [string]$Title = '',

        [Parameter(Mandatory = $false)]
        [string]$CIPPURL = ''
    )

    # Ensure AlertData is an array for consistent processing
    if ($AlertData -isnot [array]) {
        $AlertData = @($AlertData)
    }

    # Convert string data to objects with Message property
    if ($AlertData[0] -is [string]) {
        $AlertData = $AlertData | ForEach-Object { @{ Message = $_ } }
    }

    # Build standardized alert schema
    $StandardizedAlert = [PSCustomObject]@{
        # Schema metadata
        SchemaVersion = '1.0'
        AlertVersion  = '1.0.0'
        
        # Timing information
        Timestamp     = (Get-Date).ToUniversalTime().ToString('o')
        PartitionKey  = (Get-Date -UFormat '%Y%m%d').ToString()
        
        # Alert identification
        AlertId       = [guid]::NewGuid().ToString()
        AlertType     = $AlertType
        Source        = $Source
        
        # Tenant information
        Tenant        = $Tenant
        TenantId      = $TenantId
        
        # Alert metadata
        Title         = $Title
        Severity      = $Severity
        
        # Count and summary
        Count         = $AlertData.Count
        Summary       = if ($AlertData.Count -eq 1 -and $AlertData[0].Message) { 
            $AlertData[0].Message 
        } else { 
            "$($AlertData.Count) alert(s) for $Tenant" 
        }
        
        # Deep link support
        CIPPURL       = $CIPPURL
        
        # The actual alert data
        Data          = @($AlertData | ForEach-Object {
                # Remove Azure Table Storage metadata from individual alert items
                $CleanedItem = $_ | Select-Object * -ExcludeProperty ETag, PartitionKey, RowKey, Timestamp
                $CleanedItem
            })
    }

    # Add TenantId only if provided
    if ([string]::IsNullOrEmpty($TenantId)) {
        $StandardizedAlert.PSObject.Properties.Remove('TenantId')
    }

    # Add CIPPURL only if provided
    if ([string]::IsNullOrEmpty($CIPPURL)) {
        $StandardizedAlert.PSObject.Properties.Remove('CIPPURL')
    }

    return $StandardizedAlert
}
