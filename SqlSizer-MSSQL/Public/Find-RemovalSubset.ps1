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

.PARAMETER CheckpointPath
    Path to a JSON file for saving traversal progress. Enables checkpoint/resume for long-running
    traversals. If the file does not exist, it will be created. Progress is saved every
    CheckpointInterval iterations.

.PARAMETER CheckpointInterval
    How often (in iterations) to save a checkpoint. Default: 5.

.PARAMETER Resume
    Resume a previously interrupted traversal from the last checkpoint. Requires CheckpointPath
    to point to an existing checkpoint file.

.EXAMPLE
    Find-RemovalSubset -SessionId "session1" -Database "MyDB" `
        -DatabaseInfo $dbInfo -ConnectionInfo $connInfo

.EXAMPLE
    # Run with checkpointing
    Find-RemovalSubset -SessionId $sid -Database "MyDB" -DatabaseInfo $info -ConnectionInfo $conn `
        -CheckpointPath "C:\temp\removal_checkpoint.json"

.EXAMPLE
    # Resume after crash
    Find-RemovalSubset -SessionId $sid -Database "MyDB" -DatabaseInfo $info -ConnectionInfo $conn `
        -CheckpointPath "C:\temp\removal_checkpoint.json" -Resume

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
        [SqlConnectionInfo]$ConnectionInfo,

        [Parameter(Mandatory = $false)]
        [string]$CheckpointPath,

        [Parameter(Mandatory = $false)]
        [int]$CheckpointInterval = 5,

        [Parameter(Mandatory = $false)]
        [switch]$Resume
    )

    # Query cache for FK traversal patterns - keyed by "schema_table_color"
    # Value is an array of query templates for all incoming FKs for that table
    $incomingQueryCache = New-Object "System.Collections.Generic.Dictionary[[string], [string[]]]"
    
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
            $Depth,       # Can be int or string placeholder "##DEPTH##"
            $Iteration    # Can be int or string placeholder "##ITERATION##"
        )

        $tableId = $tablesByName[$Table.SchemaName + ", " + $Table.TableName].Id
        # O(1) lookup using hashtable instead of Where-Object
        $fkTable = $tablesByFullName["$($Fk.FkSchema), $($Fk.FkTable)"]
        $fkTableId = $tablesByName[$Fk.FkSchema + ", " + $Fk.FkTable].Id
        $fkId = $fksByName[$Fk.FkSchema + ", " + $Fk.FkTable + ", " + $Fk.Name].Id
        $fkSignature = $structure.Tables[$fkTable]
        $fkProcessing = $structure.GetProcessingName($fkSignature, $SessionId)
        $processing = $structure.GetProcessingName($structure.Tables[$Table], $SessionId)
        
        # Source table's primary key (for the SourceRecords CTE)
        $sourcePrimaryKey = $Table.PrimaryKey
        # FK table's primary key (for the INSERT into FK processing table)
        $fkPrimaryKey = $ReferencedByTable.PrimaryKey

        if (($null -eq $fkPrimaryKey) -or ($fkPrimaryKey.Count -eq 0))
        {
            return $null
        }

        # Build CTE for source records (columns based on SOURCE table's PK)
        $sourceColumns = @()
        for ($srcIdx = 0; $srcIdx -lt $sourcePrimaryKey.Count; $srcIdx++)
        {
            $sourceColumns += "Key$srcIdx"
        }

        # Build JOIN condition between FK table and source (with alias s.)
        $joinConditions = @()
        for ($joinIdx = 0; $joinIdx -lt $Fk.FkColumns.Count; $joinIdx++)
        {
            $joinConditions += "f.$($Fk.FkColumns[$joinIdx].Name) = s.Key$joinIdx"
        }

        # Build columns for result (based on FK table's primary key)
        $selectColumns = @()
        for ($selIdx = 0; $selIdx -lt $fkPrimaryKey.Count; $selIdx++)
        {
            $columnValue = Get-ColumnValue `
                -ColumnName $fkPrimaryKey[$selIdx].Name `
                -Prefix "f." `
                -dataType $fkPrimaryKey[$selIdx].dataType
            $selectColumns += "$columnValue AS Key$selIdx"
        }

        # MaxBatchSize limits source rows through the operation row-number window.
        # Do not TOP the dependent rows found from those source rows.
        $topClause = ""

        # Build primary key join conditions for NOT EXISTS clause (using FK table's PK)
        $pkJoinConditions = @()
        for ($pkIdx = 0; $pkIdx -lt $fkPrimaryKey.Count; $pkIdx++)
        {
            $pkJoinConditions += "p.Key$pkIdx = f.$($fkPrimaryKey[$pkIdx].Name)"
        }
        $pkJoinCondition = $pkJoinConditions -join ' AND '

        # Calculate depth+1 for the template (if $Depth is placeholder, use placeholder+1)
        $depthPlusOne = if ($Depth -eq "##DEPTH##") { "##DEPTH_PLUS_1##" } else { $Depth + 1 }

        # Generate CTE-based query (semicolon prefix for CTE is SQL Server best practice)
        # Note: Processing table columns are: Key0..N, [State], [Source], [Depth], [Fk], [Iteration]
        $query = @"
-- Find incoming references from $($Fk.FkSchema).$($Fk.FkTable) to $($Table.SchemaName).$($Table.TableName)
;WITH SourceRecordCandidates AS (
    SELECT $($sourceColumns -join ', '), [State], [Source], [Depth], [Fk], [Iteration],
        ROW_NUMBER() OVER (
            PARTITION BY [State], [Source], [Depth], [Fk], [Iteration]
            ORDER BY Id
        ) AS BatchRowNumber
    FROM $processing
    WHERE [State] = $Color
        AND [Depth] = $Depth
),
SourceRecords AS (
    SELECT $(($sourceColumns | ForEach-Object { "s.$_" }) -join ', ')
    FROM SourceRecordCandidates s
    INNER JOIN SqlSizer.Operations o ON o.[Table] = $tableId
        AND o.[State] = s.[State]
        AND o.[Depth] = s.[Depth]
        AND o.[FoundIteration] = s.[Iteration]
        AND ((o.[Source] = s.[Source]) OR (o.[Source] IS NULL AND s.[Source] IS NULL))
        AND ((o.[Fk] = s.[Fk]) OR (o.[Fk] IS NULL AND s.[Fk] IS NULL))
        AND o.[Status] = 0
        AND o.[SessionId] = '$SessionId'
    WHERE s.BatchRowNumber > ISNULL(o.ProcessedIteration, 0)
        AND s.BatchRowNumber <= o.Processed
),
NewRecords AS (
    SELECT $topClause
        $($selectColumns -join ",`n        "),
        $Color AS [State],
        $tableId AS [Source],
        $depthPlusOne AS [Depth],
        $fkId AS [Fk],
        $Iteration AS [Iteration]
    FROM $($ReferencedByTable.SchemaName).$($ReferencedByTable.TableName) f
    INNER JOIN SourceRecords s ON $($joinConditions -join ' AND ')
    WHERE NOT EXISTS (
        SELECT 1 
        FROM $fkProcessing p 
        WHERE $pkJoinCondition
    )
)
INSERT INTO $fkProcessing ($(0..($fkPrimaryKey.Count - 1) | ForEach-Object { "Key$_" } | Join-String -Separator ', '), [State], [Source], [Depth], [Fk], [Iteration])
SELECT $(0..($fkPrimaryKey.Count - 1) | ForEach-Object { "Key$_" } | Join-String -Separator ', '), [State], [Source], [Depth], [Fk], [Iteration]
FROM NewRecords;

-- Record operation
DECLARE @RowCount bigint = @@ROWCOUNT;
"@

        $query += @"

INSERT INTO SqlSizer.Operations 
    ([Table], [State], ToProcess, Processed, Status, Source, Fk, Depth, Created, ProcessedDate, SessionId, FoundIteration, ProcessedIteration)
VALUES 
    ($fkTableId, $Color, @RowCount, 0, NULL, $tableId, $fkId, $depthPlusOne, GETDATE(), NULL, '$SessionId', $Iteration, NULL);
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
                    $queries += $query.Replace("##DEPTH##", $Depth).Replace("##DEPTH_PLUS_1##", ($Depth + 1)).Replace("##ITERATION##", $Iteration)
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
                    $queries += $query.Replace("##DEPTH##", $Depth).Replace("##DEPTH_PLUS_1##", ($Depth + 1)).Replace("##ITERATION##", $Iteration)
                }
            }
        }

        # Execute all queries
        if ($queries.Count -gt 0)
        {
            # Execute each query individually
            foreach ($singleQuery in $queries)
            {
                $null = Invoke-SqlcmdEx -Sql $singleQuery -Database $Database -ConnectionInfo $ConnectionInfo
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
    o.[State],
    SUM(o.[ToProcess] - o.[Processed]) AS [Count]
FROM SqlSizer.Operations o
WHERE o.[Status] IS NULL 
    AND o.[SessionId] = '$SessionId'
GROUP BY o.[Table], o.[Depth], o.[State]
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
            [long]$TableId,
            [int]$Color,
            [int]$Depth
        )

        $query = @"
SELECT [Id], [ToProcess], [Processed] 
FROM SqlSizer.Operations 
WHERE [Table] = $TableId 
    AND [Status] IS NULL 
    AND [State] = $Color 
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
SET [Status] = 0,
    [ProcessedIteration] = [Processed],
    [Processed] = [ToProcess]
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
    [ProcessedIteration] = [Processed],
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
SET [Status] = NULL,
    [ProcessedIteration] = NULL
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
        $color = $operation.State
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
        if ($Resume)
        {
            # Resume from checkpoint
            if (-not $CheckpointPath)
            {
                throw "CheckpointPath is required when using -Resume."
            }
            if (-not (Test-Path $CheckpointPath))
            {
                throw "Checkpoint file not found: $CheckpointPath"
            }

            $checkpoint = Get-Content -Path $CheckpointPath -Raw | ConvertFrom-Json
            if ($checkpoint.Type -ne 'RemovalSubset')
            {
                throw "Checkpoint type mismatch. Expected 'RemovalSubset', found '$($checkpoint.Type)'."
            }
            if ($checkpoint.Status -eq 'Completed')
            {
                Write-Warning "Checkpoint indicates traversal already completed. Nothing to resume."
                return [pscustomobject]@{
                    Finished            = $true
                    Initialized         = $true
                    CompletedIterations = 0
                }
            }
            if ($checkpoint.SessionId -ne $SessionId)
            {
                throw "SessionId mismatch. Checkpoint is for session '$($checkpoint.SessionId)', but '$SessionId' was provided."
            }

            $StartIteration = $checkpoint.LastCompletedIteration
            Write-Verbose "Resuming from iteration $StartIteration (checkpoint: $CheckpointPath)"

            # Reset any abandoned in-progress operations
            $resetSql = @"
UPDATE SqlSizer.Operations
SET Status = NULL,
    Processed = ISNULL(ProcessedIteration, Processed),
    ProcessedIteration = NULL
WHERE Status = 0 AND SessionId = '$SessionId';
"@
            $null = Invoke-SqlcmdEx -Sql $resetSql -Database $Database -ConnectionInfo $ConnectionInfo
        }
        else
        {
            # Normal start: initialize operations
            $null = Initialize-OperationsTable `
                -SessionId $SessionId `
                -Database $Database `
                -ConnectionInfo $ConnectionInfo `
                -DatabaseInfo $DatabaseInfo `
                -StartIteration $StartIteration

            # Write initial checkpoint
            if ($CheckpointPath)
            {
                $initialCheckpoint = [ordered]@{
                    Type                   = 'RemovalSubset'
                    SessionId              = $SessionId
                    Database               = $Database
                    LastCompletedIteration = $StartIteration
                    MaxBatchSize           = $MaxBatchSize
                    Status                 = 'InProgress'
                    CreatedAt              = (Get-Date).ToString('o')
                    UpdatedAt              = (Get-Date).ToString('o')
                }
                $initialCheckpoint | ConvertTo-Json -Depth 10 | Set-Content -Path $CheckpointPath -Encoding UTF8
                Write-Verbose "Checkpoint created: $CheckpointPath"
            }
        }

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

            # Save checkpoint periodically
            if ($CheckpointPath -and (($currentIteration % $CheckpointInterval) -eq 0))
            {
                $iterationCheckpoint = [ordered]@{
                    Type                   = 'RemovalSubset'
                    SessionId              = $SessionId
                    Database               = $Database
                    LastCompletedIteration = $currentIteration
                    MaxBatchSize           = $MaxBatchSize
                    Status                 = 'InProgress'
                    CreatedAt              = if ($Resume -and $checkpoint.CreatedAt) { $checkpoint.CreatedAt } else { $startTime.ToString('o') }
                    UpdatedAt              = (Get-Date).ToString('o')
                }
                $iterationCheckpoint | ConvertTo-Json -Depth 10 | Set-Content -Path $CheckpointPath -Encoding UTF8
            }

            $currentIteration++
        }
        while ($hasMore -eq $true)

        # Write final checkpoint
        if ($CheckpointPath)
        {
            $finalCheckpoint = [ordered]@{
                Type                   = 'RemovalSubset'
                SessionId              = $SessionId
                Database               = $Database
                LastCompletedIteration = $currentIteration
                MaxBatchSize           = $MaxBatchSize
                Status                 = 'Completed'
                CreatedAt              = if ($Resume -and $checkpoint.CreatedAt) { $checkpoint.CreatedAt } else { $startTime.ToString('o') }
                UpdatedAt              = (Get-Date).ToString('o')
            }
            $finalCheckpoint | ConvertTo-Json -Depth 10 | Set-Content -Path $CheckpointPath -Encoding UTF8
            Write-Verbose "Traversal completed. Final checkpoint saved to $CheckpointPath"
        }

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
