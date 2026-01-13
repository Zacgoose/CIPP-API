function Remove-CIPPAzDataTableEntity {
    <#
    .SYNOPSIS
    Removes an entity from Azure Table Storage, including any split parts.
    
    .DESCRIPTION
    This function removes an entity from Azure Table Storage. If the entity was split
    into multiple parts by Add-CIPPAzDataTableEntity, this function will also remove
    all the split parts (rows with RowKey pattern: {OriginalRowKey}-part*).
    
    .PARAMETER Context
    The Azure Table Storage context.
    
    .PARAMETER Entity
    The entity to remove. Can be a single entity or an array of entities.
    
    .PARAMETER Force
    If specified, forces the removal without confirmation.
    
    .EXAMPLE
    Remove-CIPPAzDataTableEntity -Context $Context -Entity $Entity -Force
    
    .FUNCTIONALITY
    Internal
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        $Context,
        
        [Parameter(Mandatory = $true)]
        $Entity,
        
        [switch]$Force
    )

    foreach ($SingleEntity in @($Entity)) {
        try {
            # Remove the main entity
            if ($Force) {
                Remove-AzDataTableEntity -Context $Context -Entity $SingleEntity -Force
            } else {
                Remove-AzDataTableEntity -Context $Context -Entity $SingleEntity
            }

            # Check if this entity might have split parts
            # Split parts have RowKey pattern: {OriginalRowKey}-part{N}
            $partitionKey = $SingleEntity.PartitionKey
            $rowKey = $SingleEntity.RowKey
            
            # Only check for parts if the entity doesn't already have OriginalEntityId
            # (meaning it's not itself a part)
            $hasOriginalId = $SingleEntity.PSObject.Properties.Match('OriginalEntityId') -and $SingleEntity.OriginalEntityId
            
            if (-not $hasOriginalId) {
                # Try to find and remove any split parts
                $partIndex = 1
                while ($true) {
                    $partRowKey = "$rowKey-part$partIndex"
                    try {
                        Remove-AzDataTableEntity -Context $Context -PartitionKey $partitionKey -RowKey $partRowKey -ErrorAction Stop
                        Write-Information "Deleted split part: $partRowKey"
                        $partIndex++
                    } catch {
                        # No more parts found
                        break
                    }
                }
            }
        } catch {
            Write-Warning "Error removing entity with PartitionKey: $($SingleEntity.PartitionKey), RowKey: $($SingleEntity.RowKey): $($_.Exception.Message)"
            throw
        }
    }
}
