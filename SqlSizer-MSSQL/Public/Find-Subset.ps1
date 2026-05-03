<#
.SYNOPSIS
    Finds a referentially-complete subset from a database by traversing foreign key relationships.

.DESCRIPTION
    Traverses outgoing and incoming foreign key relationships from a starting set of rows
    to build a complete, referentially-consistent subset suitable for data extraction, testing,
    or migration scenarios.
    
    Algorithm features:
    1. TraversalState enum for explicit row classification
    2. Unified traversal function for both directions
    3. Proper state resolution without data duplication
    4. Set-based key deduplication for cycle safety
    5. Batch processing with set-based operations
    6. CTE-based SQL generation for clarity

.PARAMETER CheckpointPath
    Path to a JSON file for saving traversal progress. Enables checkpoint/resume for long-running
    traversals. If the file does not exist, it will be created. Progress is saved every
    CheckpointInterval iterations.

.PARAMETER CheckpointInterval
    How often (in iterations) to save a checkpoint. Default: 5.

.PARAMETER Resume
    Resume a previously interrupted traversal from the last checkpoint. Requires CheckpointPath
    to point to an existing checkpoint file. Skips Initialize-OperationsTable and recovers
    the iteration counter from the checkpoint.

.PARAMETER MaxSubsetPercentOfSource
    Warn when included subset rows exceed this percentage of PK-bearing source rows.
    Default: 20. Set to 0 to disable row-ratio warnings.

.PARAMETER MaxReachableTablePercent
    Warn before traversal when metadata reachability can cover more than this percentage
    of PK-bearing user tables. Default: 80. Set to 0 to disable preflight warnings.

.PARAMETER SubsetGuardCheckInterval
    How often (in traversal iterations) to check the runtime subset-size guard. Default: 5.

.PARAMETER ThrowOnSubsetGuardExceeded
    Throw a terminating error when the runtime subset-size guard is exceeded. Default: false.

.PARAMETER CollectSqlStatistics
    Collect SQL Server logical-read statistics during traversal. Disabled by default because
    STATISTICS IO adds measurable overhead to large traversal runs. Enable when profiling.

.PARAMETER ProgressRefreshInterval
    How often (in iterations) to refresh aggregate progress statistics. Default: 5.

.NOTES
    Initialize the start set using Initialize-StartSet before calling this function.
    For long-running traversals, use -CheckpointPath to enable automatic progress saving.
    If the process crashes, use -Resume -CheckpointPath to pick up where you left off.

.EXAMPLE
    # Run with checkpointing
    Find-Subset -Database "MyDB" -SessionId $sid -DatabaseInfo $info -ConnectionInfo $conn `
        -CheckpointPath "C:\temp\subset_checkpoint.json"

.EXAMPLE
    # Resume after crash
    Find-Subset -Database "MyDB" -SessionId $sid -DatabaseInfo $info -ConnectionInfo $conn `
        -CheckpointPath "C:\temp\subset_checkpoint.json" -Resume
#>

function Find-Subset
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
        [SqlConnectionInfo]$ConnectionInfo,

        [Parameter(Mandatory = $false)]
        [string]$CheckpointPath,

        [Parameter(Mandatory = $false)]
        [int]$CheckpointInterval = 5,

        [Parameter(Mandatory = $false)]
        [double]$MaxSubsetPercentOfSource = 20.0,

        [Parameter(Mandatory = $false)]
        [double]$MaxReachableTablePercent = 80.0,

        [Parameter(Mandatory = $false)]
        [int]$SubsetGuardCheckInterval = 5,

        [Parameter(Mandatory = $false)]
        [bool]$ThrowOnSubsetGuardExceeded = $false,

        [Parameter(Mandatory = $false)]
        [bool]$CollectSqlStatistics = $false,

        [Parameter(Mandatory = $false)]
        [int]$ProgressRefreshInterval = 5,

        [Parameter(Mandatory = $false)]
        [switch]$Resume
    )

    if ($MaxSubsetPercentOfSource -lt 0)
    {
        throw "MaxSubsetPercentOfSource must be greater than or equal to 0."
    }

    if ($MaxReachableTablePercent -lt 0)
    {
        throw "MaxReachableTablePercent must be greater than or equal to 0."
    }

    if ($SubsetGuardCheckInterval -lt 1)
    {
        throw "SubsetGuardCheckInterval must be greater than or equal to 1."
    }

    if ($ProgressRefreshInterval -lt 1)
    {
        throw "ProgressRefreshInterval must be greater than or equal to 1."
    }

    # O(1) table lookup hashtable - built at initialization
    $tablesByFullName = @{}
    foreach ($t in $DatabaseInfo.Tables) {
        $tablesByFullName["$($t.SchemaName), $($t.TableName)"] = $t
    }
    
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

        # Use List<string> instead of += for efficient string building
        $queryList = [System.Collections.Generic.List[string]]::new()
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
            # For outgoing, $rel is already a single FK from $Table.ForeignKeys
            $fks = if ($Direction -eq [TraversalDirection]::Incoming) {
                $rel.ForeignKeys | Where-Object { 
                    ($_.Schema -eq $Table.SchemaName) -and ($_.Table -eq $Table.TableName) 
                }
            } else {
                @($rel)  # Wrap single FK in array for consistent iteration
            }

            foreach ($fk in $fks)
            {
                $targetSchema = if ($Direction -eq [TraversalDirection]::Outgoing) { $fk.Schema } else { $fk.FkSchema }
                $targetTable = if ($Direction -eq [TraversalDirection]::Outgoing) { $fk.Table } else { $fk.FkTable }

                # Skip ignored tables (from both separate parameter and TraversalConfiguration)
                $isIgnoredFromParam = [TableInfo2]::IsIgnored($targetSchema, $targetTable, $IgnoredTables)
                $isIgnoredFromConfig = $TraversalConfiguration -and [TableInfo2]::IsIgnored($targetSchema, $targetTable, $TraversalConfiguration.IgnoredTables)
                if ($isIgnoredFromParam -or $isIgnoredFromConfig)
                {
                    continue
                }

                # O(1) lookup using hashtable instead of Where-Object
                $targetTableInfo = $tablesByFullName["$targetSchema, $targetTable"]
                
                if ($null -eq $targetTableInfo -or $targetTableInfo.PrimaryKey.Count -eq 0)
                {
                    continue
                }

                $targetTableId = $tablesGroupedByName["$targetSchema, $targetTable"].Id
                $targetSignature = $structure.Tables[$targetTableInfo]
                $targetProcessing = $structure.GetProcessingName($targetSignature, $SessionId)
                $fkId = $fkGroupedByName["$($fk.FkSchema), $($fk.FkTable), $($fk.Name)"].Id

                $branches = Get-TraversalRuleBranches `
                    -Direction $Direction `
                    -CurrentState $State `
                    -Fk $fk `
                    -SourceSchemaName $Table.SchemaName `
                    -SourceTableName $Table.TableName `
                    -ForeignKeyName $fk.Name `
                    -TraversalConfiguration $TraversalConfiguration `
                    -FullSearch $FullSearch

                foreach ($branch in $branches)
                {
                    $newState = [TraversalState]$branch.NewState
                    if ($newState -eq [TraversalState]::Exclude)
                    {
                        continue
                    }

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
                        -Constraints $branch.Constraints `
                        -Iteration $Iteration `
                        -SessionId $SessionId `
                        -MaxBatchSize $MaxBatchSize `
                        -FullSearch $FullSearch

                    $queryList.Add($query)
                }
            }
        }

        return ($queryList -join "`n")
    }

    function Invoke-TraversalOperation
    {
        <#
        .SYNOPSIS
            Executes a single traversal operation (processes one table + state + depth).
        .DESCRIPTION
            Batches outgoing and incoming FK queries into a single SQL execution
            to reduce database round-trips.
        #>
        param
        (
            [TraversalOperation]$Operation,
            [int]$Iteration
        )

        # O(1) lookup using hashtable instead of Where-Object
        $table = $tablesByFullName["$($Operation.TableSchema), $($Operation.TableName)"]

        Write-FindSubsetProgress -Phase "Preparing traversal SQL" -Iteration $Iteration -Operation $Operation -Table $table

        # Check which directions to traverse
        $traverseOutgoing = Test-ShouldTraverseDirection -State $Operation.State -Direction ([TraversalDirection]::Outgoing) -FullSearch $FullSearch
        $traverseIncoming = Test-ShouldTraverseDirection -State $Operation.State -Direction ([TraversalDirection]::Incoming) -FullSearch $FullSearch

        # Collect queries for batched execution
        $batchedQueries = [System.Collections.Generic.List[string]]::new()

        # Build outgoing traversal query
        if ($traverseOutgoing)
        {
            Write-FindSubsetProgress -Phase "Building outgoing traversal SQL" -Iteration $Iteration -Operation $Operation -Table $table
            $query = New-TraversalQuery `
                -Table $table `
                -State $Operation.State `
                -Direction ([TraversalDirection]::Outgoing) `
                -TraversalConfiguration $TraversalConfiguration `
                -Iteration $Iteration

            if ($query -ne "")
            {
                $batchedQueries.Add($query)
            }
        }

        # Build incoming traversal query
        if ($traverseIncoming)
        {
            Write-FindSubsetProgress -Phase "Building incoming traversal SQL" -Iteration $Iteration -Operation $Operation -Table $table
            $query = New-TraversalQuery `
                -Table $table `
                -State $Operation.State `
                -Direction ([TraversalDirection]::Incoming) `
                -TraversalConfiguration $TraversalConfiguration `
                -Iteration $Iteration

            if ($query -ne "")
            {
                $batchedQueries.Add($query)
            }
        }

        # Execute all queries in a single batch (reduces round-trips)
        if ($batchedQueries.Count -gt 0)
        {
            $batchedSql = $batchedQueries -join "`n"
            $phase = "Executing traversal SQL ($($batchedQueries.Count) batches)"
            $null = Invoke-FindSubsetSql -Sql $batchedSql -Phase $phase -Iteration $Iteration -Operation $Operation -Table $table
        }
        else
        {
            Write-FindSubsetProgress -Phase "No traversal SQL generated" -Iteration $Iteration -Operation $Operation -Table $table
            Write-Verbose "No traversal SQL generated for $($table.SchemaName).$($table.TableName), state $($Operation.State), depth $($Operation.Depth)"
        }

        # Candidate/bookkeeping states are resolved after the closure is complete.
    }

    function Resolve-PendingStates
    {
        <#
        .SYNOPSIS
            Marks remaining Pending states as Exclude after traversal completes.
        .DESCRIPTION
            Pending is a compatibility/candidate state. The default minimal subset
            policy does not emit Pending rows because Include does not traverse
            incoming FKs unless FullSearch is enabled. If callers seed or override
            rows as Pending, those rows are not part of output unless promoted.
            
            This function marks any remaining Pending records as Exclude - these are
            records that were discovered as candidates but never confirmed as necessary
            for the subset.
        #>
        param
        (
            [int]$Iteration
        )

        Write-Verbose "Marking remaining Pending states as Exclude for iteration $Iteration"

        # Pre-filter tables with PK outside the loop
        $tables = $DatabaseInfo.Tables | Where-Object { $_.PrimaryKey.Count -gt 0 }
        $excludedCount = 0

        # Mark ALL remaining Pending as Exclude (those not promoted to Include during traversal)
        foreach ($table in $tables)
        {
            $signature = $structure.Tables[$table]
            $processing = $structure.GetProcessingName($signature, $SessionId)
            $query = New-ExcludePendingQuery -ProcessingTable $processing -TableInfo $table

            $result = Invoke-FindSubsetSql -Sql $query -Phase "Resolving pending states: $($table.SchemaName).$($table.TableName)" -Iteration $Iteration -Table $table
            if ($null -ne $result -and $null -ne $result.ExcludedCount)
            {
                $excludedCount += $result.ExcludedCount
            }
        }

        Write-Verbose "Marked $excludedCount Pending records as Exclude"
    }

    function Get-NextOperation
    {
        <#
        .SYNOPSIS
            Gets the next operation to process (BFS or legacy size-first ordering).
        #>
        param
        (
            [bool]$UseDfs,

            [int]$Iteration
        )

        $query = New-GetNextOperationQuery -SessionId $SessionId -UseDfs $UseDfs

        $result = Invoke-FindSubsetSql -Sql $query -Phase "Selecting next operation" -Iteration $Iteration

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

    function Set-OperationInProgress
    {
        <#
        .SYNOPSIS
            Marks operations as in-progress (Status = 0).
        #>
        param
        (
            [TraversalOperation]$Operation,

            [int]$Iteration
        )

        $state = [int]$Operation.State
        $query = New-MarkOperationInProgressQuery `
            -TableId $Operation.TableId `
            -State $state `
            -Depth $Operation.Depth `
            -SessionId $SessionId `
            -MaxBatchSize $MaxBatchSize

        $table = $tablesByFullName["$($Operation.TableSchema), $($Operation.TableName)"]
        $null = Invoke-FindSubsetSql -Sql $query -Phase "Marking operation in progress" -Iteration $Iteration -Operation $Operation -Table $table
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

        $query = New-CompleteOperationsQuery -SessionId $SessionId -Iteration $Iteration

        $null = Invoke-FindSubsetSql -Sql $query -Phase "Completing operation" -Iteration $Iteration
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

        $query = New-GetIterationStatisticsQuery -SessionId $SessionId

        $result = Invoke-FindSubsetSql -Sql $query -Phase "Refreshing progress statistics" -Iteration $Iteration

        $stats = [TraversalStatistics]::new()
        $stats.TotalOperations = ConvertTo-FindSubsetProgressLong -Value $result.TotalOperations
        $stats.CompletedOperations = ConvertTo-FindSubsetProgressLong -Value $result.CompletedOperations
        $stats.TotalRecordsProcessed = ConvertTo-FindSubsetProgressLong -Value $result.TotalRecordsProcessed
        $stats.TotalRecordsRemaining = ConvertTo-FindSubsetProgressLong -Value $result.TotalRecordsRemaining
        $stats.CurrentIteration = $Iteration
        $stats.MaxDepthReached = [int](ConvertTo-FindSubsetProgressLong -Value $result.MaxDepthReached)
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
        $operation = Get-NextOperation -UseDfs $UseDfs -Iteration $Iteration

        if ($null -eq $operation)
        {
            Write-Verbose "No more operations to process"
            return $false
        }

        # Mark as in-progress
        Set-OperationInProgress -Operation $operation -Iteration $Iteration

        # Execute traversal
        Invoke-TraversalOperation -Operation $operation -Iteration $Iteration

        # Complete operations
        Complete-Operations -Iteration $Iteration

        return $true
    }

    #endregion

    function Write-FindSubsetProgress
    {
        param
        (
            [Parameter(Mandatory = $true)]
            [string]$Phase,

            [Parameter(Mandatory = $true)]
            [int]$Iteration,

            [Parameter(Mandatory = $false)]
            [AllowNull()]
            [TraversalOperation]$Operation = $null,

            [Parameter(Mandatory = $false)]
            [AllowNull()]
            [TableInfo]$Table = $null,

            [Parameter(Mandatory = $false)]
            [AllowNull()]
            [TraversalStatistics]$Statistics = $null
        )

        $stats = $Statistics
        if ($null -eq $stats)
        {
            $stats = $progressStats
        }

        $elapsed = [TimeSpan]::Zero
        if ($null -ne $startTime)
        {
            $elapsed = (Get-Date) - $startTime
        }

        $progressPercent = Get-FindSubsetProgressPercent -Statistics $stats
        $progressStatus = Get-FindSubsetProgressStatus `
            -Statistics $stats `
            -Iteration $Iteration `
            -ElapsedTime $elapsed `
            -Phase $Phase

        if (($null -ne $Operation) -and ($null -ne $Table))
        {
            $progressOperation = Get-FindSubsetProgressCurrentOperation -Table $Table -Operation $Operation -Phase $Phase
        }
        else
        {
            $progressOperation = $Phase
        }

        Write-Progress -Activity "Finding subset $SessionId" `
                       -Status $progressStatus `
                       -CurrentOperation $progressOperation `
                       -PercentComplete ([int][Math]::Round($progressPercent))
    }

    function Invoke-FindSubsetSql
    {
        param
        (
            [Parameter(Mandatory = $true)]
            [string]$Sql,

            [Parameter(Mandatory = $true)]
            [string]$Phase,

            [Parameter(Mandatory = $true)]
            [int]$Iteration,

            [Parameter(Mandatory = $false)]
            [AllowNull()]
            [TraversalOperation]$Operation = $null,

            [Parameter(Mandatory = $false)]
            [AllowNull()]
            [TableInfo]$Table = $null
        )

        Write-FindSubsetProgress -Phase $Phase -Iteration $Iteration -Operation $Operation -Table $Table

        $beforeReads = 0
        if ($null -ne $ConnectionInfo.Statistics)
        {
            $beforeReads = $ConnectionInfo.Statistics.LogicalReads
        }

        $watch = [System.Diagnostics.Stopwatch]::StartNew()
        Write-Verbose ("Find-Subset SQL start: {0}; iteration {1}; sql chars {2:N0}; statistics {3}" -f $Phase, $Iteration, $Sql.Length, $CollectSqlStatistics)
        try
        {
            return Invoke-SqlcmdEx -Sql $Sql -Database $Database -ConnectionInfo $ConnectionInfo -Statistics $CollectSqlStatistics
        }
        finally
        {
            $watch.Stop()
            $logicalReads = 0
            if ($CollectSqlStatistics -and ($null -ne $ConnectionInfo.Statistics))
            {
                $logicalReads = $ConnectionInfo.Statistics.LogicalReads - $beforeReads
            }

            $readText = if ($CollectSqlStatistics) { "; logical reads {0:N0}" -f $logicalReads } else { "; statistics off" }
            Write-Verbose ("Find-Subset SQL complete: {0}; iteration {1}; elapsed {2:N2}s{3}" -f $Phase, $Iteration, $watch.Elapsed.TotalSeconds, $readText)
        }
    }

    #region Main Execution

    # Initialize metadata
    $structure = [Structure]::new($DatabaseInfo)
    $sqlSizerInfo = Get-SqlSizerInfo -Database $Database -ConnectionInfo $ConnectionInfo -Statistics $CollectSqlStatistics
    $tablesGroupedByName = $sqlSizerInfo.Tables | Group-Object -Property SchemaName, TableName -AsHashTable -AsString
    $fkGroupedByName = $sqlSizerInfo.ForeignKeys | Group-Object -Property FkSchemaName, FkTableName, Name -AsHashTable -AsString
    $subsetGuardPreflight = $null
    $subsetGuardRuntime = $null
    $subsetGuardRuntimeWarningRaised = $false

    if ($Interactive -eq $false)
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
            if ($checkpoint.Type -ne 'Subset')
            {
                throw "Checkpoint type mismatch. Expected 'Subset', found '$($checkpoint.Type)'."
            }
            if ($checkpoint.Status -eq 'Completed')
            {
                Write-Warning "Checkpoint indicates traversal already completed. Nothing to resume."
                return [pscustomobject]@{
                    Finished            = $true
                    Initialized         = $true
                    CompletedIterations = 0
                    SubsetSizeGuard     = $null
                }
            }
            if ($checkpoint.SessionId -ne $SessionId)
            {
                throw "SessionId mismatch. Checkpoint is for session '$($checkpoint.SessionId)', but '$SessionId' was provided."
            }

            if ((-not $PSBoundParameters.ContainsKey('MaxSubsetPercentOfSource')) -and $checkpoint.PSObject.Properties['MaxSubsetPercentOfSource'])
            {
                $MaxSubsetPercentOfSource = [double]$checkpoint.MaxSubsetPercentOfSource
            }
            if ((-not $PSBoundParameters.ContainsKey('MaxReachableTablePercent')) -and $checkpoint.PSObject.Properties['MaxReachableTablePercent'])
            {
                $MaxReachableTablePercent = [double]$checkpoint.MaxReachableTablePercent
            }
            if ((-not $PSBoundParameters.ContainsKey('SubsetGuardCheckInterval')) -and $checkpoint.PSObject.Properties['SubsetGuardCheckInterval'])
            {
                $SubsetGuardCheckInterval = [int]$checkpoint.SubsetGuardCheckInterval
            }
            if ((-not $PSBoundParameters.ContainsKey('ThrowOnSubsetGuardExceeded')) -and $checkpoint.PSObject.Properties['ThrowOnSubsetGuardExceeded'])
            {
                $ThrowOnSubsetGuardExceeded = [bool]$checkpoint.ThrowOnSubsetGuardExceeded
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
            $null = Invoke-SqlcmdEx -Sql $resetSql -Database $Database -ConnectionInfo $ConnectionInfo -Statistics $CollectSqlStatistics
        }
        else
        {
            $subsetGuardPreflight = Invoke-SubsetGuardPreflight `
                -SessionId $SessionId `
                -Database $Database `
                -DatabaseInfo $DatabaseInfo `
                -ConnectionInfo $ConnectionInfo `
                -Structure $structure `
                -StartIteration $StartIteration `
                -IgnoredTables $IgnoredTables `
                -TraversalConfiguration $TraversalConfiguration `
                -FullSearch $FullSearch `
                -MaxReachableTablePercent $MaxReachableTablePercent

            # Normal start: initialize operations
            $null = Initialize-OperationsTable `
                -SessionId $SessionId `
                -Database $Database `
                -ConnectionInfo $ConnectionInfo `
                -DatabaseInfo $DatabaseInfo `
                -StartIteration $StartIteration `
                -Statistics $CollectSqlStatistics

            # Write initial checkpoint
            if ($CheckpointPath)
            {
                $initialCheckpoint = [ordered]@{
                    Type                   = 'Subset'
                    SessionId              = $SessionId
                    Database               = $Database
                    LastCompletedIteration = $StartIteration
                    FullSearch             = $FullSearch
                    UseDfs                 = $UseDfs
                    MaxBatchSize           = $MaxBatchSize
                    MaxSubsetPercentOfSource = $MaxSubsetPercentOfSource
                    MaxReachableTablePercent = $MaxReachableTablePercent
                    SubsetGuardCheckInterval = $SubsetGuardCheckInterval
                    ThrowOnSubsetGuardExceeded = $ThrowOnSubsetGuardExceeded
                    Status                 = 'InProgress'
                    CreatedAt              = (Get-Date).ToString('o')
                    UpdatedAt              = (Get-Date).ToString('o')
                }
                $initialCheckpoint | ConvertTo-Json -Depth 10 | Set-Content -Path $CheckpointPath -Encoding UTF8
                Write-Verbose "Checkpoint created: $CheckpointPath"
            }
        }

        $startTime = Get-Date
        $iteration = $StartIteration + 1
        $progressStats = Get-IterationStatistics -Iteration $StartIteration -StartTime $startTime

        do
        {
            $hasMoreWork = Invoke-SearchIteration -Iteration $iteration

            $refreshedProgressStats = $false
            if (($iteration % $ProgressRefreshInterval) -eq 0)
            {
                $progressStats = Get-IterationStatistics -Iteration $iteration -StartTime $startTime
                $refreshedProgressStats = $true
            }

            # Update progress and checkpoint
            if (($iteration % $CheckpointInterval) -eq 0)
            {
                if (-not $refreshedProgressStats)
                {
                    $progressStats = Get-IterationStatistics -Iteration $iteration -StartTime $startTime
                }

                $stats = $progressStats
                Write-Verbose $stats.ToString()

                if ($CheckpointPath)
                {
                    $iterationCheckpoint = [ordered]@{
                        Type                   = 'Subset'
                        SessionId              = $SessionId
                        Database               = $Database
                        LastCompletedIteration = $iteration
                        FullSearch             = $FullSearch
                        UseDfs                 = $UseDfs
                        MaxBatchSize           = $MaxBatchSize
                        MaxSubsetPercentOfSource = $MaxSubsetPercentOfSource
                        MaxReachableTablePercent = $MaxReachableTablePercent
                        SubsetGuardCheckInterval = $SubsetGuardCheckInterval
                        ThrowOnSubsetGuardExceeded = $ThrowOnSubsetGuardExceeded
                        Status                 = 'InProgress'
                        CreatedAt              = if ($Resume -and $checkpoint.CreatedAt) { $checkpoint.CreatedAt } else { $startTime.ToString('o') }
                        UpdatedAt              = (Get-Date).ToString('o')
                    }
                    $iterationCheckpoint | ConvertTo-Json -Depth 10 | Set-Content -Path $CheckpointPath -Encoding UTF8
                }
            }

            if (($iteration % $SubsetGuardCheckInterval) -eq 0)
            {
                $subsetGuardRuntime = Invoke-SubsetGuardRuntimeCheck `
                    -SessionId $SessionId `
                    -Database $Database `
                    -DatabaseInfo $DatabaseInfo `
                    -ConnectionInfo $ConnectionInfo `
                    -MaxSubsetPercentOfSource $MaxSubsetPercentOfSource `
                    -Iteration $iteration `
                    -Phase 'Runtime' `
                    -EmitWarning (-not $subsetGuardRuntimeWarningRaised) `
                    -ThrowOnExceeded $ThrowOnSubsetGuardExceeded

                if ($subsetGuardRuntime.Exceeded)
                {
                    $subsetGuardRuntimeWarningRaised = $true
                }
            }

            $iteration++
        }
        while ($hasMoreWork)

        # Resolve all remaining Pending states after traversal completes
        if (-not $FullSearch)
        {
            Resolve-PendingStates -Iteration $iteration
        }

        $subsetGuardRuntime = Invoke-SubsetGuardRuntimeCheck `
            -SessionId $SessionId `
            -Database $Database `
            -DatabaseInfo $DatabaseInfo `
            -ConnectionInfo $ConnectionInfo `
            -MaxSubsetPercentOfSource $MaxSubsetPercentOfSource `
            -Iteration $iteration `
            -Phase 'Final' `
            -EmitWarning (-not $subsetGuardRuntimeWarningRaised) `
            -ThrowOnExceeded $ThrowOnSubsetGuardExceeded

        if ($subsetGuardRuntime.Exceeded)
        {
            $subsetGuardRuntimeWarningRaised = $true
        }

        # Write final checkpoint
        if ($CheckpointPath)
        {
            $finalCheckpoint = [ordered]@{
                Type                   = 'Subset'
                SessionId              = $SessionId
                Database               = $Database
                LastCompletedIteration = $iteration
                FullSearch             = $FullSearch
                UseDfs                 = $UseDfs
                MaxBatchSize           = $MaxBatchSize
                MaxSubsetPercentOfSource = $MaxSubsetPercentOfSource
                MaxReachableTablePercent = $MaxReachableTablePercent
                SubsetGuardCheckInterval = $SubsetGuardCheckInterval
                ThrowOnSubsetGuardExceeded = $ThrowOnSubsetGuardExceeded
                Status                 = 'Completed'
                CreatedAt              = if ($Resume -and $checkpoint.CreatedAt) { $checkpoint.CreatedAt } else { $startTime.ToString('o') }
                UpdatedAt              = (Get-Date).ToString('o')
            }
            $finalCheckpoint | ConvertTo-Json -Depth 10 | Set-Content -Path $CheckpointPath -Encoding UTF8
            Write-Verbose "Traversal completed. Final checkpoint saved to $CheckpointPath"
        }

        Write-Progress -Activity "Finding subset $SessionId" -Completed

        return [pscustomobject]@{
            Finished            = $true
            Initialized         = $true
            CompletedIterations = $iteration - $StartIteration
            SubsetSizeGuard     = New-SubsetGuardResult -Preflight $subsetGuardPreflight -Runtime $subsetGuardRuntime
        }
    }
    else
    {
        # Interactive mode: one iteration at a time
        if ($Iteration -eq 0)
        {
            $subsetGuardPreflight = Invoke-SubsetGuardPreflight `
                -SessionId $SessionId `
                -Database $Database `
                -DatabaseInfo $DatabaseInfo `
                -ConnectionInfo $ConnectionInfo `
                -Structure $structure `
                -StartIteration $StartIteration `
                -IgnoredTables $IgnoredTables `
                -TraversalConfiguration $TraversalConfiguration `
                -FullSearch $FullSearch `
                -MaxReachableTablePercent $MaxReachableTablePercent

            $null = Initialize-OperationsTable `
                -SessionId $SessionId `
                -Database $Database `
                -ConnectionInfo $ConnectionInfo `
                -DatabaseInfo $DatabaseInfo `
                -StartIteration $StartIteration `
                -Statistics $CollectSqlStatistics

            return [pscustomobject]@{
                Finished            = $false
                Initialized         = $true
                CompletedIterations = 1
                SubsetSizeGuard     = New-SubsetGuardResult -Preflight $subsetGuardPreflight -Runtime $null
            }
        }
        else
        {
            $startTime = Get-Date
            $progressStats = Get-IterationStatistics -Iteration $Iteration -StartTime $startTime
            $hasMoreWork = Invoke-SearchIteration -Iteration $Iteration

            # Resolve Pending states when traversal is complete
            if (-not $hasMoreWork -and -not $FullSearch)
            {
                Resolve-PendingStates -Iteration $Iteration
            }

            if (-not $hasMoreWork)
            {
                $subsetGuardRuntime = Invoke-SubsetGuardRuntimeCheck `
                    -SessionId $SessionId `
                    -Database $Database `
                    -DatabaseInfo $DatabaseInfo `
                    -ConnectionInfo $ConnectionInfo `
                    -MaxSubsetPercentOfSource $MaxSubsetPercentOfSource `
                    -Iteration $Iteration `
                    -Phase 'Final' `
                    -EmitWarning $true `
                    -ThrowOnExceeded $ThrowOnSubsetGuardExceeded
            }

            return [pscustomobject]@{
                Finished            = -not $hasMoreWork
                Initialized         = $true
                CompletedIterations = 1
                SubsetSizeGuard     = $(if (-not $hasMoreWork) { New-SubsetGuardResult -Preflight $null -Runtime $subsetGuardRuntime } else { $null })
            }
        }
    }

    #endregion
}

function ConvertTo-FindSubsetProgressLong
{
    [cmdletbinding()]
    [outputtype([long])]
    param
    (
        [Parameter(Mandatory = $false)]
        [AllowNull()]
        [object]$Value,

        [Parameter(Mandatory = $false)]
        [long]$DefaultValue = 0
    )

    if ($null -eq $Value -or $Value -is [System.DBNull])
    {
        return $DefaultValue
    }

    return [Convert]::ToInt64($Value, [System.Globalization.CultureInfo]::InvariantCulture)
}

function Format-FindSubsetProgressNumber
{
    [cmdletbinding()]
    [outputtype([string])]
    param
    (
        [Parameter(Mandatory = $false)]
        [AllowNull()]
        [object]$Value
    )

    $culture = [System.Globalization.CultureInfo]::InvariantCulture
    return (ConvertTo-FindSubsetProgressLong -Value $Value).ToString("N0", $culture)
}

function Format-FindSubsetProgressElapsedTime
{
    [cmdletbinding()]
    [outputtype([string])]
    param
    (
        [Parameter(Mandatory = $false)]
        [AllowNull()]
        [TimeSpan]$ElapsedTime = [TimeSpan]::Zero
    )

    if ($ElapsedTime -lt [TimeSpan]::Zero)
    {
        $ElapsedTime = [TimeSpan]::Zero
    }

    $hours = [Math]::Floor($ElapsedTime.TotalHours)
    return "{0:00}:{1:00}:{2:00}" -f $hours, $ElapsedTime.Minutes, $ElapsedTime.Seconds
}

function Get-FindSubsetProgressPercent
{
    [cmdletbinding()]
    [outputtype([double])]
    param
    (
        [Parameter(Mandatory = $false)]
        [AllowNull()]
        [TraversalStatistics]$Statistics
    )

    if ($null -eq $Statistics)
    {
        return 0.0
    }

    $percent = $Statistics.PercentComplete()
    if ($percent -lt 0) { return 0.0 }
    if ($percent -gt 100) { return 100.0 }
    return $percent
}

function Get-FindSubsetProgressStatus
{
    [cmdletbinding()]
    [outputtype([string])]
    param
    (
        [Parameter(Mandatory = $false)]
        [AllowNull()]
        [TraversalStatistics]$Statistics,

        [Parameter(Mandatory = $true)]
        [int]$Iteration,

        [Parameter(Mandatory = $false)]
        [AllowNull()]
        [TimeSpan]$ElapsedTime = [TimeSpan]::Zero,

        [Parameter(Mandatory = $false)]
        [AllowEmptyString()]
        [string]$Phase = ""
    )

    $culture = [System.Globalization.CultureInfo]::InvariantCulture
    $percent = (Get-FindSubsetProgressPercent -Statistics $Statistics).ToString("0.##", $culture)
    $elapsed = Format-FindSubsetProgressElapsedTime -ElapsedTime $ElapsedTime

    $processed = 0
    $remaining = 0
    $completedOperations = 0
    $totalOperations = 0

    if ($null -ne $Statistics)
    {
        $processed = $Statistics.TotalRecordsProcessed
        $remaining = $Statistics.TotalRecordsRemaining
        $completedOperations = $Statistics.CompletedOperations
        $totalOperations = $Statistics.TotalOperations
    }

    $phasePrefix = ""
    if (-not [string]::IsNullOrWhiteSpace($Phase))
    {
        $phasePrefix = "$Phase | "
    }

    return "$phasePrefix$percent% | elapsed $elapsed | records $(Format-FindSubsetProgressNumber $processed) processed / $(Format-FindSubsetProgressNumber $remaining) remaining | ops $(Format-FindSubsetProgressNumber $completedOperations)/$(Format-FindSubsetProgressNumber $totalOperations) | iteration $Iteration"
}

function Get-FindSubsetProgressCurrentOperation
{
    [cmdletbinding()]
    [outputtype([string])]
    param
    (
        [Parameter(Mandatory = $true)]
        [TableInfo]$Table,

        [Parameter(Mandatory = $true)]
        [TraversalOperation]$Operation,

        [Parameter(Mandatory = $false)]
        [AllowEmptyString()]
        [string]$Phase = ""
    )

    $operationText = "$($Table.SchemaName).$($Table.TableName) | state $($Operation.State) | depth $($Operation.Depth) | operation records $(Format-FindSubsetProgressNumber $Operation.RecordsToProcess)"
    if ([string]::IsNullOrWhiteSpace($Phase))
    {
        return $operationText
    }

    return "$Phase | $operationText"
}
