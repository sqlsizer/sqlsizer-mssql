<#
.SYNOPSIS
    Pester tests for QueryBuilders functions.
    
.DESCRIPTION
    Unit tests for SQL query building functions.
    Tests verify SQL structure, parameter injection, and correctness.
#>

BeforeAll {
    $modulePath = Split-Path -Parent $PSScriptRoot
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
            $result | Should -Match 'ProcessedIteration = Processed'
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
            $result | Should -Match '\[State\] = 2'
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
            $result | Should -Match 'DECLARE @OperationId INT'
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
            $result | Should -Match 'ProcessedIteration = Processed'
            $result | Should -Match 'WHERE Id = @OperationId'
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
        $result | Should -Match 'ProcessedIteration = NULL'
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
            -TableInfo $mockTableInfo

        # Pending state = 3, Exclude state = 2
        $result | Should -Match 'SET \[State\] = 2'
        $result | Should -Match 'WHERE \[State\] = 3'
    }

    It 'Uses correct processing table' {
        $result = New-ExcludePendingQuery `
            -ProcessingTable 'SqlSizer.Custom_Table' `
            -TableInfo $mockTableInfo

        $result | Should -Match 'UPDATE SqlSizer\.Custom_Table'
    }

    It 'Includes GO statement' {
        $result = New-ExcludePendingQuery `
            -ProcessingTable 'SqlSizer.Processing_Orders' `
            -TableInfo $mockTableInfo

        $result | Should -Match 'GO'
    }

    It 'Includes descriptive comment' {
        $result = New-ExcludePendingQuery `
            -ProcessingTable 'SqlSizer.Processing_Orders' `
            -TableInfo $mockTableInfo

        $result | Should -Match '-- Mark remaining Pending as Exclude'
        $result | Should -Match 'dbo\.Orders'
    }
}

Describe 'New-CTETraversalQuery - Structure Tests' {
    BeforeAll {
        # Helper to create ColumnInfo objects
        function New-ColumnInfo([string]$Name, [string]$DataType) {
            $col = New-Object ColumnInfo
            $col.Name = $Name
            $col.DataType = $DataType
            return $col
        }

        # Helper to create TableInfo objects
        function New-MockTableInfo([string]$Schema, [string]$Table, [array]$PkColumns) {
            $t = New-Object TableInfo
            $t.SchemaName = $Schema
            $t.TableName = $Table
            $t.PrimaryKey = [System.Collections.Generic.List[ColumnInfo]]::new()
            foreach ($col in $PkColumns) {
                $t.PrimaryKey.Add($col)
            }
            return $t
        }

        # Create minimal mock objects for testing
        $mockSourceTable = New-MockTableInfo -Schema 'dbo' -Table 'Customers' -PkColumns @(
            (New-ColumnInfo 'CustomerID' 'int')
        )

        $mockTargetTable = New-MockTableInfo -Schema 'dbo' -Table 'Orders' -PkColumns @(
            (New-ColumnInfo 'OrderID' 'int')
        )

        # Helper to create TableFk objects
        function New-MockTableFk([string]$Name, [array]$FkColumns, [array]$Columns) {
            $fk = New-Object TableFk
            $fk.Name = $Name
            $fk.FkColumns = [System.Collections.Generic.List[ColumnInfo]]::new()
            foreach ($col in $FkColumns) { $fk.FkColumns.Add($col) }
            $fk.Columns = [System.Collections.Generic.List[ColumnInfo]]::new()
            foreach ($col in $Columns) { $fk.Columns.Add($col) }
            return $fk
        }

        $mockFk = New-MockTableFk -Name 'FK_Orders_Customers' `
            -FkColumns @((New-ColumnInfo 'CustomerID' 'int')) `
            -Columns @((New-ColumnInfo 'CustomerID' 'int'))

        # Create mock tables with multiple columns for dynamic key testing
        $mockSourceTableMultiKey = New-MockTableInfo -Schema 'dbo' -Table 'CompositeKeyTable' -PkColumns @(
            (New-ColumnInfo 'Key1' 'int'),
            (New-ColumnInfo 'Key2' 'varchar'),
            (New-ColumnInfo 'Key3' 'uniqueidentifier')
        )

        $mockTargetTableMultiKey = New-MockTableInfo -Schema 'dbo' -Table 'RelatedTable' -PkColumns @(
            (New-ColumnInfo 'RelatedKey1' 'int'),
            (New-ColumnInfo 'RelatedKey2' 'varchar')
        )

        $mockFkMultiColumn = New-MockTableFk -Name 'FK_Related_Composite' `
            -FkColumns @((New-ColumnInfo 'FkKey1' 'int'), (New-ColumnInfo 'FkKey2' 'varchar')) `
            -Columns @((New-ColumnInfo 'Key1' 'int'), (New-ColumnInfo 'Key2' 'varchar'))

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
            -FullSearch $false

        $result | Should -Match 'SourceRecords AS'
        $result | Should -Match 'SourceRecordCandidates AS'
        $result | Should -Match 'NewRecords AS'
    }

    It 'Scopes source records to the selected in-progress operation batch' {
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
            -MaxBatchSize 100 `
            -FullSearch $false

        $result | Should -Match 'ROW_NUMBER\(\) OVER'
        $result | Should -Match 'o\.\[Table\] = 1'
        $result | Should -Match 'o\.\[State\] = src\.\[State\]'
        $result | Should -Match 'o\.Depth = src\.Depth'
        $result | Should -Match 'o\.FoundIteration = src\.Iteration'
        $result | Should -Match 'o\.\[Source\] = src\.\[Source\]'
        $result | Should -Match 'o\.\[Fk\] = src\.\[Fk\]'
        $result | Should -Match 'src\.BatchRowNumber > ISNULL\(o\.ProcessedIteration, 0\)'
        $result | Should -Match 'src\.BatchRowNumber <= o\.Processed'
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
            -FullSearch $false

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
            -FullSearch $false

        $result | Should -Match 'INSERT INTO SqlSizer\.Operations'
    }

    It 'Queues promoted Pending rows as Include work' {
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
            -FullSearch $false

        $result | Should -Match 'OUTPUT inserted\.Depth INTO @InsertedRows'
        $result | Should -Match 'SET \[State\] = 1'
        $result | Should -Match 'Depth = nr\.Depth'
        $result | Should -Match 'Iteration = 5'
        $result | Should -Match 'src\.Depth \+ 1 AS Depth'
        $result | Should -Match 'WHERE existing\.\[State\] = 3'
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
            -FullSearch $false

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
            -FullSearch $false

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
            -FullSearch $false

        $result | Should -Match '-- Traverse INCOMING FK'
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
                -FullSearch $false

            # Should have Key0 in SourceRecords
            $result | Should -Match 'SELECT src\.Key0, src\.Depth, src\.Fk'
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
                -FullSearch $false

            # For outgoing, source columns = PK (3 columns), target columns = FK columns (2 columns)
            # SourceRecords should have Key0, Key1, Key2
            $result | Should -Match 'SELECT src\.Key0, src\.Key1, src\.Key2, src\.Depth, src\.Fk'
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
                -FullSearch $false

            # INSERT should only list Key0 (since FK has 1 column)
            $result | Should -Match 'INSERT INTO SqlSizer\.Proc_Target \(Key0, \[State\], Source, Depth, Fk, Iteration\)'
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
                -FullSearch $false

            # For outgoing: target columns = FK columns (2 columns)
            # INSERT should list Key0, Key1
            $result | Should -Match 'INSERT INTO SqlSizer\.Proc_Target \(Key0, Key1, \[State\], Source, Depth, Fk, Iteration\)'
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
                -FullSearch $false

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
                -FullSearch $false

            # For incoming: source columns = FK columns (2), target columns = target PK (2)
            # SourceRecords should have Key0, Key1
            $result | Should -Match 'SELECT src\.Key0, src\.Key1, src\.Depth, src\.Fk'
        }
    }
}
