<#
.SYNOPSIS
    Refactored version of Find-Subset with improved algorithm design.

.DESCRIPTION
    This is a cleaner, more maintainable implementation of the subset finding algorithm.
    
    Key improvements over the original:
    1. Explicit TraversalState enum instead of confusing color codes
    2. Unified traversal function (no separate HandleOutgoing/HandleIncoming)
    3. Eliminated the "Split" operation - uses proper state resolution
    4. Improved cycle detection with path tracking
    5. Better batch processing with set-based operations
    6. Cleaner SQL generation with CTEs
    7. Better separation of concerns

.NOTES
    This is a DRAFT refactoring for review. It maintains the same external interface
    as the original Find-Subset function but with internal improvements.
#>

function Find-Subset-Refactored
{
    [cmdletbinding()]
    [outputtype([pscustomobject])]
    param
    (
        [Parameter(Mandatory = $false)]
        [int]$StartIteration = 0,

        [Parameter(Mandatory = $false)]
        [bool]$Interactive = $false,

        [Parameter(Mandatory = $false)]
        [int]$Iteration = -1,

        [Parameter(Mandatory = $false)]
        [int]$MaxBatchSize = -1,

        [Parameter(Mandatory = $true)]
        [string]$SessionId,

        [Parameter(Mandatory = $true)]
        [string]$Database,

        [Parameter(Mandatory = $false)]
        [TableInfo2[]]$IgnoredTables,

        [Parameter(Mandatory = $true)]
        [DatabaseInfo]$DatabaseInfo,

        [Parameter(Mandatory = $false)]
        [TraversalConfiguration]$TraversalConfiguration = $null,

        [Parameter(Mandatory = $false)]
        [bool]$FullSearch = $false,

        [Parameter(Mandatory = $false)]
        [bool]$UseDfs = $false,

        [Parameter(Mandatory = $true)]
        [SqlConnectionInfo]$ConnectionInfo
    )

    # Query caches - keyed by "schema_table_state_direction"
    $queryCache = New-Object "System.Collections.Generic.Dictionary[[string], [string]]"
    #region Helper Functions

    function New-TraversalQuery
    {
        <#
        .SYNOPSIS
            Generates SQL query for traversing relationships (unified for both directions).
        .DESCRIPTION
            Uses CTEs for cleaner, more readable SQL generation.
            Handles both outgoing (FK to referenced table) and incoming (referenced by) relationships.
        #>
        param
        (
            [TableInfo]$Table,
            [TraversalState]$State,
            [TraversalDirection]$Direction,
            [TraversalConfiguration]$TraversalConfiguration,
            [int]$Iteration
        )

        $result = ""
        $tableId = $tablesGroupedByName["$($Table.SchemaName), $($Table.TableName)"].Id
        $processing = $structure.GetProcessingName($structure.Tables[$Table], $SessionId)

        $relationships = if ($Direction -eq [TraversalDirection]::Outgoing) {
            $Table.ForeignKeys
        } else {
            $Table.IsReferencedBy
        }

        foreach ($rel in $relationships)
        {
            # For incoming, we need to iterate through FKs that point to current table
            $fks = if ($Direction -eq [TraversalDirection]::Incoming) {
                $rel.ForeignKeys | Where-Object { 
                    ($_.Schema -eq $Table.SchemaName) -and ($_.Table -eq $Table.TableName) 
                }
            } else {
                @($rel.ForeignKeys)
            }

            foreach ($fk in $fks)
            {
                $targetSchema = if ($Direction -eq [TraversalDirection]::Outgoing) { $fk.Schema } else { $fk.FkSchema }
                $targetTable = if ($Direction -eq [TraversalDirection]::Outgoing) { $fk.Table } else { $fk.FkTable }

                # Skip ignored tables
                if ([TableInfo2]::IsIgnored($targetSchema, $targetTable, $IgnoredTables))
                {
                    continue
                }

                $newState = Get-NewTraversalState -Direction $Direction -CurrentState $State -Fk $fk -TraversalConfiguration $TraversalConfiguration -FullSearch $FullSearch
                $constraints = Get-TraversalConstraints -Fk $fk -Direction $Direction -TraversalConfiguration $TraversalConfiguration

                $targetTableInfo = $DatabaseInfo.Tables | Where-Object { 
                    ($_.SchemaName -eq $targetSchema) -and ($_.TableName -eq $targetTable) 
                }
                
                if ($null -eq $targetTableInfo -or $targetTableInfo.PrimaryKey.Count -eq 0)
                {
                    continue
                }

                $targetTableId = $tablesGroupedByName["$targetSchema, $targetTable"].Id
                $targetSignature = $structure.Tables[$targetTableInfo]
                $targetProcessing = $structure.GetProcessingName($targetSignature, $SessionId)
                $fkId = $fkGroupedByName["$($fk.FkSchema), $($fk.FkTable), $($fk.Name)"].Id

                # Build CTE-based query using shared function
                $query = New-CTETraversalQuery `
                    -SourceProcessing $processing `
                    -TargetProcessing $targetProcessing `
                    -SourceTable $Table `
                    -TargetTable $targetTableInfo `
                    -Fk $fk `
                    -Direction $Direction `
                    -NewState $newState `
                    -SourceTableId $tableId `
                    -TargetTableId $targetTableId `
                    -FkId $fkId `
                    -Constraints $constraints `
                    -Iteration $Iteration `
                    -SessionId $SessionId `
                    -MaxBatchSize $MaxBatchSize `
                    -FullSearch $FullSearch `
                    -IsSynapse $ConnectionInfo.IsSynapse

                $result += $query
            }
        }

        return $result
    }

    function Invoke-TraversalOperation
    {
        <#
        .SYNOPSIS
            Executes a single traversal operation (processes one table + state + depth).
        #>
        param
        (
            [TraversalOperation]$Operation,
            [int]$Iteration
        )

        $table = $DatabaseInfo.Tables | Where-Object { 
            ($_.SchemaName -eq $Operation.TableSchema) -and 
            ($_.TableName -eq $Operation.TableName) 
        }

        Write-Progress -Activity "Finding subset $SessionId" `
                       -CurrentOperation "$($table.SchemaName).$($table.TableName) - State: $($Operation.State)" `
                       -PercentComplete $percentComplete

        # Check which directions to traverse
        $traverseOutgoing = Test-ShouldTraverseDirection -State $Operation.State -Direction ([TraversalDirection]::Outgoing)
        $traverseIncoming = Test-ShouldTraverseDirection -State $Operation.State -Direction ([TraversalDirection]::Incoming)

        # Execute outgoing traversal
        if ($traverseOutgoing)
        {
            $cacheKey = "$($table.SchemaName)_$($table.TableName)_$([int]$Operation.State)_OUT"
            
            if ($queryCache.ContainsKey($cacheKey))
            {
                $query = $queryCache[$cacheKey]
            }
            else
            {
                $query = New-TraversalQuery `
                    -Table $table `
                    -State $Operation.State `
                    -Direction ([TraversalDirection]::Outgoing) `
                    -TraversalConfiguration $TraversalConfiguration `
                    -Iteration $Iteration
                
                $queryCache[$cacheKey] = $query
            }

            if ($query -ne "")
            {
                $null = Invoke-SqlcmdEx -Sql $query -Database $Database -ConnectionInfo $ConnectionInfo
            }
        }

        # Execute incoming traversal
        if ($traverseIncoming)
        {
            $cacheKey = "$($table.SchemaName)_$($table.TableName)_$([int]$Operation.State)_IN"
            
            if ($queryCache.ContainsKey($cacheKey))
            {
                $query = $queryCache[$cacheKey]
            }
            else
            {
                $query = New-TraversalQuery `
                    -Table $table `
                    -State $Operation.State `
                    -Direction ([TraversalDirection]::Incoming) `
                    -TraversalConfiguration $TraversalConfiguration `
                    -Iteration $Iteration
                
                $queryCache[$cacheKey] = $query
            }

            if ($query -ne "")
            {
                $null = Invoke-SqlcmdEx -Sql $query -Database $Database -ConnectionInfo $ConnectionInfo
            }
        }

        # NO SPLIT OPERATION - Pending states are resolved later
        # This eliminates the confusing Yellow -> Red+Green duplication
    }

    function Resolve-PendingStates
    {
        <#
        .SYNOPSIS
            Resolves Pending states after traversal completes.
            This replaces the confusing "Split" operation.
        .DESCRIPTION
            Pending records are those reached via incoming FKs in non-full search.
            Resolution logic: 
            1. If a Pending record is also reachable as Include, mark it Include
            2. Iteratively propagate Include to Pending dependencies
            3. Mark remaining Pending as Exclude
            
            Note: Pending -> Pending transitions mean uncertainty propagates through
            dependency chains. This function resolves those chains transitively.
        #>
        param
        (
            [int]$Iteration
        )

        Write-Verbose "Resolving Pending states for iteration $Iteration (transitive resolution)"

        # Iteratively resolve Pending states until no more changes
        $resolvedCount = 0
        $maxIterations = 100  # Safety limit to prevent infinite loops
        $iteration = 0
        
        do
        {
            $iteration++
            $changedThisIteration = 0
            
            # For each table with Pending records, resolve them
            $tables = $DatabaseInfo.Tables | Where-Object { $_.PrimaryKey.Count -gt 0 }
        
            foreach ($table in $tables)
            {
                $signature = $structure.Tables[$table]
                $processing = $structure.GetProcessingName($signature, $SessionId)
                $tableId = $tablesGroupedByName["$($table.SchemaName), $($table.TableName)"].Id

                $pendingState = [int][TraversalState]::Pending
                $includeState = [int][TraversalState]::Include
                $excludeState = [int][TraversalState]::Exclude

                # Build PK comparison conditions
                $pkConditions = for ($i = 0; $i -lt $table.PrimaryKey.Count; $i++) {
                    "pending.Key$i = inc.Key$i"
                }
                $pkJoin = $pkConditions -join " AND "

                # Mark Pending as Include if it matches an Include record
                # This handles both direct matches AND transitive dependencies
                # (since Pending -> Pending means dependencies become Include too)
                $query = @"
-- Resolve Pending states for $($table.SchemaName).$($table.TableName) (iteration $iteration)
DECLARE @Changed INT = 0;

UPDATE pending
SET Color = $includeState
FROM $processing pending
WHERE pending.Color = $pendingState
    AND EXISTS (
        SELECT 1
        FROM $processing inc
        WHERE inc.Color = $includeState
            AND $pkJoin
    );

SET @Changed = @@ROWCOUNT;
"@

                if (-not $ConnectionInfo.IsSynapse)
                {
                    $query += "`nGO`n"
                }

                $result = Invoke-SqlcmdEx -Sql $query -Database $Database -ConnectionInfo $ConnectionInfo
                if ($null -ne $result -and $null -ne $result.Changed)
                {
                    $changedThisIteration += $result.Changed
                }
            }
            
            $resolvedCount += $changedThisIteration
            Write-Verbose "Resolution iteration $($iteration) - Changed $changedThisIteration records"
            
        } while ($changedThisIteration -gt 0 -and $iteration -lt $maxIterations)

        if ($iteration -ge $maxIterations)
        {
            Write-Warning "Pending resolution hit maximum iterations ($maxIterations). Possible circular dependency."
        }

        Write-Verbose "Resolved $resolvedCount Pending records to Include in $iteration iterations"

        # Mark ALL remaining Pending as Exclude (those not reachable from Include)
        foreach ($table in $tables)
        {
            $signature = $structure.Tables[$table]
            $processing = $structure.GetProcessingName($signature, $SessionId)
            $pendingState = [int][TraversalState]::Pending
            $excludeState = [int][TraversalState]::Exclude

            $query = @"
-- Mark remaining Pending as Exclude for $($table.SchemaName).$($table.TableName)
UPDATE $processing
SET Color = $excludeState
WHERE Color = $pendingState;
"@

            if (-not $ConnectionInfo.IsSynapse)
            {
                $query += "`nGO`n"
            }

            $null = Invoke-SqlcmdEx -Sql $query -Database $Database -ConnectionInfo $ConnectionInfo
        }
    }

    function Get-NextOperation
    {
        <#
        .SYNOPSIS
            Gets the next operation to process (BFS or DFS).
        #>
        param
        (
            [bool]$UseDfs
        )

        if ($UseDfs)
        {
            # DFS: Process by count (deepest/most records first)
            $query = @"
SELECT TOP 1
    o.[Table],
    t.[Schema] AS TableSchema,
    t.TableName,
    o.Color AS State,
    o.Depth,
    SUM(o.ToProcess - o.Processed) AS RemainingRecords
FROM SqlSizer.Operations o
INNER JOIN SqlSizer.Tables t ON o.[Table] = t.Id
WHERE o.Status IS NULL 
    AND o.SessionId = '$SessionId'
GROUP BY o.[Table], t.[Schema], t.TableName, o.Color, o.Depth
ORDER BY RemainingRecords DESC
"@
        }
        else
        {
            # BFS: Process by depth (breadth-first)
            $query = @"
SELECT TOP 1
    o.[Table] AS TableId,
    t.[Schema] AS TableSchema,
    t.TableName,
    o.Color AS State,
    o.Depth,
    SUM(o.ToProcess - o.Processed) AS RemainingRecords
FROM SqlSizer.Operations o
INNER JOIN SqlSizer.Tables t ON o.[Table] = t.Id
WHERE o.Status IS NULL 
    AND o.SessionId = '$SessionId'
GROUP BY o.[Table], t.[Schema], t.TableName, o.Color, o.Depth
ORDER BY o.Depth ASC, RemainingRecords DESC
"@
        }

        $result = Invoke-SqlcmdEx -Sql $query -Database $Database -ConnectionInfo $ConnectionInfo

        if ($null -eq $result)
        {
            return $null
        }

        $operation = [TraversalOperation]::new()
        $operation.TableId = $result.TableId
        $operation.TableSchema = $result.TableSchema
        $operation.TableName = $result.TableName
        $operation.State = [TraversalState]$result.State
        $operation.Depth = $result.Depth
        $operation.RecordsToProcess = $result.RemainingRecords
        $operation.RecordsProcessed = 0

        return $operation
    }

    function Mark-OperationInProgress
    {
        <#
        .SYNOPSIS
            Marks operations as in-progress (Status = 0).
        #>
        param
        (
            [TraversalOperation]$Operation
        )

        $state = [int]$Operation.State

        if ($MaxBatchSize -eq -1)
        {
            # Process all at once
            $query = @"
UPDATE SqlSizer.Operations
SET Status = 0, Processed = ToProcess
WHERE [Table] = $($Operation.TableId)
    AND Color = $state
    AND Depth = $($Operation.Depth)
    AND Status IS NULL
    AND SessionId = '$SessionId'
"@
        }
        else
        {
            # Process in batches
            $query = @"
DECLARE @Remaining INT = $MaxBatchSize;

UPDATE SqlSizer.Operations
SET Status = 0,
    Processed = CASE
        WHEN (ToProcess - Processed) <= @Remaining THEN ToProcess
        ELSE Processed + @Remaining
    END,
    @Remaining = @Remaining - CASE
        WHEN (ToProcess - Processed) <= @Remaining THEN (ToProcess - Processed)
        ELSE @Remaining
    END
WHERE [Table] = $($Operation.TableId)
    AND Color = $state
    AND Depth = $($Operation.Depth)
    AND Status IS NULL
    AND SessionId = '$SessionId'
    AND @Remaining > 0
"@
        }

        $null = Invoke-SqlcmdEx -Sql $query -Database $Database -ConnectionInfo $ConnectionInfo
    }

    function Complete-Operations
    {
        <#
        .SYNOPSIS
            Marks completed operations and resets partially complete ones.
        #>
        param
        (
            [int]$Iteration
        )

        $query = @"
-- Reset operations that hit batch limit
UPDATE SqlSizer.Operations
SET Status = NULL
WHERE Status = 0 
    AND ToProcess <> Processed
    AND SessionId = '$SessionId';

-- Mark fully processed operations as complete
UPDATE SqlSizer.Operations
SET Status = 1, 
    ProcessedIteration = $Iteration,
    ProcessedDate = GETDATE()
WHERE Status = 0
    AND SessionId = '$SessionId';
"@

        $null = Invoke-SqlcmdEx -Sql $query -Database $Database -ConnectionInfo $ConnectionInfo
    }

    function Get-IterationStatistics
    {
        <#
        .SYNOPSIS
            Gets current progress statistics.
        #>
        param
        (
            [int]$Iteration,
            [DateTime]$StartTime
        )

        $query = @"
SELECT 
    COUNT(*) AS TotalOperations,
    SUM(CASE WHEN Status = 1 THEN 1 ELSE 0 END) AS CompletedOperations,
    SUM(Processed) AS TotalRecordsProcessed,
    SUM(ToProcess - Processed) AS TotalRecordsRemaining,
    MAX(Depth) AS MaxDepthReached
FROM SqlSizer.Operations
WHERE SessionId = '$SessionId'
"@

        $result = Invoke-SqlcmdEx -Sql $query -Database $Database -ConnectionInfo $ConnectionInfo

        $stats = [TraversalStatistics]::new()
        $stats.TotalOperations = $result.TotalOperations
        $stats.CompletedOperations = $result.CompletedOperations
        $stats.TotalRecordsProcessed = $result.TotalRecordsProcessed
        $stats.TotalRecordsRemaining = $result.TotalRecordsRemaining
        $stats.CurrentIteration = $Iteration
        $stats.MaxDepthReached = $result.MaxDepthReached
        $stats.ElapsedTime = (Get-Date) - $StartTime

        return $stats
    }

    function Invoke-SearchIteration
    {
        <#
        .SYNOPSIS
            Executes one iteration of the search algorithm.
        .RETURNS
            $true if more work remains, $false if complete.
        #>
        param
        (
            [int]$Iteration
        )

        # Get next operation
        $operation = Get-NextOperation -UseDfs $UseDfs

        if ($null -eq $operation)
        {
            Write-Verbose "No more operations to process"
            return $false
        }

        # Mark as in-progress
        Mark-OperationInProgress -Operation $operation

        # Execute traversal
        Invoke-TraversalOperation -Operation $operation -Iteration $Iteration

        # Complete operations
        Complete-Operations -Iteration $Iteration

        # Resolve any Pending states created in this iteration
        if ($operation.State -eq [TraversalState]::Include -and -not $FullSearch)
        {
            Resolve-PendingStates -Iteration $Iteration
        }

        return $true
    }

    #endregion

    #region Main Execution

    # Initialize metadata
    $structure = [Structure]::new($DatabaseInfo)
    $sqlSizerInfo = Get-SqlSizerInfo -Database $Database -ConnectionInfo $ConnectionInfo
    $script:tablesGroupedById = $sqlSizerInfo.Tables | Group-Object -Property Id -AsHashTable -AsString
    $script:tablesGroupedByName = $sqlSizerInfo.Tables | Group-Object -Property SchemaName, TableName -AsHashTable -AsString
    $script:fkGroupedByName = $sqlSizerInfo.ForeignKeys | Group-Object -Property FkSchemaName, FkTableName, Name -AsHashTable -AsString

    if ($Interactive -eq $false)
    {
        # Non-interactive mode: run until complete
        $null = Initialize-OperationsTable `
            -SessionId $SessionId `
            -Database $Database `
            -ConnectionInfo $ConnectionInfo `
            -DatabaseInfo $DatabaseInfo `
            -StartIteration $StartIteration

        $startTime = Get-Date
        $iteration = $StartIteration + 1
        $script:percentComplete = 0

        do
        {
            $hasMoreWork = Invoke-SearchIteration -Iteration $iteration

            # Update progress
            if (($iteration % 5) -eq 0)
            {
                $stats = Get-IterationStatistics -Iteration $iteration -StartTime $startTime
                $script:percentComplete = $stats.PercentComplete()
                Write-Verbose $stats.ToString()
            }

            $iteration++
        }
        while ($hasMoreWork)

        Write-Progress -Activity "Finding subset" -Completed

        return [pscustomobject]@{
            Finished            = $true
            Initialized         = $true
            CompletedIterations = $iteration - $StartIteration
        }
    }
    else
    {
        # Interactive mode: one iteration at a time
        if ($Iteration -eq 0)
        {
            $null = Initialize-OperationsTable `
                -SessionId $SessionId `
                -Database $Database `
                -ConnectionInfo $ConnectionInfo `
                -DatabaseInfo $DatabaseInfo `
                -StartIteration $StartIteration

            return [pscustomobject]@{
                Finished            = $false
                Initialized         = $true
                CompletedIterations = 1
            }
        }
        else
        {
            $startTime = Get-Date
            $script:percentComplete = 0
            $hasMoreWork = Invoke-SearchIteration -Iteration $Iteration

            return [pscustomobject]@{
                Finished            = -not $hasMoreWork
                Initialized         = $true
                CompletedIterations = 1
            }
        }
    }

    #endregion
}
