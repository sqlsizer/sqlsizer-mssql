<#
.SYNOPSIS
    SQL query building functions for Find-Subset traversal operations.
    
.DESCRIPTION
    This module contains testable functions for building SQL queries
    used in graph traversal operations. Separated for testability.
#>

function ConvertTo-SqlIdentifier
{
    [CmdletBinding()]
    [OutputType([string])]
    param
    (
        [Parameter(Mandatory = $true)]
        [string]$Name
    )

    return '[' + $Name.Replace(']', ']]') + ']'
}

function ConvertTo-SqlMultipartIdentifier
{
    [CmdletBinding()]
    [OutputType([string])]
    param
    (
        [Parameter(Mandatory = $true)]
        [string]$Name
    )

    return (($Name -split '\.') | ForEach-Object { ConvertTo-SqlIdentifier $_ }) -join '.'
}

function ConvertTo-SqlStringLiteral
{
    [CmdletBinding()]
    [OutputType([string])]
    param
    (
        [Parameter(Mandatory = $true)]
        [AllowEmptyString()]
        [string]$Value
    )

    return "'" + $Value.Replace("'", "''") + "'"
}

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
        [long]$SourceTableId,
        
        [Parameter(Mandatory = $true)]
        [long]$TargetTableId,
        
        [Parameter(Mandatory = $true)]
        [long]$FkId,
        
        [Parameter(Mandatory = $true)]
        [hashtable]$Constraints,
        
        [Parameter(Mandatory = $true)]
        [int]$Iteration,
        
        [Parameter(Mandatory = $true)]
        [string]$SessionId,
        
        [Parameter(Mandatory = $true)]
        [int]$MaxBatchSize,
        
        [Parameter(Mandatory = $true)]
        [bool]$FullSearch
    )

    $sourceProcessingSql = ConvertTo-SqlMultipartIdentifier $SourceProcessing
    $targetProcessingSql = ConvertTo-SqlMultipartIdentifier $TargetProcessing
    $sourceTableSql = (ConvertTo-SqlIdentifier $SourceTable.SchemaName) + "." + (ConvertTo-SqlIdentifier $SourceTable.TableName)
    $targetTableSql = (ConvertTo-SqlIdentifier $TargetTable.SchemaName) + "." + (ConvertTo-SqlIdentifier $TargetTable.TableName)
    $sessionIdLiteral = ConvertTo-SqlStringLiteral $SessionId

    # Build column mappings based on direction
    if ($Direction -eq [TraversalDirection]::Outgoing)
    {
        $sourceColumns = $SourceTable.PrimaryKey
        $targetColumns = $Fk.Columns  # Referenced columns (target's PK)
        
        # For OUTGOING: join through source table
        # SourceRecords (src) -> SourceTable (srcTable) on PK -> TargetTable (tgt) on FK->PK
        $srcTableJoinConditions = for ($i = 0; $i -lt $SourceTable.PrimaryKey.Count; $i++) {
            $col = $SourceTable.PrimaryKey[$i]
            "src.Key$i = srcTable.$(ConvertTo-SqlIdentifier $col.Name)"
        }
        $srcTableJoinClause = $srcTableJoinConditions -join " AND "
        
        $targetJoinConditions = for ($i = 0; $i -lt $Fk.FkColumns.Count; $i++) {
            "srcTable.$(ConvertTo-SqlIdentifier $Fk.FkColumns[$i].Name) = tgt.$(ConvertTo-SqlIdentifier $Fk.Columns[$i].Name)"
        }
        $targetJoinClause = $targetJoinConditions -join " AND "
        
        $fromClause = @"
FROM $targetTableSql tgt
    INNER JOIN $sourceTableSql srcTable ON $targetJoinClause
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
            "src.Key$i = tgt.$(ConvertTo-SqlIdentifier $Fk.FkColumns[$i].Name)"
        }
        $joinClause = $joinConditions -join " AND "
        
        $fromClause = @"
FROM $targetTableSql tgt
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

    # Build source key list for SourceRecords CTE
    $sourceKeyList = (0..($sourceColumns.Count - 1) | ForEach-Object { "Key$_" }) -join ", "
    $sourceKeyListFromSrc = (0..($sourceColumns.Count - 1) | ForEach-Object { "src.Key$_" }) -join ", "
    $sourceKeyListFromSrcRows = (0..($sourceColumns.Count - 1) | ForEach-Object { "srcRows.Key$_" }) -join ", "
    
    # Build target key list for INSERT
    $targetKeyListForInsert = (0..($targetColumns.Count - 1) | ForEach-Object { "Key$_" }) -join ", "

    # MaxBatchSize limits source rows via the operation row-number window below.
    # TOP is reserved for table-specific traversal constraints to avoid dropping
    # dependent rows found from the selected source batch.
    $topClause = Get-TopClause -MaxBatchSize -1 -Constraints $Constraints
    $orderByClause = if ($topClause -ne "") {
        "ORDER BY " + ((0..($targetColumns.Count - 1) | ForEach-Object { "Key$_ ASC" }) -join ", ")
    } else {
        ""
    }

    $sourceBatchJoinConditions = @(
        "o.[Table] = $SourceTableId",
        "o.[State] = src.[State]",
        "o.Depth = src.Depth",
        "o.FoundIteration = src.Iteration",
        "((o.[Source] = src.[Source]) OR (o.[Source] IS NULL AND src.[Source] IS NULL))",
        "((o.[Fk] = src.[Fk]) OR (o.[Fk] IS NULL AND src.[Fk] IS NULL))",
        "o.Status = 0",
        "o.SessionId = $sessionIdLiteral"
    )
    $sourceBatchJoinClause = $sourceBatchJoinConditions -join "`n        AND "
    $sourceBatchWindowClause = "src.BatchRowNumber > ISNULL(src.ProcessedIteration, 0)`n        AND src.BatchRowNumber <= src.Processed"
    $sourceBatchWindowClauseForUpdate = "srcRows.BatchRowNumber > ISNULL(srcRows.ProcessedIteration, 0)`n        AND srcRows.BatchRowNumber <= srcRows.Processed"

    $sourceRecordsForUpdate = @"
(
    SELECT $sourceKeyListFromSrcRows, srcRows.Depth, srcRows.Fk
    FROM (
        SELECT $sourceKeyListFromSrc, src.Depth, src.Fk,
            o.Id AS OperationId,
            o.ProcessedIteration,
            o.Processed,
            ROW_NUMBER() OVER (
                PARTITION BY o.Id
                ORDER BY src.Id
            ) AS BatchRowNumber
        FROM $sourceProcessingSql src
        INNER JOIN SqlSizer.Operations o ON $sourceBatchJoinClause
    ) srcRows
    WHERE $sourceBatchWindowClauseForUpdate
) src
"@

    if ($Direction -eq [TraversalDirection]::Outgoing)
    {
        $fromClauseForUpdate = @"
FROM $targetTableSql tgt
    INNER JOIN $sourceTableSql srcTable ON $targetJoinClause
    INNER JOIN $sourceRecordsForUpdate ON $srcTableJoinClause
WHERE 1 = 1
"@
    }
    else
    {
        $fromClauseForUpdate = @"
FROM $targetTableSql tgt
    INNER JOIN $sourceRecordsForUpdate ON $joinClause
WHERE 1 = 1
"@
    }

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

WITH SourceRecordCandidates AS (
    SELECT $sourceKeyListFromSrc, src.Depth, src.Fk,
        o.Id AS OperationId,
        o.ProcessedIteration,
        o.Processed,
        ROW_NUMBER() OVER (
            PARTITION BY o.Id
            ORDER BY src.Id
        ) AS BatchRowNumber
    FROM $sourceProcessingSql src
    INNER JOIN SqlSizer.Operations o ON $sourceBatchJoinClause
),
SourceRecords AS (
    SELECT $sourceKeyListFromSrc, src.Depth, src.Fk
    FROM SourceRecordCandidates src
    WHERE $sourceBatchWindowClause
),
NewRecords AS (
    SELECT DISTINCT $topClause
        $targetKeyList,
        src.Depth + 1 AS Depth
    $fromClause
    WHERE tgt.$(ConvertTo-SqlIdentifier $targetColumns[0].Name) IS NOT NULL
        $whereClause
        AND NOT EXISTS (
            SELECT 1 
            FROM $targetProcessingSql existing
            WHERE $notExistsClause
        )
    $orderByClause
)
INSERT INTO $targetProcessingSql ($targetKeyListForInsert, [State], Source, Depth, Fk, Iteration)
OUTPUT inserted.Depth INTO @InsertedRows
SELECT $targetKeyListForInsert, $([int]$NewState), $SourceTableId, Depth, $FkId, $Iteration
FROM NewRecords;

-- Promote existing records when a stronger include path finds them
$(if (($NewState -eq [TraversalState]::Include) -or ($NewState -eq [TraversalState]::IncludeFull)) {
    $eligibleStates = if ($NewState -eq [TraversalState]::IncludeFull) {
        "$([int][TraversalState]::Pending), $([int][TraversalState]::Include)"
    } else {
        "$([int][TraversalState]::Pending)"
    }
@"
UPDATE existing
SET [State] = $([int]$NewState),
    Source = $SourceTableId,
    Fk = $FkId,
    Depth = nr.Depth,
    Iteration = $Iteration
OUTPUT inserted.Depth INTO @InsertedRows
FROM $targetProcessingSql existing
INNER JOIN (
    SELECT DISTINCT
        $targetKeyList,
        src.Depth + 1 AS Depth
    $fromClauseForUpdate
        AND tgt.$(ConvertTo-SqlIdentifier $targetColumns[0].Name) IS NOT NULL
        $whereClause
) nr ON $updateKeyClause
WHERE existing.[State] IN ($eligibleStates);
"@
} else { "" })

-- Update operations table
INSERT INTO SqlSizer.Operations (
    [Table], [State], ToProcess, Processed, Status, Source, Fk, Depth,
    Created, ProcessedDate, SessionId, FoundIteration, ProcessedIteration
)
SELECT
    $TargetTableId,
    $([int]$NewState),
    COUNT_BIG(*),
    0,
    NULL,
    $SourceTableId,
    $FkId,
    Depth,
    GETDATE(),
    NULL, 
    $sessionIdLiteral,
    $Iteration, 
    NULL
FROM @InsertedRows
GROUP BY Depth;

GO

"@

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
        [object]$TableInfo
    )

    $pendingState = [int][TraversalState]::Pending
    $excludeState = [int][TraversalState]::Exclude
    $processingTableSql = ConvertTo-SqlMultipartIdentifier $ProcessingTable

    $query = @"
-- Mark remaining Pending as Exclude for $($TableInfo.SchemaName).$($TableInfo.TableName)
DECLARE @ExcludedCount INT = 0;
UPDATE $processingTableSql
SET [State] = $excludeState
WHERE [State] = $pendingState;
SET @ExcludedCount = @@ROWCOUNT;
SELECT @ExcludedCount AS ExcludedCount;

GO

"@

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

    $sessionIdLiteral = ConvertTo-SqlStringLiteral $SessionId

    if ($UseDfs)
    {
        # Preserve legacy UseDfs behavior: process the largest remaining operation first.
        return @"
SELECT TOP 1
    o.[Table] AS TableId,
    t.[Schema] AS TableSchema,
    t.TableName,
    o.[State] AS State,
    o.Depth,
    SUM(o.ToProcess - o.Processed) AS RemainingRecords
FROM SqlSizer.Operations o
INNER JOIN SqlSizer.Tables t ON o.[Table] = t.Id
WHERE o.Status IS NULL 
    AND o.SessionId = $sessionIdLiteral
GROUP BY o.[Table], t.[Schema], t.TableName, o.[State], o.Depth
ORDER BY RemainingRecords DESC
"@
    }
    else
    {
        # BFS: Process by depth (breadth-first)
        return @"
SELECT TOP 1
    o.[Table] AS TableId,
    t.[Schema] AS TableSchema,
    t.TableName,
    o.[State] AS State,
    o.Depth,
    SUM(o.ToProcess - o.Processed) AS RemainingRecords
FROM SqlSizer.Operations o
INNER JOIN SqlSizer.Tables t ON o.[Table] = t.Id
WHERE o.Status IS NULL 
    AND o.SessionId = $sessionIdLiteral
GROUP BY o.[Table], t.[Schema], t.TableName, o.[State], o.Depth
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
        [long]$TableId,
        
        [Parameter(Mandatory = $true)]
        [int]$State,
        
        [Parameter(Mandatory = $true)]
        [int]$Depth,
        
        [Parameter(Mandatory = $true)]
        [string]$SessionId,
        
        [Parameter(Mandatory = $true)]
        [int]$MaxBatchSize
    )

    $sessionIdLiteral = ConvertTo-SqlStringLiteral $SessionId

    if ($MaxBatchSize -eq -1)
    {
        # Process all at once
        return @"
UPDATE SqlSizer.Operations
SET Status = 0, ProcessedIteration = Processed, Processed = ToProcess
WHERE [Table] = $TableId
    AND [State] = $State
    AND Depth = $Depth
    AND Status IS NULL
    AND SessionId = $sessionIdLiteral
"@
    }
    else
    {
        # Process in batches - must separate SELECT and UPDATE since SQL Server
        # doesn't allow mixing column updates with variable assignment in SET clause
        return @"
DECLARE @Remaining bigint = $MaxBatchSize;
DECLARE @ProcessThisRow bigint;
DECLARE @OperationId bigint;

WHILE @Remaining > 0
BEGIN
    SET @OperationId = NULL;
    SET @ProcessThisRow = NULL;

    -- Calculate how much to process from the next available row
    SELECT TOP 1
        @OperationId = Id,
        @ProcessThisRow =
        CASE WHEN (ToProcess - Processed) <= @Remaining 
             THEN (ToProcess - Processed) 
             ELSE @Remaining 
        END
    FROM SqlSizer.Operations
    WHERE [Table] = $TableId
        AND [State] = $State
        AND Depth = $Depth
        AND Status IS NULL
        AND SessionId = $sessionIdLiteral
        AND (ToProcess - Processed) > 0
    ORDER BY Id;
    
    IF @OperationId IS NULL OR @ProcessThisRow IS NULL OR @ProcessThisRow = 0
        BREAK;
    
    -- Update exactly the selected row
    UPDATE SqlSizer.Operations
    SET Status = 0,
        ProcessedIteration = Processed,
        Processed = Processed + @ProcessThisRow
    WHERE Id = @OperationId;
    
    IF @@ROWCOUNT = 0
        BREAK;
    
    SET @Remaining = @Remaining - @ProcessThisRow;
END
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

    $sessionIdLiteral = ConvertTo-SqlStringLiteral $SessionId

    return @"
-- Reset operations that hit batch limit
UPDATE SqlSizer.Operations
SET Status = NULL,
    ProcessedIteration = NULL
WHERE Status = 0 
    AND ToProcess <> Processed
    AND SessionId = $sessionIdLiteral;

-- Mark fully processed operations as complete
UPDATE SqlSizer.Operations
SET Status = 1, 
    ProcessedIteration = $Iteration,
    ProcessedDate = GETDATE()
WHERE Status = 0
    AND SessionId = $sessionIdLiteral;
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

    $sessionIdLiteral = ConvertTo-SqlStringLiteral $SessionId

    return @"
SELECT 
    COUNT_BIG(*) AS TotalOperations,
    SUM(CASE WHEN Status = 1 THEN 1 ELSE 0 END) AS CompletedOperations,
    SUM(Processed) AS TotalRecordsProcessed,
    SUM(ToProcess - Processed) AS TotalRecordsRemaining,
    MAX(Depth) AS MaxDepthReached
FROM SqlSizer.Operations
WHERE SessionId = $sessionIdLiteral
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
