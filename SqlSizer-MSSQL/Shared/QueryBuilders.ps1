<#
.SYNOPSIS
    SQL query building functions for Find-Subset traversal operations.
    
.DESCRIPTION
    This module contains testable functions for building SQL queries
    used in graph traversal operations. Separated for testability.
#>

function New-CTETraversalQuery
{
    <#
    .SYNOPSIS
        Builds a CTE-based traversal query.
    .DESCRIPTION
        Generates SQL with CTEs for cleaner, more maintainable queries.
        This is a complex but testable function.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param
    (
        [Parameter(Mandatory = $true)]
        [string]$SourceProcessing,
        
        [Parameter(Mandatory = $true)]
        [string]$TargetProcessing,
        
        [Parameter(Mandatory = $true)]
        [TableInfo]$SourceTable,
        
        [Parameter(Mandatory = $true)]
        [TableInfo]$TargetTable,
        
        [Parameter(Mandatory = $true)]
        [TableFk]$Fk,
        
        [Parameter(Mandatory = $true)]
        [TraversalDirection]$Direction,
        
        [Parameter(Mandatory = $true)]
        [TraversalState]$NewState,
        
        [Parameter(Mandatory = $true)]
        [int]$SourceTableId,
        
        [Parameter(Mandatory = $true)]
        [int]$TargetTableId,
        
        [Parameter(Mandatory = $true)]
        [int]$FkId,
        
        [Parameter(Mandatory = $true)]
        [hashtable]$Constraints,
        
        [Parameter(Mandatory = $true)]
        [int]$Iteration,
        
        [Parameter(Mandatory = $true)]
        [string]$SessionId,
        
        [Parameter(Mandatory = $true)]
        [int]$MaxBatchSize,
        
        [Parameter(Mandatory = $true)]
        [bool]$FullSearch,
        
        [Parameter(Mandatory = $true)]
        [bool]$IsSynapse
    )

    # Build column mappings based on direction
    if ($Direction -eq [TraversalDirection]::Outgoing)
    {
        $sourceColumns = $SourceTable.PrimaryKey
        $targetColumns = $Fk.Columns  # Referenced columns (target's PK)
        
        # For OUTGOING: join through source table
        # SourceRecords (src) -> SourceTable (srcTable) on PK -> TargetTable (tgt) on FK->PK
        $srcTableJoinConditions = for ($i = 0; $i -lt $SourceTable.PrimaryKey.Count; $i++) {
            $col = $SourceTable.PrimaryKey[$i]
            "src.Key$i = srcTable.$($col.Name)"
        }
        $srcTableJoinClause = $srcTableJoinConditions -join " AND "
        
        $targetJoinConditions = for ($i = 0; $i -lt $Fk.FkColumns.Count; $i++) {
            "srcTable.$($Fk.FkColumns[$i].Name) = tgt.$($Fk.Columns[$i].Name)"
        }
        $targetJoinClause = $targetJoinConditions -join " AND "
        
        $fromClause = @"
FROM $($TargetTable.SchemaName).$($TargetTable.TableName) tgt
    INNER JOIN $($SourceTable.SchemaName).$($SourceTable.TableName) srcTable ON $targetJoinClause
    INNER JOIN SourceRecords src ON $srcTableJoinClause
"@
    }
    else # Incoming
    {
        $sourceColumns = $Fk.Columns  # Referenced columns (source's PK that FK points to)
        $targetColumns = $TargetTable.PrimaryKey
        
        # For INCOMING: direct join from SourceRecords to TargetTable
        # SourceRecords has PK of FK target, join to TargetTable (FK source) on FK columns
        $joinConditions = for ($i = 0; $i -lt $Fk.FkColumns.Count; $i++) {
            "src.Key$i = tgt.$($Fk.FkColumns[$i].Name)"
        }
        $joinClause = $joinConditions -join " AND "
        
        $fromClause = @"
FROM $($TargetTable.SchemaName).$($TargetTable.TableName) tgt
    INNER JOIN SourceRecords src ON $joinClause
"@
    }

    # Build select list for target keys
    $targetKeySelect = for ($i = 0; $i -lt $targetColumns.Count; $i++) {
        $col = $targetColumns[$i]
        (Get-ColumnValue -ColumnName $col.Name -Prefix "tgt." -DataType $col.DataType) + " AS Key$i"
    }
    $targetKeyList = $targetKeySelect -join ", "

    # Build NOT EXISTS check
    $notExistsConditions = for ($i = 0; $i -lt $targetColumns.Count; $i++) {
        $col = $targetColumns[$i]
        "existing.Key$i = " + (Get-ColumnValue -ColumnName $col.Name -Prefix "tgt." -DataType $col.DataType)
    }
    $notExistsClause = $notExistsConditions -join " AND "

    # Get additional WHERE conditions
    $additionalConditions = Get-AdditionalWhereConditions `
        -Constraints $Constraints `
        -FkId $FkId `
        -FullSearch $FullSearch

    $whereClause = if ($additionalConditions.Count -gt 0) {
        "AND " + ($additionalConditions -join " AND ")
    } else {
        ""
    }

    # Get TOP clause
    $topClause = Get-TopClause -MaxBatchSize $MaxBatchSize -Constraints $Constraints

    # Build source key list for SourceRecords CTE
    $sourceKeyList = (0..($sourceColumns.Count - 1) | ForEach-Object { "Key$_" }) -join ", "
    
    # Build target key list for INSERT
    $targetKeyListForInsert = (0..($targetColumns.Count - 1) | ForEach-Object { "Key$_" }) -join ", "

    # Build the query
    $directionLabel = if ($Direction -eq [TraversalDirection]::Outgoing) { 'OUTGOING' } else { 'INCOMING' }
    
    # Build conditions for updating existing Pending records to Include
    $updateKeyConditions = for ($i = 0; $i -lt $targetColumns.Count; $i++) {
        "existing.Key$i = nr.Key$i"
    }
    $updateKeyClause = $updateKeyConditions -join " AND "
    
    $query = @"
-- Traverse $directionLabel FK: $($Fk.Name)
DECLARE @InsertedRows TABLE (Depth INT);

WITH SourceRecords AS (
    SELECT $sourceKeyList, Depth, Fk
    FROM $SourceProcessing src
    WHERE src.Iteration IN (
        SELECT FoundIteration 
        FROM SqlSizer.Operations 
        WHERE Status = 0 AND SessionId = '$SessionId'
    )
),
NewRecords AS (
    SELECT DISTINCT $topClause
        $targetKeyList,
        src.Depth + 1 AS Depth
    $fromClause
    WHERE tgt.$($targetColumns[0].Name) IS NOT NULL
        $whereClause
        AND NOT EXISTS (
            SELECT 1 
            FROM $TargetProcessing existing 
            WHERE $notExistsClause
        )
)
INSERT INTO $TargetProcessing ($targetKeyListForInsert, Color, Source, Depth, Fk, Iteration)
OUTPUT inserted.Depth INTO @InsertedRows
SELECT $targetKeyListForInsert, $([int]$NewState), $SourceTableId, Depth, $FkId, $Iteration
FROM NewRecords;

-- Promote existing Pending records to Include if we found them via Include path
-- This handles the case where a record was first discovered as Pending, then later as Include
$(if ($NewState -eq [TraversalState]::Include) {
@"
UPDATE existing
SET Color = $([int][TraversalState]::Include)
FROM $TargetProcessing existing
WHERE existing.Color = $([int][TraversalState]::Pending)
    AND EXISTS (
        SELECT 1 FROM (
            SELECT DISTINCT $targetKeyList
            $fromClause
            WHERE tgt.$($targetColumns[0].Name) IS NOT NULL
                $whereClause
        ) nr
        WHERE $updateKeyClause
    );
"@
} else { "" })

-- Update operations table
INSERT INTO SqlSizer.Operations (
    [Table], Color, ToProcess, Processed, Status, Source, Fk, Depth, 
    Created, ProcessedDate, SessionId, FoundIteration, ProcessedIteration
)
SELECT 
    $TargetTableId, 
    $([int]$NewState), 
    COUNT(*), 
    0, 
    NULL, 
    $SourceTableId, 
    $FkId, 
    Depth, 
    GETDATE(), 
    NULL, 
    '$SessionId', 
    $Iteration, 
    NULL
FROM @InsertedRows
GROUP BY Depth;

"@

    if (-not $IsSynapse)
    {
        $query += "`nGO`n"
    }

    return $query
}

function New-ExcludePendingQuery
{
    <#
    .SYNOPSIS
        Builds query to mark remaining Pending as Exclude.
    .DESCRIPTION
        Pure function that generates SQL for marking all Pending
        records as Exclude after resolution attempts.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param
    (
        [Parameter(Mandatory = $true)]
        [string]$ProcessingTable,
        
        [Parameter(Mandatory = $true)]
        [TableInfo]$TableInfo,
        
        [Parameter(Mandatory = $true)]
        [bool]$IsSynapse
    )

    $pendingState = [int][TraversalState]::Pending
    $excludeState = [int][TraversalState]::Exclude

    $query = @"
-- Mark remaining Pending as Exclude for $($TableInfo.SchemaName).$($TableInfo.TableName)
UPDATE $ProcessingTable
SET Color = $excludeState
WHERE Color = $pendingState;
"@

    if (-not $IsSynapse)
    {
        $query += "`nGO`n"
    }

    return $query
}

function New-GetNextOperationQuery
{
    <#
    .SYNOPSIS
        Builds query to get the next operation to process.
    .DESCRIPTION
        Pure function that generates SQL for BFS or DFS order.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param
    (
        [Parameter(Mandatory = $true)]
        [string]$SessionId,
        
        [Parameter(Mandatory = $true)]
        [bool]$UseDfs
    )

    if ($UseDfs)
    {
        # DFS: Process by count (deepest/most records first)
        return @"
SELECT TOP 1
    o.[Table] AS TableId,
    t.SchemaName AS TableSchema,
    t.TableName,
    o.Color AS State,
    o.Depth,
    SUM(o.ToProcess - o.Processed) AS RemainingRecords
FROM SqlSizer.Operations o
INNER JOIN SqlSizer.Tables t ON o.[Table] = t.Id
WHERE o.Status IS NULL 
    AND o.SessionId = '$SessionId'
GROUP BY o.[Table], t.SchemaName, t.TableName, o.Color, o.Depth
ORDER BY RemainingRecords DESC
"@
    }
    else
    {
        # BFS: Process by depth (breadth-first)
        return @"
SELECT TOP 1
    o.[Table] AS TableId,
    t.SchemaName AS TableSchema,
    t.TableName,
    o.Color AS State,
    o.Depth,
    SUM(o.ToProcess - o.Processed) AS RemainingRecords
FROM SqlSizer.Operations o
INNER JOIN SqlSizer.Tables t ON o.[Table] = t.Id
WHERE o.Status IS NULL 
    AND o.SessionId = '$SessionId'
GROUP BY o.[Table], t.SchemaName, t.TableName, o.Color, o.Depth
ORDER BY o.Depth ASC, RemainingRecords DESC
"@
    }
}

function New-MarkOperationInProgressQuery
{
    <#
    .SYNOPSIS
        Builds query to mark operations as in-progress.
    .DESCRIPTION
        Pure function that generates SQL for marking operations
        with Status = 0 (in progress).
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param
    (
        [Parameter(Mandatory = $true)]
        [int]$TableId,
        
        [Parameter(Mandatory = $true)]
        [int]$State,
        
        [Parameter(Mandatory = $true)]
        [int]$Depth,
        
        [Parameter(Mandatory = $true)]
        [string]$SessionId,
        
        [Parameter(Mandatory = $true)]
        [int]$MaxBatchSize
    )

    if ($MaxBatchSize -eq -1)
    {
        # Process all at once
        return @"
UPDATE SqlSizer.Operations
SET Status = 0, Processed = ToProcess
WHERE [Table] = $TableId
    AND Color = $State
    AND Depth = $Depth
    AND Status IS NULL
    AND SessionId = '$SessionId'
"@
    }
    else
    {
        # Process in batches
        return @"
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
WHERE [Table] = $TableId
    AND Color = $State
    AND Depth = $Depth
    AND Status IS NULL
    AND SessionId = '$SessionId'
    AND @Remaining > 0
"@
    }
}

function New-CompleteOperationsQuery
{
    <#
    .SYNOPSIS
        Builds query to complete operations.
    .DESCRIPTION
        Pure function that generates SQL for marking completed
        operations and resetting partial ones.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param
    (
        [Parameter(Mandatory = $true)]
        [string]$SessionId,
        
        [Parameter(Mandatory = $true)]
        [int]$Iteration
    )

    return @"
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
}

function New-GetIterationStatisticsQuery
{
    <#
    .SYNOPSIS
        Builds query to get iteration statistics.
    .DESCRIPTION
        Pure function that generates SQL for retrieving progress stats.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param
    (
        [Parameter(Mandatory = $true)]
        [string]$SessionId
    )

    return @"
SELECT 
    COUNT(*) AS TotalOperations,
    SUM(CASE WHEN Status = 1 THEN 1 ELSE 0 END) AS CompletedOperations,
    SUM(Processed) AS TotalRecordsProcessed,
    SUM(ToProcess - Processed) AS TotalRecordsRemaining,
    MAX(Depth) AS MaxDepthReached
FROM SqlSizer.Operations
WHERE SessionId = '$SessionId'
"@
}

Export-ModuleMember -Function @(
    'New-CTETraversalQuery',
    'New-ExcludePendingQuery',
    'New-GetNextOperationQuery',
    'New-MarkOperationInProgressQuery',
    'New-CompleteOperationsQuery',
    'New-GetIterationStatisticsQuery'
)
