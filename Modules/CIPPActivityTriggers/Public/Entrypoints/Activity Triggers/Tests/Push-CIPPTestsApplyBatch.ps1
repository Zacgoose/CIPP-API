function Push-CIPPTestsApplyBatch {
    <#
    .SYNOPSIS
        Aggregate test tasks from all tenants and start a coordinator orchestrator (Phase 2)

    .DESCRIPTION
        PostExecution function for the Tests pipeline. Receives aggregated results from the
        per-tenant CIPPTestsList activities, groups the tasks by TenantFilter, and starts a
        coordinator orchestrator that spawns one sub-orchestration per tenant to execute that
        tenant's test tasks.

        This replaces the previous flat Phase-2 orchestrator (which fanned out every task in a
        single orchestrator and caused DTFx history/instance/control-queue write storms at scale).
        Each tenant's sub-orchestrator now owns its own small history partition; the coordinator
        only tracks N sub-orchestration starts + completions.

    .FUNCTIONALITY
        Entrypoint
    #>
    param($Item)

    try {
        # Aggregate all test tasks from all tenant list activities
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
            Write-Information 'No test tasks to execute across all tenants'
            return @{ Success = $true; TaskCount = 0; ChildCount = 0 }
        }

        # Group tasks by tenant; one sub-orchestrator per TenantFilter
        $TasksByTenant = $AllTasks | Group-Object -Property TenantFilter
        $ChildOrchestrators = foreach ($Group in $TasksByTenant) {
            [PSCustomObject]@{
                OrchestratorName = "CIPPTestsExecute-$($Group.Name)"
                Batch            = @($Group.Group)
                SkipLog          = $true
            }
        }
        $ChildOrchestrators = @($ChildOrchestrators)

        Write-Information "Aggregated $($AllTasks.Count) test tasks across $($ChildOrchestrators.Count) tenant sub-orchestrator(s)"

        # Build coordinator input (no coordinator-level PostExecution for this pipeline)
        $InputObject = [PSCustomObject]@{
            OrchestratorName   = 'CIPPTestsCoordinator'
            ChildOrchestrators = $ChildOrchestrators
            SkipLog            = $true
        }

        $InstanceId = Start-CIPPOrchestrator -InputObject $InputObject
        Write-Information "Started tests coordinator orchestrator ID = '$InstanceId' for $($ChildOrchestrators.Count) tenant(s) / $($AllTasks.Count) total task(s)"

        return @{
            Success    = $true
            TaskCount  = $AllTasks.Count
            ChildCount = $ChildOrchestrators.Count
            InstanceId = $InstanceId
        }

    } catch {
        Write-Warning "Error in Tests apply batch aggregation: $($_.Exception.Message)"
        return @{ Success = $false; Error = $_.Exception.Message }
    }
}
