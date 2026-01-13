# Pester tests for Remove-CIPPAzDataTableEntity
# Verifies that split entities are properly cleaned up when removing templates

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    $FunctionPath = Join-Path $RepoRoot 'Modules' 'CIPPCore' 'Public' 'Remove-CIPPAzDataTableEntity.ps1'

    # Mock the AzBobbyTables cmdlet
    function Remove-AzDataTableEntity { 
        param($Context, $Entity, $PartitionKey, $RowKey, [switch]$Force, [switch]$ErrorAction) 
    }

    # Source the function
    . $FunctionPath
}

Describe 'Remove-CIPPAzDataTableEntity' {
    BeforeEach {
        $script:RemovedEntities = @()
        $script:RemovalAttempts = 0

        Mock -CommandName Remove-AzDataTableEntity -MockWith {
            param($Context, $Entity, $PartitionKey, $RowKey, [switch]$Force)
            
            $script:RemovalAttempts++
            
            # Check for throw conditions BEFORE tracking
            if ($PartitionKey -and $RowKey) {
                # Simulate that parts 1, 2, 3 exist but 4 doesn't
                if ($RowKey -match '-part([0-9]+)$') {
                    $partNum = [int]$Matches[1]
                    if ($partNum -ge 4) {
                        throw "Entity not found"
                    }
                }
            }
            
            # Track what was removed (only if we didn't throw above)
            if ($Entity) {
                $script:RemovedEntities += @{
                    Type = 'Entity'
                    PartitionKey = $Entity.PartitionKey
                    RowKey = $Entity.RowKey
                }
            } elseif ($PartitionKey -and $RowKey) {
                $script:RemovedEntities += @{
                    Type = 'ByKey'
                    PartitionKey = $PartitionKey
                    RowKey = $RowKey
                }
            }
        } -Verifiable
    }

    It 'removes a simple entity without split parts' {
        $entity = [PSCustomObject]@{
            PartitionKey = 'StandardsTemplateV2'
            RowKey = 'test-template-123'
            JSON = '{"templateName": "Test Template"}'
        }

        $mockContext = [PSCustomObject]@{ TableName = 'templates' }

        Remove-CIPPAzDataTableEntity -Context $mockContext -Entity $entity -Force

        # Should attempt to remove main entity + check for part1 (which throws)
        $script:RemovalAttempts | Should -BeGreaterOrEqual 2
        $script:RemovedEntities[0].RowKey | Should -Be 'test-template-123'
        $script:RemovedEntities[0].Type | Should -Be 'Entity'
    }

    It 'removes main entity and all split parts' {
        $entity = [PSCustomObject]@{
            PartitionKey = 'StandardsTemplateV2'
            RowKey = 'large-template-456'
            JSON = '{"templateName": "Large Template"}'
        }

        $mockContext = [PSCustomObject]@{ TableName = 'templates' }

        Remove-CIPPAzDataTableEntity -Context $mockContext -Entity $entity -Force

        # Should remove main entity + part1, part2, part3 (part4 throws)
        # Main entity + 3 parts + 1 failed attempt = 5 total attempts
        $script:RemovalAttempts | Should -Be 5
        $script:RemovedEntities[0].RowKey | Should -Be 'large-template-456'
        
        # Check that parts were attempted (should find 3 successful removals)
        $partRemovals = $script:RemovedEntities | Where-Object { $_.RowKey -match '-part[0-9]+$' }
        $partRemovals.Count | Should -Be 3
        ($partRemovals | Where-Object { $_.RowKey -eq 'large-template-456-part1' }) | Should -Not -BeNullOrEmpty
        ($partRemovals | Where-Object { $_.RowKey -eq 'large-template-456-part2' }) | Should -Not -BeNullOrEmpty
        ($partRemovals | Where-Object { $_.RowKey -eq 'large-template-456-part3' }) | Should -Not -BeNullOrEmpty
    }

    It 'does not attempt to remove parts for an entity that is itself a part' {
        $partEntity = [PSCustomObject]@{
            PartitionKey = 'StandardsTemplateV2'
            RowKey = 'template-789-part1'
            OriginalEntityId = 'template-789'
            PartIndex = 1
        }

        $mockContext = [PSCustomObject]@{ TableName = 'templates' }

        Remove-CIPPAzDataTableEntity -Context $mockContext -Entity $partEntity -Force

        # Should only remove the part itself, not look for sub-parts
        $script:RemovalAttempts | Should -Be 1
        $script:RemovedEntities[0].RowKey | Should -Be 'template-789-part1'
    }

    It 'handles multiple entities in a single call' {
        $entities = @(
            [PSCustomObject]@{
                PartitionKey = 'StandardsTemplateV2'
                RowKey = 'template-1'
                JSON = '{}'
            },
            [PSCustomObject]@{
                PartitionKey = 'StandardsTemplateV2'
                RowKey = 'template-2'
                JSON = '{}'
            }
        )

        $mockContext = [PSCustomObject]@{ TableName = 'templates' }

        Remove-CIPPAzDataTableEntity -Context $mockContext -Entity $entities -Force

        # Should process both entities
        $mainRemovals = $script:RemovedEntities | Where-Object { $_.Type -eq 'Entity' }
        $mainRemovals.Count | Should -Be 2
        ($mainRemovals | Where-Object { $_.RowKey -eq 'template-1' }) | Should -Not -BeNullOrEmpty
        ($mainRemovals | Where-Object { $_.RowKey -eq 'template-2' }) | Should -Not -BeNullOrEmpty
    }

    It 'respects Force parameter' {
        $entity = [PSCustomObject]@{
            PartitionKey = 'StandardsTemplateV2'
            RowKey = 'test-template'
            JSON = '{}'
        }

        $mockContext = [PSCustomObject]@{ TableName = 'templates' }

        # Verify mock was called with Force parameter
        Remove-CIPPAzDataTableEntity -Context $mockContext -Entity $entity -Force

        Assert-MockCalled -CommandName Remove-AzDataTableEntity -Times 1 -ParameterFilter { 
            $Force -eq $true 
        } -Scope It
    }
}
