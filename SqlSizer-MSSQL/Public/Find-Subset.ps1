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

                $constraints = Get-TraversalConstraints -Fk $fk -Direction $Direction -TraversalConfiguration $TraversalConfiguration
                if (-not (Test-TraversalConstraintsMatch `
                    -Constraints $constraints `
                    -SourceSchemaName $Table.SchemaName `
                    -SourceTableName $Table.TableName `
                    -ForeignKeyName $fk.Name))
                {
                    continue
                }

                $newState = Get-NewTraversalState -Direction $Direction -CurrentState $State -Fk $fk -TraversalConfiguration $TraversalConfiguration -FullSearch $FullSearch
                
                # Skip traversal when StateOverride is Exclude
                if ($newState -eq [TraversalState]::Exclude)
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
                    -FullSearch $FullSearch

                $queryList.Add($query)
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

        Write-Progress -Activity "Finding subset $SessionId" `
                       -CurrentOperation "$($table.SchemaName).$($table.TableName) - State: $($Operation.State)" `
                       -PercentComplete $percentComplete

        # Check which directions to traverse
        $traverseOutgoing = Test-ShouldTraverseDirection -State $Operation.State -Direction ([TraversalDirection]::Outgoing) -FullSearch $FullSearch
        $traverseIncoming = Test-ShouldTraverseDirection -State $Operation.State -Direction ([TraversalDirection]::Incoming) -FullSearch $FullSearch

        # Collect queries for batched execution
        $batchedQueries = [System.Collections.Generic.List[string]]::new()

        # Build outgoing traversal query
        if ($traverseOutgoing)
        {
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
            $null = Invoke-SqlcmdEx -Sql $batchedSql -Database $Database -ConnectionInfo $ConnectionInfo
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

            $result = Invoke-SqlcmdEx -Sql $query -Database $Database -ConnectionInfo $ConnectionInfo
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
            [bool]$UseDfs
        )

        $query = New-GetNextOperationQuery -SessionId $SessionId -UseDfs $UseDfs

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

    function Set-OperationInProgress
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
        $query = New-MarkOperationInProgressQuery `
            -TableId $Operation.TableId `
            -State $state `
            -Depth $Operation.Depth `
            -SessionId $SessionId `
            -MaxBatchSize $MaxBatchSize

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

        $query = New-CompleteOperationsQuery -SessionId $SessionId -Iteration $Iteration

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

        $query = New-GetIterationStatisticsQuery -SessionId $SessionId

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
        Set-OperationInProgress -Operation $operation

        # Execute traversal
        Invoke-TraversalOperation -Operation $operation -Iteration $Iteration

        # Complete operations
        Complete-Operations -Iteration $Iteration

        return $true
    }

    #endregion

    #region Main Execution

    # Initialize metadata
    $structure = [Structure]::new($DatabaseInfo)
    $sqlSizerInfo = Get-SqlSizerInfo -Database $Database -ConnectionInfo $ConnectionInfo
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
            $null = Invoke-SqlcmdEx -Sql $resetSql -Database $Database -ConnectionInfo $ConnectionInfo
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
                -StartIteration $StartIteration

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
        $percentComplete = 0

        do
        {
            $hasMoreWork = Invoke-SearchIteration -Iteration $iteration

            # Update progress and checkpoint
            if (($iteration % $CheckpointInterval) -eq 0)
            {
                $stats = Get-IterationStatistics -Iteration $iteration -StartTime $startTime
                $percentComplete = $stats.PercentComplete()
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

        Write-Progress -Activity "Finding subset" -Completed

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
                -StartIteration $StartIteration

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
            $percentComplete = 0
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
