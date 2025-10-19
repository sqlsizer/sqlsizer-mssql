<#
.SYNOPSIS
    Pester tests for QueryBuilders functions.
    
.DESCRIPTION
    Unit tests for SQL query building functions.
    Tests verify SQL structure, parameter injection, and correctness.
#>

BeforeAll {
    # Import the module
    $modulePath = Split-Path -Parent $PSScriptRoot
    Import-Module "$modulePath\SqlSizer-MSSQL\SqlSizer-MSSQL" -Force -Verbose
    
    . "$modulePath\SqlSizer-MSSQL\Shared\Get-ColumnValue.ps1"
}

Describe 'New-GetNextOperationQuery' {
    It 'Generates DFS query when UseDfs is true' {
        $result = New-GetNextOperationQuery `
            -SessionId 'TEST-SESSION-123' `
            -UseDfs $true

        $result | Should -Match 'ORDER BY RemainingRecords DESC'
        $result | Should -Not -Match 'ORDER BY o\.Depth ASC'
        $result | Should -Match "SessionId = 'TEST-SESSION-123'"
    }

    It 'Generates BFS query when UseDfs is false' {
        $result = New-GetNextOperationQuery `
            -SessionId 'TEST-SESSION-456' `
            -UseDfs $false

        $result | Should -Match 'ORDER BY o\.Depth ASC, RemainingRecords DESC'
        $result | Should -Match "SessionId = 'TEST-SESSION-456'"
    }

    It 'Includes required fields in SELECT' {
        $result = New-GetNextOperationQuery `
            -SessionId 'TEST' `
            -UseDfs $false

        $result | Should -Match 'TableId'
        $result | Should -Match 'TableSchema'
        $result | Should -Match 'TableName'
        $result | Should -Match 'State'
        $result | Should -Match 'Depth'
        $result | Should -Match 'RemainingRecords'
    }

    It 'Filters by Status IS NULL' {
        $result = New-GetNextOperationQuery `
            -SessionId 'TEST' `
            -UseDfs $false

        $result | Should -Match 'WHERE o\.Status IS NULL'
    }

    It 'Returns TOP 1 result' {
        $result = New-GetNextOperationQuery `
            -SessionId 'TEST' `
            -UseDfs $false

        $result | Should -Match 'SELECT TOP 1'
    }
}

Describe 'New-MarkOperationInProgressQuery' {
    Context 'Unlimited batch size' {
        It 'Sets Processed to ToProcess when MaxBatchSize is -1' {
            $result = New-MarkOperationInProgressQuery `
                -TableId 5 `
                -State 1 `
                -Depth 2 `
                -SessionId 'TEST-SESSION' `
                -MaxBatchSize -1

            $result | Should -Match 'Processed = ToProcess'
            $result | Should -Not -Match 'DECLARE @Remaining'
        }

        It 'Filters by correct table, state, and depth' {
            $result = New-MarkOperationInProgressQuery `
                -TableId 10 `
                -State 2 `
                -Depth 5 `
                -SessionId 'TEST' `
                -MaxBatchSize -1

            $result | Should -Match '\[Table\] = 10'
            $result | Should -Match 'Color = 2'
            $result | Should -Match 'Depth = 5'
        }

        It 'Sets Status to 0 (in progress)' {
            $result = New-MarkOperationInProgressQuery `
                -TableId 1 `
                -State 1 `
                -Depth 1 `
                -SessionId 'TEST' `
                -MaxBatchSize -1

            $result | Should -Match 'Status = 0'
        }
    }

    Context 'Limited batch size' {
        It 'Uses batch logic when MaxBatchSize is set' {
            $result = New-MarkOperationInProgressQuery `
                -TableId 5 `
                -State 1 `
                -Depth 2 `
                -SessionId 'TEST' `
                -MaxBatchSize 1000

            $result | Should -Match 'DECLARE @Remaining INT = 1000'
            $result | Should -Match 'CASE'
            $result | Should -Match '@Remaining'
        }

        It 'Includes batch size in query' {
            $result = New-MarkOperationInProgressQuery `
                -TableId 1 `
                -State 1 `
                -Depth 1 `
                -SessionId 'TEST' `
                -MaxBatchSize 500

            $result | Should -Match '500'
        }

        It 'Filters by @Remaining > 0' {
            $result = New-MarkOperationInProgressQuery `
                -TableId 1 `
                -State 1 `
                -Depth 1 `
                -SessionId 'TEST' `
                -MaxBatchSize 100

            $result | Should -Match '@Remaining > 0'
        }
    }

    It 'Includes SessionId in WHERE clause' {
        $result = New-MarkOperationInProgressQuery `
            -TableId 1 `
            -State 1 `
            -Depth 1 `
            -SessionId 'MY-CUSTOM-SESSION' `
            -MaxBatchSize -1

        $result | Should -Match "SessionId = 'MY-CUSTOM-SESSION'"
    }
}

Describe 'New-CompleteOperationsQuery' {
    It 'Resets operations that hit batch limit' {
        $result = New-CompleteOperationsQuery `
            -SessionId 'TEST-SESSION' `
            -Iteration 10

        $result | Should -Match 'UPDATE SqlSizer\.Operations'
        $result | Should -Match 'SET Status = NULL'
        $result | Should -Match 'WHERE Status = 0'
        $result | Should -Match 'ToProcess <> Processed'
    }

    It 'Marks fully processed operations as complete' {
        $result = New-CompleteOperationsQuery `
            -SessionId 'TEST-SESSION' `
            -Iteration 10

        $result | Should -Match 'Status = 1'
        $result | Should -Match 'ProcessedIteration = 10'
        $result | Should -Match 'ProcessedDate = GETDATE\(\)'
    }

    It 'Filters by SessionId' {
        $result = New-CompleteOperationsQuery `
            -SessionId 'MY-SESSION-789' `
            -Iteration 5

        $result | Should -Match "SessionId = 'MY-SESSION-789'"
    }

    It 'Uses correct iteration number' {
        $result = New-CompleteOperationsQuery `
            -SessionId 'TEST' `
            -Iteration 42

        $result | Should -Match 'ProcessedIteration = 42'
    }

    It 'Contains comment explaining logic' {
        $result = New-CompleteOperationsQuery `
            -SessionId 'TEST' `
            -Iteration 1

        $result | Should -Match '-- Reset operations'
        $result | Should -Match '-- Mark fully processed'
    }
}

Describe 'New-GetIterationStatisticsQuery' {
    It 'Selects all required statistics' {
        $result = New-GetIterationStatisticsQuery -SessionId 'TEST'

        $result | Should -Match 'COUNT\(\*\) AS TotalOperations'
        $result | Should -Match 'CompletedOperations'
        $result | Should -Match 'TotalRecordsProcessed'
        $result | Should -Match 'TotalRecordsRemaining'
        $result | Should -Match 'MaxDepthReached'
    }

    It 'Filters by SessionId' {
        $result = New-GetIterationStatisticsQuery -SessionId 'STATS-SESSION-123'

        $result | Should -Match "SessionId = 'STATS-SESSION-123'"
    }

    It 'Calculates remaining records correctly' {
        $result = New-GetIterationStatisticsQuery -SessionId 'TEST'

        $result | Should -Match 'SUM\(ToProcess - Processed\)'
    }

    It 'Uses MAX for depth' {
        $result = New-GetIterationStatisticsQuery -SessionId 'TEST'

        $result | Should -Match 'MAX\(Depth\)'
    }

    It 'Counts completed operations' {
        $result = New-GetIterationStatisticsQuery -SessionId 'TEST'

        $result | Should -Match 'SUM\(CASE WHEN Status = 1 THEN 1 ELSE 0 END\)'
    }
}

Describe 'New-PendingResolutionQuery' {
    BeforeAll {
        $mockTableInfo = [PSCustomObject]@{
            SchemaName = 'dbo'
            TableName  = 'Orders'
            PrimaryKey = @(
                [PSCustomObject]@{ Name = 'OrderID' },
                [PSCustomObject]@{ Name = 'OrderType' }
            )
        }
    }

    It 'Generates query for non-Synapse' {
        $result = New-PendingResolutionQuery `
            -ProcessingTable 'SqlSizer.Processing_Orders' `
            -TableInfo $mockTableInfo `
            -Iteration 5 `
            -IsSynapse $false

        $result | Should -Match 'GO'
    }

    It 'Omits GO for Synapse' {
        $result = New-PendingResolutionQuery `
            -ProcessingTable 'SqlSizer.Processing_Orders' `
            -TableInfo $mockTableInfo `
            -Iteration 5 `
            -IsSynapse $true

        $result | Should -Not -Match '\nGO\n'
    }

    It 'Updates Pending to Include' {
        $result = New-PendingResolutionQuery `
            -ProcessingTable 'SqlSizer.Processing_Orders' `
            -TableInfo $mockTableInfo `
            -Iteration 5 `
            -IsSynapse $false

        # Pending state = 2, Include state = 1
        $result | Should -Match 'pending\.Color = 3'
        $result | Should -Match 'SET Color = 1'
    }

    It 'Joins on all primary key columns' {
        $result = New-PendingResolutionQuery `
            -ProcessingTable 'SqlSizer.Processing_Orders' `
            -TableInfo $mockTableInfo `
            -Iteration 5 `
            -IsSynapse $false

        $result | Should -Match 'pending\.Key0 = inc\.Key0'
        $result | Should -Match 'pending\.Key1 = inc\.Key1'
    }

    It 'Uses correct table name' {
        $result = New-PendingResolutionQuery `
            -ProcessingTable 'SqlSizer.Custom_Processing_Table' `
            -TableInfo $mockTableInfo `
            -Iteration 5 `
            -IsSynapse $false

        $result | Should -Match 'FROM SqlSizer\.Custom_Processing_Table'
    }

    It 'Includes iteration in comment' {
        $result = New-PendingResolutionQuery `
            -ProcessingTable 'SqlSizer.Processing_Orders' `
            -TableInfo $mockTableInfo `
            -Iteration 42 `
            -IsSynapse $false

        $result | Should -Match 'iteration 42'
    }

    It 'Declares @Changed variable' {
        $result = New-PendingResolutionQuery `
            -ProcessingTable 'SqlSizer.Processing_Orders' `
            -TableInfo $mockTableInfo `
            -Iteration 5 `
            -IsSynapse $false

        $result | Should -Match 'DECLARE @Changed INT = 0'
        $result | Should -Match 'SET @Changed = @@ROWCOUNT'
    }
}

Describe 'New-ExcludePendingQuery' {
    BeforeAll {
        $mockTableInfo = [PSCustomObject]@{
            SchemaName = 'dbo'
            TableName  = 'Orders'
        }
    }

    It 'Updates Pending to Exclude' {
        $result = New-ExcludePendingQuery `
            -ProcessingTable 'SqlSizer.Processing_Orders' `
            -TableInfo $mockTableInfo `
            -IsSynapse $false

        # Pending state = 3, Exclude state = 2
        $result | Should -Match 'SET Color = 2'
        $result | Should -Match 'WHERE Color = 3'
    }

    It 'Uses correct processing table' {
        $result = New-ExcludePendingQuery `
            -ProcessingTable 'SqlSizer.Custom_Table' `
            -TableInfo $mockTableInfo `
            -IsSynapse $false

        $result | Should -Match 'UPDATE SqlSizer\.Custom_Table'
    }

    It 'Includes GO for non-Synapse' {
        $result = New-ExcludePendingQuery `
            -ProcessingTable 'SqlSizer.Processing_Orders' `
            -TableInfo $mockTableInfo `
            -IsSynapse $false

        $result | Should -Match 'GO'
    }

    It 'Omits GO for Synapse' {
        $result = New-ExcludePendingQuery `
            -ProcessingTable 'SqlSizer.Processing_Orders' `
            -TableInfo $mockTableInfo `
            -IsSynapse $true

        $result | Should -Not -Match '\nGO\n'
    }

    It 'Includes descriptive comment' {
        $result = New-ExcludePendingQuery `
            -ProcessingTable 'SqlSizer.Processing_Orders' `
            -TableInfo $mockTableInfo `
            -IsSynapse $false

        $result | Should -Match '-- Mark remaining Pending as Exclude'
        $result | Should -Match 'dbo\.Orders'
    }
}

Describe 'New-CTETraversalQuery - Structure Tests' {
    BeforeAll {
        # Create minimal mock objects for testing
        $mockSourceTable = [PSCustomObject]@{
            SchemaName = 'dbo'
            TableName  = 'Customers'
            PrimaryKey = @([PSCustomObject]@{ Name = 'CustomerID'; DataType = 'int' })
        }

        $mockTargetTable = [PSCustomObject]@{
            SchemaName = 'dbo'
            TableName  = 'Orders'
            PrimaryKey = @([PSCustomObject]@{ Name = 'OrderID'; DataType = 'int' })
        }

        $mockFk = [PSCustomObject]@{
            Name      = 'FK_Orders_Customers'
            FkColumns = @([PSCustomObject]@{ Name = 'CustomerID'; DataType = 'int' })
        }

        # Create mock tables with multiple columns for dynamic key testing
        $mockSourceTableMultiKey = [PSCustomObject]@{
            SchemaName = 'dbo'
            TableName  = 'CompositeKeyTable'
            PrimaryKey = @(
                [PSCustomObject]@{ Name = 'Key1'; DataType = 'int' },
                [PSCustomObject]@{ Name = 'Key2'; DataType = 'varchar' },
                [PSCustomObject]@{ Name = 'Key3'; DataType = 'uniqueidentifier' }
            )
        }

        $mockTargetTableMultiKey = [PSCustomObject]@{
            SchemaName = 'dbo'
            TableName  = 'RelatedTable'
            PrimaryKey = @(
                [PSCustomObject]@{ Name = 'RelatedKey1'; DataType = 'int' },
                [PSCustomObject]@{ Name = 'RelatedKey2'; DataType = 'varchar' }
            )
        }

        $mockFkMultiColumn = [PSCustomObject]@{
            Name      = 'FK_Related_Composite'
            FkColumns = @(
                [PSCustomObject]@{ Name = 'FkKey1'; DataType = 'int' },
                [PSCustomObject]@{ Name = 'FkKey2'; DataType = 'varchar' }
            )
        }

        # Mock Get-ColumnValue function
        Mock Get-ColumnValue { return "tgt.$ColumnName" }
        
        # Mock helper functions that might be called
        Mock Get-AdditionalWhereConditions { return @() }
        Mock Get-TopClause { return "" }
    }

    It 'Includes CTE structure' {
        $result = New-CTETraversalQuery `
            -SourceProcessing 'SqlSizer.Proc_Source' `
            -TargetProcessing 'SqlSizer.Proc_Target' `
            -SourceTable $mockSourceTable `
            -TargetTable $mockTargetTable `
            -Fk $mockFk `
            -Direction ([TraversalDirection]::Outgoing) `
            -NewState ([TraversalState]::Include) `
            -SourceTableId 1 `
            -TargetTableId 2 `
            -FkId 10 `
            -Constraints @{} `
            -Iteration 5 `
            -SessionId 'TEST-SESSION' `
            -MaxBatchSize -1 `
            -FullSearch $false `
            -IsSynapse $false

        $result | Should -Match 'WITH SourceRecords AS'
        $result | Should -Match 'NewRecords AS'
    }

    It 'Includes INSERT INTO statement' {
        $result = New-CTETraversalQuery `
            -SourceProcessing 'SqlSizer.Proc_Source' `
            -TargetProcessing 'SqlSizer.Proc_Target' `
            -SourceTable $mockSourceTable `
            -TargetTable $mockTargetTable `
            -Fk $mockFk `
            -Direction ([TraversalDirection]::Outgoing) `
            -NewState ([TraversalState]::Include) `
            -SourceTableId 1 `
            -TargetTableId 2 `
            -FkId 10 `
            -Constraints @{} `
            -Iteration 5 `
            -SessionId 'TEST-SESSION' `
            -MaxBatchSize -1 `
            -FullSearch $false `
            -IsSynapse $false

        $result | Should -Match 'INSERT INTO SqlSizer\.Proc_Target'
    }

    It 'Includes operations table update' {
        $result = New-CTETraversalQuery `
            -SourceProcessing 'SqlSizer.Proc_Source' `
            -TargetProcessing 'SqlSizer.Proc_Target' `
            -SourceTable $mockSourceTable `
            -TargetTable $mockTargetTable `
            -Fk $mockFk `
            -Direction ([TraversalDirection]::Outgoing) `
            -NewState ([TraversalState]::Include) `
            -SourceTableId 1 `
            -TargetTableId 2 `
            -FkId 10 `
            -Constraints @{} `
            -Iteration 5 `
            -SessionId 'TEST-SESSION' `
            -MaxBatchSize -1 `
            -FullSearch $false `
            -IsSynapse $false

        $result | Should -Match 'INSERT INTO SqlSizer\.Operations'
    }

    It 'Includes FK name in comment' {
        $result = New-CTETraversalQuery `
            -SourceProcessing 'SqlSizer.Proc_Source' `
            -TargetProcessing 'SqlSizer.Proc_Target' `
            -SourceTable $mockSourceTable `
            -TargetTable $mockTargetTable `
            -Fk $mockFk `
            -Direction ([TraversalDirection]::Outgoing) `
            -NewState ([TraversalState]::Include) `
            -SourceTableId 1 `
            -TargetTableId 2 `
            -FkId 10 `
            -Constraints @{} `
            -Iteration 5 `
            -SessionId 'TEST-SESSION' `
            -MaxBatchSize -1 `
            -FullSearch $false `
            -IsSynapse $false

        $result | Should -Match 'FK_Orders_Customers'
    }

    It 'Shows OUTGOING direction in comment' {
        $result = New-CTETraversalQuery `
            -SourceProcessing 'SqlSizer.Proc_Source' `
            -TargetProcessing 'SqlSizer.Proc_Target' `
            -SourceTable $mockSourceTable `
            -TargetTable $mockTargetTable `
            -Fk $mockFk `
            -Direction ([TraversalDirection]::Outgoing) `
            -NewState ([TraversalState]::Include) `
            -SourceTableId 1 `
            -TargetTableId 2 `
            -FkId 10 `
            -Constraints @{} `
            -Iteration 5 `
            -SessionId 'TEST-SESSION' `
            -MaxBatchSize -1 `
            -FullSearch $false `
            -IsSynapse $false

        $result | Should -Match '-- Traverse OUTGOING FK'
    }

    It 'Shows INCOMING direction in comment' {
        $result = New-CTETraversalQuery `
            -SourceProcessing 'SqlSizer.Proc_Source' `
            -TargetProcessing 'SqlSizer.Proc_Target' `
            -SourceTable $mockSourceTable `
            -TargetTable $mockTargetTable `
            -Fk $mockFk `
            -Direction ([TraversalDirection]::Incoming) `
            -NewState ([TraversalState]::Include) `
            -SourceTableId 1 `
            -TargetTableId 2 `
            -FkId 10 `
            -Constraints @{} `
            -Iteration 5 `
            -SessionId 'TEST-SESSION' `
            -MaxBatchSize -1 `
            -FullSearch $false `
            -IsSynapse $false

        $result | Should -Match '-- Traverse INCOMING FK'
    }

    It 'Omits GO for Synapse' {
        $result = New-CTETraversalQuery `
            -SourceProcessing 'SqlSizer.Proc_Source' `
            -TargetProcessing 'SqlSizer.Proc_Target' `
            -SourceTable $mockSourceTable `
            -TargetTable $mockTargetTable `
            -Fk $mockFk `
            -Direction ([TraversalDirection]::Outgoing) `
            -NewState ([TraversalState]::Include) `
            -SourceTableId 1 `
            -TargetTableId 2 `
            -FkId 10 `
            -Constraints @{} `
            -Iteration 5 `
            -SessionId 'TEST-SESSION' `
            -MaxBatchSize -1 `
            -FullSearch $true `
            -IsSynapse $true

        $result | Should -Not -Match '\nGO\n'
    }

    Context 'Dynamic Key Column Generation' {
        It 'Generates single key column for single PK' {
            $result = New-CTETraversalQuery `
                -SourceProcessing 'SqlSizer.Proc_Source' `
                -TargetProcessing 'SqlSizer.Proc_Target' `
                -SourceTable $mockSourceTable `
                -TargetTable $mockTargetTable `
                -Fk $mockFk `
                -Direction ([TraversalDirection]::Outgoing) `
                -NewState ([TraversalState]::Include) `
                -SourceTableId 1 `
                -TargetTableId 2 `
                -FkId 10 `
                -Constraints @{} `
                -Iteration 5 `
                -SessionId 'TEST-SESSION' `
                -MaxBatchSize -1 `
                -FullSearch $false `
                -IsSynapse $false

            # Should have Key0 in SourceRecords
            $result | Should -Match 'SELECT Key0, Depth, Fk'
            # Should NOT have hardcoded Key1, Key2, etc.
            $result | Should -Not -Match 'Key0, Key1, Key2, Key3, Key4, Key5, Key6, Key7'
        }

        It 'Generates multiple key columns for composite PK in source' {
            $result = New-CTETraversalQuery `
                -SourceProcessing 'SqlSizer.Proc_Source' `
                -TargetProcessing 'SqlSizer.Proc_Target' `
                -SourceTable $mockSourceTableMultiKey `
                -TargetTable $mockTargetTableMultiKey `
                -Fk $mockFkMultiColumn `
                -Direction ([TraversalDirection]::Outgoing) `
                -NewState ([TraversalState]::Include) `
                -SourceTableId 1 `
                -TargetTableId 2 `
                -FkId 10 `
                -Constraints @{} `
                -Iteration 5 `
                -SessionId 'TEST-SESSION' `
                -MaxBatchSize -1 `
                -FullSearch $false `
                -IsSynapse $false

            # For outgoing, source columns = PK (3 columns), target columns = FK columns (2 columns)
            # SourceRecords should have Key0, Key1, Key2
            $result | Should -Match 'SELECT Key0, Key1, Key2, Depth, Fk'
        }

        It 'Generates correct INSERT column list for single key' {
            $result = New-CTETraversalQuery `
                -SourceProcessing 'SqlSizer.Proc_Source' `
                -TargetProcessing 'SqlSizer.Proc_Target' `
                -SourceTable $mockSourceTable `
                -TargetTable $mockTargetTable `
                -Fk $mockFk `
                -Direction ([TraversalDirection]::Outgoing) `
                -NewState ([TraversalState]::Include) `
                -SourceTableId 1 `
                -TargetTableId 2 `
                -FkId 10 `
                -Constraints @{} `
                -Iteration 5 `
                -SessionId 'TEST-SESSION' `
                -MaxBatchSize -1 `
                -FullSearch $false `
                -IsSynapse $false

            # INSERT should only list Key0 (since FK has 1 column)
            $result | Should -Match 'INSERT INTO SqlSizer\.Proc_Target \(Key0, Color, Source, Depth, Fk, Iteration\)'
        }

        It 'Generates correct INSERT column list for composite key' {
            $result = New-CTETraversalQuery `
                -SourceProcessing 'SqlSizer.Proc_Source' `
                -TargetProcessing 'SqlSizer.Proc_Target' `
                -SourceTable $mockSourceTableMultiKey `
                -TargetTable $mockTargetTableMultiKey `
                -Fk $mockFkMultiColumn `
                -Direction ([TraversalDirection]::Outgoing) `
                -NewState ([TraversalState]::Include) `
                -SourceTableId 1 `
                -TargetTableId 2 `
                -FkId 10 `
                -Constraints @{} `
                -Iteration 5 `
                -SessionId 'TEST-SESSION' `
                -MaxBatchSize -1 `
                -FullSearch $false `
                -IsSynapse $false

            # For outgoing: target columns = FK columns (2 columns)
            # INSERT should list Key0, Key1
            $result | Should -Match 'INSERT INTO SqlSizer\.Proc_Target \(Key0, Key1, Color, Source, Depth, Fk, Iteration\)'
        }

        It 'Does not include hardcoded 8-column key list' {
            $result = New-CTETraversalQuery `
                -SourceProcessing 'SqlSizer.Proc_Source' `
                -TargetProcessing 'SqlSizer.Proc_Target' `
                -SourceTable $mockSourceTableMultiKey `
                -TargetTable $mockTargetTableMultiKey `
                -Fk $mockFkMultiColumn `
                -Direction ([TraversalDirection]::Incoming) `
                -NewState ([TraversalState]::Include) `
                -SourceTableId 1 `
                -TargetTableId 2 `
                -FkId 10 `
                -Constraints @{} `
                -Iteration 5 `
                -SessionId 'TEST-SESSION' `
                -MaxBatchSize -1 `
                -FullSearch $false `
                -IsSynapse $false

            # Should NOT have the old hardcoded 8-column pattern
            $result | Should -Not -Match 'Key0, Key1, Key2, Key3, Key4, Key5, Key6, Key7, Depth, Fk'
        }

        It 'Handles incoming direction with different key columns' {
            $result = New-CTETraversalQuery `
                -SourceProcessing 'SqlSizer.Proc_Source' `
                -TargetProcessing 'SqlSizer.Proc_Target' `
                -SourceTable $mockSourceTableMultiKey `
                -TargetTable $mockTargetTableMultiKey `
                -Fk $mockFkMultiColumn `
                -Direction ([TraversalDirection]::Incoming) `
                -NewState ([TraversalState]::Include) `
                -SourceTableId 1 `
                -TargetTableId 2 `
                -FkId 10 `
                -Constraints @{} `
                -Iteration 5 `
                -SessionId 'TEST-SESSION' `
                -MaxBatchSize -1 `
                -FullSearch $false `
                -IsSynapse $false

            # For incoming: source columns = FK columns (2), target columns = target PK (2)
            # SourceRecords should have Key0, Key1
            $result | Should -Match 'SELECT Key0, Key1, Depth, Fk'
        }
    }
}
