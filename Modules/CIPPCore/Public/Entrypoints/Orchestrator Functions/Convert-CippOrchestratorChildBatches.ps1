function Convert-CippOrchestratorChildBatches {
    <#
    .SYNOPSIS
        Offload each child orchestrator's Batch to the CippOrchestratorBatch table.
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        $ChildOrchestrators,

        [Parameter(Mandatory = $true)]
        [hashtable]$BatchTable
    )

    foreach ($Child in $ChildOrchestrators) {
        $BatchGuid = (New-Guid).Guid.ToString()
        foreach ($BatchItem in $Child.Batch) {
            $BatchEntity = @{
                PartitionKey = $BatchGuid
                RowKey       = (New-Guid).Guid.ToString()
                BatchItem    = [string]($BatchItem | ConvertTo-Json -Depth 10 -Compress)
            }
            Add-CIPPAzDataTableEntity @BatchTable -Entity $BatchEntity -Force
        }

        $Child.PSObject.Properties.Remove('Batch')
        $Child | Add-Member -NotePropertyName 'QueueFunction' -NotePropertyValue @{
            FunctionName = 'OrchestratorBatchItems'
            Parameters   = @{ BatchId = $BatchGuid }
        } -Force
    }
}
