function Push-CIPPDBCacheApplyBatch {
    <#
    .SYNOPSIS
        Aggregate cache tasks from all tenants and start a coordinator orchestrator (Phase 2)

    .DESCRIPTION
        PostExecution function for the DBCache pipeline. Receives aggregated results from the
        per-tenant CIPPDBCacheData list activities, groups the tasks by TenantFilter, and starts
        a coordinator orchestrator that spawns one sub-orchestration per tenant to execute that
        tenant's cache tasks.

        This replaces the previous flat Phase-2 orchestrator (which fanned out every task in a
        single orchestrator and caused DTFx history/instance/control-queue write storms at scale).
        Each tenant's sub-orchestrator now owns its own small history partition; the coordinator
        only tracks N sub-orchestration starts + completions + a single PostExecution.

        The TestRun PostExecution is attached to the coordinator, so it runs exactly once after
        all per-tenant sub-orchestrators complete.

    .FUNCTIONALITY
        Entrypoint
    #>
    param($Item)

    try {
        # Aggregate all cache tasks from all tenant list activities
        $AllTasks = [System.Collections.Generic.List[object]]::new()

        foreach ($TenantResult in $Item.Results) {
            foreach ($Batch in $TenantResult) {
                foreach ($Task in $Batch) {
                    if ($Task -and $Task.FunctionName) {
                        $AllTasks.Add($Task)
                    }
                }
            }
        }

        if ($AllTasks.Count -eq 0) {
            Write-Information 'No cache tasks to execute across all tenants'
            return @{ Success = $true; TaskCount = 0; ChildCount = 0 }
        }

        # Group tasks by tenant; one sub-orchestrator per TenantFilter
        $TasksByTenant = $AllTasks | Group-Object -Property TenantFilter

        # Every cache task must carry a TenantFilter — that's a hard invariant of the pipeline.
        # If Group-Object produces a group with no name, Phase 1 emitted a malformed task and we
        # refuse to silently bucket it; fail the aggregator so the upstream bug surfaces.
        $MissingTenant = @($TasksByTenant | Where-Object { [string]::IsNullOrWhiteSpace($_.Name) })
        if ($MissingTenant.Count -gt 0) {
            $OrphanCount = ($MissingTenant | Measure-Object -Property Count -Sum).Sum
            throw "DBCache apply batch: $OrphanCount task(s) were missing TenantFilter — every cache task must have one. Check Push-CIPPDBCacheData."
        }

        $ChildOrchestrators = foreach ($Group in $TasksByTenant) {
            [PSCustomObject]@{
                OrchestratorName = "CIPPDBCacheExecute-$($Group.Name)"
                Batch            = @($Group.Group)
                SkipLog          = $true
            }
        }
        $ChildOrchestrators = @($ChildOrchestrators)

        Write-Information "Aggregated $($AllTasks.Count) cache tasks across $($ChildOrchestrators.Count) tenant sub-orchestrator(s)"

        # Build coordinator input
        $InputObject = [PSCustomObject]@{
            OrchestratorName   = 'CIPPDBCacheCoordinator'
            ChildOrchestrators = $ChildOrchestrators
            SkipLog            = $true
        }

        # Add test run post-execution if flagged — runs once after all sub-orchestrators complete
        if ($Item.Parameters -and $Item.Parameters.TestRun -eq $true -and $Item.Parameters.TenantFilter) {
            $InputObject | Add-Member -NotePropertyName PostExecution -NotePropertyValue @{
                FunctionName = 'CIPPDBTestsRun'
                Parameters   = @{
                    TenantFilter = $Item.Parameters.TenantFilter
                }
            }
        }

        $InstanceId = Start-CIPPOrchestrator -InputObject $InputObject
        Write-Information "Started cache coordinator orchestrator ID = '$InstanceId' for $($ChildOrchestrators.Count) tenant(s) / $($AllTasks.Count) total task(s)"

        return @{
            Success    = $true
            TaskCount  = $AllTasks.Count
            ChildCount = $ChildOrchestrators.Count
            InstanceId = $InstanceId
        }

    } catch {
        Write-Warning "Error in DBCache apply batch aggregation: $($_.Exception.Message)"
        return @{ Success = $false; Error = $_.Exception.Message }
    }
}
