function Convert-CippOrchestratorChildBatches {
    <#
    .SYNOPSIS
        Offload each child orchestrator's Batch to the CippOrchestratorBatch table.

    .DESCRIPTION
        Used by Start-CIPPOrchestrator when starting a coordinator orchestration that
        spawns per-tenant sub-orchestrators. Each child's Batch is written to the shared
        batch table and replaced on the child input with a QueueFunction reference that
        the sub-orchestration will use to retrieve its batch items at execution time.

        This keeps the coordinator orchestration input (which embeds every child) small,
        avoiding the 60 KB orchestration input size limit for large fan-outs.

    .PARAMETER ChildOrchestrators
        The list of child orchestrator input objects (each may carry its own Batch).

    .PARAMETER BatchTable
        Hashtable for Get-CippTable -TableName 'CippOrchestratorBatch' (splatted into
        Add-CIPPAzDataTableEntity).

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
        if (-not $Child) { continue }

        $ChildBatch = $null
        if ($Child -is [hashtable]) {
            $ChildBatch = $Child['Batch']
        } else {
            $ChildBatch = $Child.Batch
        }

        if (-not $ChildBatch -or ($ChildBatch | Measure-Object).Count -eq 0) {
            continue
        }

        $BatchGuid = (New-Guid).Guid.ToString()
        foreach ($BatchItem in $ChildBatch) {
            $BatchEntity = @{
                PartitionKey = $BatchGuid
                RowKey       = (New-Guid).Guid.ToString()
                BatchItem    = [string]($BatchItem | ConvertTo-Json -Depth 10 -Compress)
            }
            Add-CIPPAzDataTableEntity @BatchTable -Entity $BatchEntity -Force
        }

        $QueueFunction = @{
            FunctionName = 'OrchestratorBatchItems'
            Parameters   = @{
                BatchId = $BatchGuid
            }
        }

        if ($Child -is [hashtable]) {
            $Child.Remove('Batch')
            $Child['QueueFunction'] = $QueueFunction
        } else {
            $Child.PSObject.Properties.Remove('Batch')
            $Child | Add-Member -NotePropertyName 'QueueFunction' -NotePropertyValue $QueueFunction -Force
        }
    }
}
