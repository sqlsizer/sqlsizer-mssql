<#
.SYNOPSIS
    Finds the subset of rows that must be removed before target rows can be deleted.

.DESCRIPTION
    Traverses incoming foreign key relationships to identify all rows that reference
    the target rows. These dependent rows must be removed first to maintain
    referential integrity during deletion.
    
    Algorithm features:
    1. Unified traversal query generation
    2. CTE-based SQL queries for readability and performance
    3. Batch processing for large datasets
    4. Proper separation of concerns
    5. Progress tracking with statistics
    6. Efficient operation selection strategy
    7. Enhanced error handling

.PARAMETER SessionId
    Unique identifier for this removal subset operation.

.PARAMETER Database
    The database to analyze.

.PARAMETER DatabaseInfo
    Metadata about the database structure.

.PARAMETER ConnectionInfo
    SQL connection details.

.PARAMETER StartIteration
    Starting iteration number (default: 0).

.PARAMETER Interactive
    If true, runs one iteration at a time (default: false).

.PARAMETER Iteration
    Specific iteration to run in interactive mode.

.PARAMETER MaxBatchSize
    Maximum number of rows to process per batch (default: -1 = unlimited).

.EXAMPLE
    Find-RemovalSubset -SessionId "session1" -Database "MyDB" `
        -DatabaseInfo $dbInfo -ConnectionInfo $connInfo

.NOTES
    Initialize the start set using Initialize-StartSet before calling this function.
    This function traverses INCOMING foreign keys to find rows that reference
    the target rows and must be removed first to maintain referential integrity.
#>

function Find-RemovalSubset
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

        [Parameter(Mandatory = $true)]
        [DatabaseInfo]$DatabaseInfo,

        [Parameter(Mandatory = $true)]
        [SqlConnectionInfo]$ConnectionInfo
    )

    # Query cache for FK traversal patterns - keyed by "fkSchema_fkTable_tableSchema_table"
    $incomingQueryCache = New-Object "System.Collections.Generic.Dictionary[[string], [string]]"
    
    # Metadata
    $structure = [Structure]::new($DatabaseInfo)
    $sqlSizerInfo = Get-SqlSizerInfo -Database $Database -ConnectionInfo $ConnectionInfo
    $tablesById = $sqlSizerInfo.Tables | Group-Object -Property Id -AsHashTable -AsString
    $tablesByName = $sqlSizerInfo.Tables | Group-Object -Property SchemaName, TableName -AsHashTable -AsString
    $fksByName = $sqlSizerInfo.ForeignKeys | Group-Object -Property FkSchemaName, FkTableName, Name -AsHashTable -AsString
    $ignoredTables = @()
    
    # O(1) table lookup hashtable for DatabaseInfo.Tables (optimization)
    $tablesByFullName = @{}
    foreach ($t in $DatabaseInfo.Tables) {
        $tablesByFullName["$($t.SchemaName), $($t.TableName)"] = $t
    }

    #region Helper Functions

    function Build-IncomingTraversalQuery
    {
        <#
        .SYNOPSIS
            Builds a CTE-based query for traversing incoming foreign keys.
        #>
        param
        (
            [TableInfo]$Table,
            [int]$Color,
            [TableInfo]$ReferencedByTable,
            [TableFk]$Fk,
            [int]$Depth,
            [int]$Iteration
        )

        $tableId = $tablesByName[$Table.SchemaName + ", " + $Table.TableName].Id
        # O(1) lookup using hashtable instead of Where-Object
        $fkTable = $tablesByFullName["$($Fk.FkSchema), $($Fk.FkTable)"]
        $fkTableId = $tablesByName[$Fk.FkSchema + ", " + $Fk.FkTable].Id
        $fkId = $fksByName[$Fk.FkSchema + ", " + $Fk.FkTable + ", " + $Fk.Name].Id
        $fkSignature = $structure.Tables[$fkTable]
        $fkProcessing = $structure.GetProcessingName($fkSignature, $SessionId)
        $processing = $structure.GetProcessingName($structure.Tables[$Table], $SessionId)
        $primaryKey = $ReferencedByTable.PrimaryKey

        if (($null -eq $primaryKey) -or ($primaryKey.Count -eq 0))
        {
            return $null
        }

        # Build CTE for source records
        $sourceColumns = @()
        for ($srcIdx = 0; $srcIdx -lt $primaryKey.Count; $srcIdx++)
        {
            $sourceColumns += "s.Key$srcIdx"
        }

        # Build JOIN condition between FK table and source
        $joinConditions = @()
        for ($joinIdx = 0; $joinIdx -lt $Fk.FkColumns.Count; $joinIdx++)
        {
            $joinConditions += "f.$($Fk.FkColumns[$joinIdx].Name) = s.Key$joinIdx"
        }

        # Build columns for result
        $selectColumns = @()
        for ($selIdx = 0; $selIdx -lt $primaryKey.Count; $selIdx++)
        {
            $columnValue = Get-ColumnValue `
                -ColumnName $primaryKey[$selIdx].Name `
                -Prefix "f." `
                -dataType $primaryKey[$selIdx].dataType
            $selectColumns += "$columnValue AS Key$selIdx"
        }

        # Build TOP clause
        $topClause = ""
        if ($MaxBatchSize -ne -1)
        {
            $topClause = "TOP ($MaxBatchSize)"
        }

        # Build primary key join conditions for NOT EXISTS clause
        $pkJoinConditions = @()
        for ($pkIdx = 0; $pkIdx -lt $primaryKey.Count; $pkIdx++)
        {
            $pkJoinConditions += "p.Key$pkIdx = f.$($primaryKey[$pkIdx].Name)"
        }
        $pkJoinCondition = $pkJoinConditions -join ' AND '

        # Generate CTE-based query
        $query = @"
-- Find incoming references from $($Fk.FkSchema).$($Fk.FkTable) to $($Table.SchemaName).$($Table.TableName)
WITH SourceRecords AS (
    SELECT $($sourceColumns -join ', ')
    FROM $processing
    WHERE Depth = $Depth
),
NewRecords AS (
    SELECT $topClause
        $($selectColumns -join ",`n        "),
        $Color AS Color,
        $tableId AS TableId,
        $($Depth + 1) AS Depth,
        $fkId AS FkId,
        $Iteration AS Iteration
    FROM $($ReferencedByTable.SchemaName).$($ReferencedByTable.TableName) f
    INNER JOIN SourceRecords s ON $($joinConditions -join ' AND ')
    WHERE NOT EXISTS (
        SELECT 1 
        FROM $fkProcessing p 
        WHERE $pkJoinCondition
    )
)
INSERT INTO $fkProcessing ($(0..($primaryKey.Count - 1) | ForEach-Object { "Key$_" } | Join-String -Separator ', '), Color, TableId, Depth, FkId, Iteration)
SELECT $(0..($primaryKey.Count - 1) | ForEach-Object { "Key$_" } | Join-String -Separator ', '), Color, TableId, Depth, FkId, Iteration
FROM NewRecords;

-- Record operation
DECLARE @RowCount INT = @@ROWCOUNT;
"@

        if ($MaxBatchSize -ne -1)
        {
            # Reset operation status if we hit the batch limit
            $query += @"

IF (@RowCount = $MaxBatchSize)
BEGIN
    UPDATE SqlSizer.Operations 
    SET [Status] = NULL 
    WHERE [SessionId] = '$SessionId' 
        AND [Status] = 0 
        AND [Table] = $tableId;
END
"@
        }

        $query += @"

INSERT INTO SqlSizer.Operations 
    ([Table], [Color], [ToProcess], [Status], [ParentTable], [FkId], [Depth], [StartDate], [SessionId], [Iteration])
VALUES 
    ($fkTableId, $Color, @RowCount, 0, $tableId, $fkId, $($Depth + 1), GETDATE(), '$SessionId', $Iteration);
"@

        return $query
    }

    function Invoke-IncomingTraversal
    {
        <#
        .SYNOPSIS
            Processes incoming foreign keys for a table at a specific depth.
        #>
        param
        (
            [TableInfo]$Table,
            [int]$Color,
            [int]$Depth,
            [int]$Iteration
        )

        $cacheKey = "$($Table.SchemaName)_$($Table.TableName)_$Color"
        $queries = @()

        # Generate or retrieve cached queries
        if ($incomingQueryCache.ContainsKey($cacheKey))
        {
            $cachedQueries = $incomingQueryCache[$cacheKey]
            # Replace depth and iteration placeholders
            foreach ($query in $cachedQueries)
            {
                if ($null -ne $query -and $query -ne "")
                {
                    $queries += $query.Replace("##DEPTH##", $Depth).Replace("##ITERATION##", $Iteration)
                }
            }
        }
        else
        {
            # Build queries for all incoming FKs
            $queryTemplates = @()
            
            foreach ($referencedByTable in $Table.IsReferencedBy)
            {
                $fks = $referencedByTable.ForeignKeys | Where-Object { 
                    ($_.Schema -eq $Table.SchemaName) -and ($_.Table -eq $Table.TableName) 
                }
                
                foreach ($fk in $fks)
                {
                    if ([TableInfo2]::IsIgnored($fk.FkSchema, $fk.FkTable, $ignoredTables))
                    {
                        continue
                    }

                    # Build query with placeholders
                    $queryTemplate = Build-IncomingTraversalQuery `
                        -Table $Table `
                        -Color $Color `
                        -ReferencedByTable $referencedByTable `
                        -Fk $fk `
                        -Depth "##DEPTH##" `
                        -Iteration "##ITERATION##"
                    
                    if ($null -ne $queryTemplate)
                    {
                        $queryTemplates += $queryTemplate
                    }
                }
            }
            
            $incomingQueryCache[$cacheKey] = $queryTemplates
            
            # Now substitute actual values
            foreach ($query in $queryTemplates)
            {
                if ($null -ne $query -and $query -ne "")
                {
                    $queries += $query.Replace("##DEPTH##", $Depth).Replace("##ITERATION##", $Iteration)
                }
            }
        }

        # Execute all queries
        if ($queries.Count -gt 0)
        {
            if ($ConnectionInfo.IsSynapse)
            {
                # Synapse: Execute queries with proper GO separators
                $combinedQuery = "DECLARE @SqlSizerCount INT = 0`n`n" + ($queries -join "`n`n")
                $null = Invoke-SqlcmdEx -Sql $combinedQuery -Database $Database -ConnectionInfo $ConnectionInfo
            }
            else
            {
                # Regular SQL Server: Execute queries individually with GO
                foreach ($query in $queries)
                {
                    $wrappedQuery = $query + "`nGO`n"
                    $null = Invoke-SqlcmdEx -Sql $wrappedQuery -Database $Database -ConnectionInfo $ConnectionInfo
                }
            }
        }
    }

    function Get-NextOperation
    {
        <#
        .SYNOPSIS
            Selects the next operation to process using optimized strategy.
        #>
        param ()

        # Select operation with lowest depth first, then highest count
        # This processes tables closest to the root first (BFS-like)
        $query = @"
SELECT TOP 1
    o.[Table],
    o.[Depth],
    o.[Color],
    SUM(o.[ToProcess] - o.[Processed]) AS [Count]
FROM SqlSizer.Operations o
WHERE o.[Status] IS NULL 
    AND o.[SessionId] = '$SessionId'
GROUP BY o.[Table], o.[Depth], o.[Color]
HAVING SUM(o.[ToProcess] - o.[Processed]) > 0
ORDER BY o.[Depth] ASC, [Count] DESC;
"@

        return Invoke-SqlcmdEx -Sql $query -Database $Database -ConnectionInfo $ConnectionInfo
    }

    function Update-OperationStatus
    {
        <#
        .SYNOPSIS
            Updates operation status for batch processing.
        #>
        param
        (
            [int]$TableId,
            [int]$Color,
            [int]$Depth
        )

        $query = @"
SELECT [Id], [ToProcess], [Processed] 
FROM SqlSizer.Operations 
WHERE [Table] = $TableId 
    AND [Status] IS NULL 
    AND [Color] = $Color 
    AND [Depth] = $Depth 
    AND [SessionId] = '$SessionId';
"@

        $operations = Invoke-SqlcmdEx -Sql $query -Database $Database -ConnectionInfo $ConnectionInfo

        if ($MaxBatchSize -eq -1)
        {
            # Process all at once
            foreach ($operation in $operations)
            {
                $updateQuery = @"
UPDATE SqlSizer.Operations 
SET [Status] = 0, [Processed] = [ToProcess] 
WHERE [Id] = $($operation.Id);
"@
                $null = Invoke-SqlcmdEx -Sql $updateQuery -Database $Database -ConnectionInfo $ConnectionInfo
            }
        }
        else
        {
            # Process with batch size limit
            $remainingBatchSize = $MaxBatchSize
            
            foreach ($operation in $operations)
            {
                if ($remainingBatchSize -le 0)
                {
                    break
                }

                $toProcess = $operation.ToProcess - $operation.Processed
                
                if ($toProcess -le 0)
                {
                    continue
                }

                $processAmount = [Math]::Min($toProcess, $remainingBatchSize)
                
                $updateQuery = @"
UPDATE SqlSizer.Operations 
SET [Status] = 0, 
    [Processed] = [Processed] + $processAmount 
WHERE [Id] = $($operation.Id);
"@
                $null = Invoke-SqlcmdEx -Sql $updateQuery -Database $Database -ConnectionInfo $ConnectionInfo
                
                $remainingBatchSize -= $processAmount
            }
        }
    }

    function Complete-ProcessedOperations
    {
        <#
        .SYNOPSIS
            Marks completed operations and resets partial ones.
        #>
        param
        (
            [int]$Iteration
        )

        # Reset operations that weren't fully processed
        $resetQuery = @"
UPDATE SqlSizer.Operations 
SET [Status] = NULL 
WHERE [Status] = 0 
    AND [ToProcess] <> [Processed] 
    AND [SessionId] = '$SessionId';
"@
        $null = Invoke-SqlcmdEx -Sql $resetQuery -Database $Database -ConnectionInfo $ConnectionInfo

        # Mark completed operations
        $completeQuery = @"
UPDATE SqlSizer.Operations 
SET [Status] = 1, 
    [ProcessedIteration] = $Iteration, 
    [ProcessedDate] = GETDATE() 
WHERE [Status] = 0 
    AND [SessionId] = '$SessionId';
"@
        $null = Invoke-SqlcmdEx -Sql $completeQuery -Database $Database -ConnectionInfo $ConnectionInfo
    }

    function Invoke-RemovalIteration
    {
        <#
        .SYNOPSIS
            Executes one iteration of the removal subset algorithm.
        #>
        param
        (
            [int]$Iteration,
            [datetime]$StartTime,
            [ref]$LastProgressTime
        )

        # Update progress periodically
        $progressInterval = 5
        $currentTime = Get-Date
        $elapsedSeconds = ($currentTime - $StartTime).TotalSeconds
        
        if ($elapsedSeconds -gt ($LastProgressTime.Value + $progressInterval))
        {
            $LastProgressTime.Value = $elapsedSeconds
            $progress = Get-SubsetProgress -Database $Database -ConnectionInfo $ConnectionInfo
            
            if ($progress.Processed + $progress.ToProcess -gt 0)
            {
                $percentComplete = [Math]::Min(100, [Math]::Round(100.0 * $progress.Processed / ($progress.Processed + $progress.ToProcess), 1))
                Write-Progress `
                    -Activity "Finding removal subset $SessionId" `
                    -Status "Processed: $($progress.Processed) | Remaining: $($progress.ToProcess)" `
                    -PercentComplete $percentComplete
            }
        }

        # Get next operation
        $operation = Get-NextOperation
        
        if ($null -eq $operation)
        {
            Write-Progress -Activity "Finding removal subset $SessionId" -Completed
            return $false
        }

        # Load table information
        $tableId = $operation.Table
        $color = $operation.Color
        $depth = $operation.Depth
        $tableData = $tablesById["$tableId"]
        $table = $DatabaseInfo.Tables | Where-Object { 
            ($_.SchemaName -eq $tableData.SchemaName) -and ($_.TableName -eq $tableData.TableName) 
        }
        $table.Id = $tableId

        Write-Verbose "Processing: $($table.SchemaName).$($table.TableName) (Depth: $depth, Color: $color, Count: $($operation.Count))"

        # Update operation status
        Update-OperationStatus -TableId $tableId -Color $color -Depth $depth

        # Process incoming foreign keys
        Invoke-IncomingTraversal -Table $table -Color $color -Depth $depth -Iteration $Iteration

        # Complete processed operations
        Complete-ProcessedOperations -Iteration $Iteration

        return $true
    }

    #endregion Helper Functions

    #region Main Execution

    if ($false -eq $Interactive)
    {
        # Non-interactive mode: run until completion
        $null = Initialize-OperationsTable `
            -SessionId $SessionId `
            -Database $Database `
            -ConnectionInfo $ConnectionInfo `
            -DatabaseInfo $DatabaseInfo `
            -StartIteration $StartIteration

        $startTime = Get-Date
        $lastProgressTime = 0
        $currentIteration = $StartIteration + 1

        Write-Progress -Activity "Finding removal subset $SessionId" -PercentComplete 0

        do
        {
            $hasMore = Invoke-RemovalIteration `
                -Iteration $currentIteration `
                -StartTime $startTime `
                -LastProgressTime ([ref]$lastProgressTime)
            
            $currentIteration++
        }
        while ($hasMore -eq $true)

        Write-Progress -Activity "Finding removal subset $SessionId" -Completed

        return [pscustomobject]@{
            Finished            = $true
            Initialized         = $true
            CompletedIterations = $currentIteration - $StartIteration - 1
        }
    }
    else
    {
        # Interactive mode: run one iteration at a time
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
            $lastProgressTime = 0
            
            $hasMore = Invoke-RemovalIteration `
                -Iteration $Iteration `
                -StartTime $startTime `
                -LastProgressTime ([ref]$lastProgressTime)

            return [pscustomobject]@{
                Finished            = $hasMore -eq $false
                Initialized         = $true
                CompletedIterations = 1
            }
        }
    }

    #endregion Main Execution
}
