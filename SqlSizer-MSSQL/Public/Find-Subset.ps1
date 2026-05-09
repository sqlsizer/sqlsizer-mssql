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

.PARAMETER CollectPerformanceProfile
    Collect per-phase SQL and PowerShell traversal-building timings. Disabled by default
    because profiling adds overhead. When enabled, the result includes PerformanceProfile.

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

.EXAMPLE
    # Collect phase timings and SQL logical reads while investigating a slow traversal
    $result = Find-Subset -Database "MyDB" -SessionId $sid -DatabaseInfo $info -ConnectionInfo $conn `
        -CollectPerformanceProfile $true -CollectSqlStatistics $true
    $result.PerformanceProfile.ByPhase | Sort-Object TotalElapsedMs -Descending | Format-Table
#>

function Get-FindSubsetPerformanceSampleValue
{
    [cmdletbinding()]
    param
    (
        [Parameter(Mandatory = $true)]
        [object]$Sample,

        [Parameter(Mandatory = $true)]
        [string]$Name,

        [Parameter(Mandatory = $false)]
        [object]$DefaultValue = 0
    )

    if ($null -eq $Sample)
    {
        return $DefaultValue
    }

    $property = $Sample.PSObject.Properties[$Name]
    if (($null -eq $property) -or ($null -eq $property.Value) -or ($property.Value -is [System.DBNull]))
    {
        return $DefaultValue
    }

    return $property.Value
}

function ConvertTo-FindSubsetPerformanceLong
{
    [cmdletbinding()]
    [outputtype([long])]
    param
    (
        [Parameter(Mandatory = $false)]
        [AllowNull()]
        [object]$Value
    )

    if (($null -eq $Value) -or ($Value -is [System.DBNull]))
    {
        return 0
    }

    return [Convert]::ToInt64($Value, [System.Globalization.CultureInfo]::InvariantCulture)
}

function ConvertTo-FindSubsetPerformanceDouble
{
    [cmdletbinding()]
    [outputtype([double])]
    param
    (
        [Parameter(Mandatory = $false)]
        [AllowNull()]
        [object]$Value
    )

    if (($null -eq $Value) -or ($Value -is [System.DBNull]))
    {
        return 0.0
    }

    return [Convert]::ToDouble($Value, [System.Globalization.CultureInfo]::InvariantCulture)
}

function New-FindSubsetPerformanceProfileCall
{
    [cmdletbinding()]
    [outputtype([pscustomobject])]
    param
    (
        [Parameter(Mandatory = $true)]
        [object]$Sample
    )

    return [pscustomobject]@{
        Category             = Get-FindSubsetPerformanceSampleValue -Sample $Sample -Name 'Category' -DefaultValue ''
        Phase                = Get-FindSubsetPerformanceSampleValue -Sample $Sample -Name 'Phase' -DefaultValue ''
        Iteration            = ConvertTo-FindSubsetPerformanceLong (Get-FindSubsetPerformanceSampleValue -Sample $Sample -Name 'Iteration' -DefaultValue 0)
        Table                = Get-FindSubsetPerformanceSampleValue -Sample $Sample -Name 'Table' -DefaultValue ''
        State                = Get-FindSubsetPerformanceSampleValue -Sample $Sample -Name 'State' -DefaultValue ''
        Depth                = ConvertTo-FindSubsetPerformanceLong (Get-FindSubsetPerformanceSampleValue -Sample $Sample -Name 'Depth' -DefaultValue 0)
        Direction            = Get-FindSubsetPerformanceSampleValue -Sample $Sample -Name 'Direction' -DefaultValue ''
        ElapsedMs            = [Math]::Round((ConvertTo-FindSubsetPerformanceDouble (Get-FindSubsetPerformanceSampleValue -Sample $Sample -Name 'ElapsedMs' -DefaultValue 0)), 2)
        LogicalReads         = ConvertTo-FindSubsetPerformanceLong (Get-FindSubsetPerformanceSampleValue -Sample $Sample -Name 'LogicalReads' -DefaultValue 0)
        SqlChars             = ConvertTo-FindSubsetPerformanceLong (Get-FindSubsetPerformanceSampleValue -Sample $Sample -Name 'SqlChars' -DefaultValue 0)
        RelationshipsVisited = ConvertTo-FindSubsetPerformanceLong (Get-FindSubsetPerformanceSampleValue -Sample $Sample -Name 'RelationshipsVisited' -DefaultValue 0)
        FksScanned           = ConvertTo-FindSubsetPerformanceLong (Get-FindSubsetPerformanceSampleValue -Sample $Sample -Name 'FksScanned' -DefaultValue 0)
        FksEmitted           = ConvertTo-FindSubsetPerformanceLong (Get-FindSubsetPerformanceSampleValue -Sample $Sample -Name 'FksEmitted' -DefaultValue 0)
        IgnoredChecks        = ConvertTo-FindSubsetPerformanceLong (Get-FindSubsetPerformanceSampleValue -Sample $Sample -Name 'IgnoredChecks' -DefaultValue 0)
        GeneratedQueryCount  = ConvertTo-FindSubsetPerformanceLong (Get-FindSubsetPerformanceSampleValue -Sample $Sample -Name 'GeneratedQueryCount' -DefaultValue 0)
        RuleBranchCalls      = ConvertTo-FindSubsetPerformanceLong (Get-FindSubsetPerformanceSampleValue -Sample $Sample -Name 'RuleBranchCalls' -DefaultValue 0)
        RuleBranchElapsedMs  = [Math]::Round((ConvertTo-FindSubsetPerformanceDouble (Get-FindSubsetPerformanceSampleValue -Sample $Sample -Name 'RuleBranchElapsedMs' -DefaultValue 0)), 2)
    }
}

function ConvertTo-FindSubsetPerformanceProfile
{
    [cmdletbinding()]
    [outputtype([pscustomobject])]
    param
    (
        [Parameter(Mandatory = $false)]
        [object[]]$Samples = @()
    )

    $samplesArray = @($Samples)
    $totalElapsedMs = [double]0
    $sqlElapsedMs = [double]0
    $powerShellElapsedMs = [double]0
    $logicalReads = [long]0
    $sqlChars = [long]0
    $sqlCalls = [long]0
    $powerShellCalls = [long]0

    foreach ($sample in $samplesArray)
    {
        $elapsed = ConvertTo-FindSubsetPerformanceDouble (Get-FindSubsetPerformanceSampleValue -Sample $sample -Name 'ElapsedMs' -DefaultValue 0)
        $category = Get-FindSubsetPerformanceSampleValue -Sample $sample -Name 'Category' -DefaultValue ''
        $totalElapsedMs += $elapsed
        $logicalReads += ConvertTo-FindSubsetPerformanceLong (Get-FindSubsetPerformanceSampleValue -Sample $sample -Name 'LogicalReads' -DefaultValue 0)
        $sqlChars += ConvertTo-FindSubsetPerformanceLong (Get-FindSubsetPerformanceSampleValue -Sample $sample -Name 'SqlChars' -DefaultValue 0)

        if ($category -eq 'SQL')
        {
            $sqlCalls += 1
            $sqlElapsedMs += $elapsed
        }
        elseif ($category -eq 'PowerShell')
        {
            $powerShellCalls += 1
            $powerShellElapsedMs += $elapsed
        }
    }

    $phaseGroups = $samplesArray | Group-Object -Property Category, Phase -AsHashTable -AsString
    if ($null -eq $phaseGroups)
    {
        $phaseGroups = @{}
    }

    $byPhase = @(
        foreach ($group in $phaseGroups.GetEnumerator())
        {
            $groupSamples = @($group.Value)
            if ($groupSamples.Count -eq 0)
            {
                continue
            }

            $first = $groupSamples[0]
            $elapsedValues = @($groupSamples | ForEach-Object { ConvertTo-FindSubsetPerformanceDouble (Get-FindSubsetPerformanceSampleValue -Sample $_ -Name 'ElapsedMs' -DefaultValue 0) })
            $elapsedTotal = ($elapsedValues | Measure-Object -Sum).Sum
            if ($null -eq $elapsedTotal) { $elapsedTotal = 0 }

            [pscustomobject]@{
                Category             = Get-FindSubsetPerformanceSampleValue -Sample $first -Name 'Category' -DefaultValue ''
                Phase                = Get-FindSubsetPerformanceSampleValue -Sample $first -Name 'Phase' -DefaultValue ''
                CallCount            = [int]$groupSamples.Count
                TotalElapsedMs       = [Math]::Round([double]$elapsedTotal, 2)
                AverageElapsedMs     = [Math]::Round(([double]$elapsedTotal / [Math]::Max(1, $groupSamples.Count)), 2)
                MaxElapsedMs         = [Math]::Round([double](($elapsedValues | Measure-Object -Maximum).Maximum), 2)
                TotalLogicalReads    = [long](($groupSamples | ForEach-Object { ConvertTo-FindSubsetPerformanceLong (Get-FindSubsetPerformanceSampleValue -Sample $_ -Name 'LogicalReads' -DefaultValue 0) } | Measure-Object -Sum).Sum)
                TotalSqlChars        = [long](($groupSamples | ForEach-Object { ConvertTo-FindSubsetPerformanceLong (Get-FindSubsetPerformanceSampleValue -Sample $_ -Name 'SqlChars' -DefaultValue 0) } | Measure-Object -Sum).Sum)
                RelationshipsVisited = [long](($groupSamples | ForEach-Object { ConvertTo-FindSubsetPerformanceLong (Get-FindSubsetPerformanceSampleValue -Sample $_ -Name 'RelationshipsVisited' -DefaultValue 0) } | Measure-Object -Sum).Sum)
                FksScanned           = [long](($groupSamples | ForEach-Object { ConvertTo-FindSubsetPerformanceLong (Get-FindSubsetPerformanceSampleValue -Sample $_ -Name 'FksScanned' -DefaultValue 0) } | Measure-Object -Sum).Sum)
                FksEmitted           = [long](($groupSamples | ForEach-Object { ConvertTo-FindSubsetPerformanceLong (Get-FindSubsetPerformanceSampleValue -Sample $_ -Name 'FksEmitted' -DefaultValue 0) } | Measure-Object -Sum).Sum)
                IgnoredChecks        = [long](($groupSamples | ForEach-Object { ConvertTo-FindSubsetPerformanceLong (Get-FindSubsetPerformanceSampleValue -Sample $_ -Name 'IgnoredChecks' -DefaultValue 0) } | Measure-Object -Sum).Sum)
                GeneratedQueryCount  = [long](($groupSamples | ForEach-Object { ConvertTo-FindSubsetPerformanceLong (Get-FindSubsetPerformanceSampleValue -Sample $_ -Name 'GeneratedQueryCount' -DefaultValue 0) } | Measure-Object -Sum).Sum)
                RuleBranchCalls      = [long](($groupSamples | ForEach-Object { ConvertTo-FindSubsetPerformanceLong (Get-FindSubsetPerformanceSampleValue -Sample $_ -Name 'RuleBranchCalls' -DefaultValue 0) } | Measure-Object -Sum).Sum)
                RuleBranchElapsedMs  = [Math]::Round([double](($groupSamples | ForEach-Object { ConvertTo-FindSubsetPerformanceDouble (Get-FindSubsetPerformanceSampleValue -Sample $_ -Name 'RuleBranchElapsedMs' -DefaultValue 0) } | Measure-Object -Sum).Sum), 2)
            }
        }
    ) | Sort-Object TotalElapsedMs -Descending

    return [pscustomobject]@{
        Summary                = [pscustomobject]@{
            TotalCalls               = [int]$samplesArray.Count
            TotalElapsedMs           = [Math]::Round($totalElapsedMs, 2)
            SqlCallCount             = [int]$sqlCalls
            SqlElapsedMs             = [Math]::Round($sqlElapsedMs, 2)
            PowerShellCallCount      = [int]$powerShellCalls
            PowerShellElapsedMs      = [Math]::Round($powerShellElapsedMs, 2)
            TotalLogicalReads        = $logicalReads
            TotalSqlChars            = $sqlChars
        }
        ByPhase                = @($byPhase)
        SlowestCalls           = @($samplesArray | Sort-Object { ConvertTo-FindSubsetPerformanceDouble (Get-FindSubsetPerformanceSampleValue -Sample $_ -Name 'ElapsedMs' -DefaultValue 0) } -Descending | Select-Object -First 20 | ForEach-Object { New-FindSubsetPerformanceProfileCall -Sample $_ })
        PowerShellBuildHotspots = @($samplesArray | Where-Object { (Get-FindSubsetPerformanceSampleValue -Sample $_ -Name 'Category' -DefaultValue '') -eq 'PowerShell' } | Sort-Object { ConvertTo-FindSubsetPerformanceDouble (Get-FindSubsetPerformanceSampleValue -Sample $_ -Name 'ElapsedMs' -DefaultValue 0) } -Descending | Select-Object -First 20 | ForEach-Object { New-FindSubsetPerformanceProfileCall -Sample $_ })
    }
}

function New-FindSubsetResultObject
{
    [cmdletbinding()]
    [outputtype([pscustomobject])]
    param
    (
        [Parameter(Mandatory = $true)]
        [bool]$Finished,

        [Parameter(Mandatory = $true)]
        [bool]$Initialized,

        [Parameter(Mandatory = $true)]
        [int]$CompletedIterations,

        [Parameter(Mandatory = $false)]
        [AllowNull()]
        [object]$SubsetSizeGuard,

        [Parameter(Mandatory = $false)]
        [bool]$IncludePerformanceProfile = $false,

        [Parameter(Mandatory = $false)]
        [AllowNull()]
        [object]$PerformanceProfile = $null
    )

    $result = [ordered]@{
        Finished            = $Finished
        Initialized         = $Initialized
        CompletedIterations = $CompletedIterations
        SubsetSizeGuard     = $SubsetSizeGuard
    }

    if ($IncludePerformanceProfile)
    {
        $result.PerformanceProfile = $PerformanceProfile
    }

    return [pscustomobject]$result
}

function New-FindSubsetIgnoredTableKeySet
{
    [cmdletbinding()]
    [outputtype([System.Collections.Generic.HashSet[string]])]
    param
    (
        [Parameter(Mandatory = $false)]
        [AllowNull()]
        [TableInfo2[]]$Tables
    )

    $keys = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($table in @($Tables))
    {
        if (($null -ne $table) -and (-not [string]::IsNullOrWhiteSpace($table.SchemaName)) -and (-not [string]::IsNullOrWhiteSpace($table.TableName)))
        {
            $null = $keys.Add("$($table.SchemaName), $($table.TableName)")
        }
    }

    return ,$keys
}

function New-FindSubsetIncomingForeignKeyLookup
{
    [cmdletbinding()]
    [outputtype([hashtable])]
    param
    (
        [Parameter(Mandatory = $true)]
        [DatabaseInfo]$DatabaseInfo
    )

    $lookup = @{}
    foreach ($table in @($DatabaseInfo.Tables))
    {
        foreach ($fk in @($table.ForeignKeys))
        {
            if ($null -eq $fk)
            {
                continue
            }

            $targetKey = "$($fk.Schema), $($fk.Table)"
            if (-not $lookup.ContainsKey($targetKey))
            {
                $lookup[$targetKey] = [System.Collections.Generic.List[TableFk]]::new()
            }

            $lookup[$targetKey].Add($fk)
        }
    }

    return $lookup
}

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
        [bool]$CollectPerformanceProfile = $false,

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

    $performanceSamples = [System.Collections.Generic.List[object]]::new()

    $ignoredTableKeys = New-FindSubsetIgnoredTableKeySet -Tables $IgnoredTables

    $configurationIgnoredTableKeys = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    if ($null -ne $TraversalConfiguration)
    {
        $configurationIgnoredTableKeys = New-FindSubsetIgnoredTableKeySet -Tables $TraversalConfiguration.IgnoredTables
    }

    $userTablesWithPrimaryKey = [System.Collections.Generic.List[TableInfo]]::new()
    foreach ($table in @($DatabaseInfo.Tables))
    {
        if (($null -ne $table.PrimaryKey) -and ($table.PrimaryKey.Count -gt 0) -and (-not $table.SchemaName.StartsWith('SqlSizer')))
        {
            $null = $userTablesWithPrimaryKey.Add($table)
        }
    }

    $incomingFksByTarget = New-FindSubsetIncomingForeignKeyLookup -DatabaseInfo $DatabaseInfo

    # O(1) table lookup hashtable - built at initialization
    $tablesByFullName = @{}
    foreach ($t in $DatabaseInfo.Tables) {
        $tablesByFullName["$($t.SchemaName), $($t.TableName)"] = $t
    }

    # Per-run caches for hot paths (Bottlenecks 3 and 4 in plan)
    $ruleBranchCache = @{}
    $cteQueryTemplateCache = @{}
    # Table-level cache for the full concatenated New-TraversalQuery output.
    # Within a single Find-Subset run only $Iteration changes between calls
    # for the same (Table, Direction, State), so the entire emitted SQL can
    # be memoized and rehydrated with one string Replace per call. This is
    # the dominant win for tables with many incoming FKs.
    $traversalQueryCache = @{}
    $ITER_TOKEN = '/*__SQLSIZER_ITER__*/'

    # Diagnostic counters for the table-level traversal cache. Emitted via
    # Write-Verbose at end of Find-Subset and surfaced on the result object
    # so callers can verify the cache is actually being hit without enabling
    # the full performance profile.
    $traversalCacheStats = [ordered]@{
        Hits          = [long]0
        Misses        = [long]0
        HitElapsedMs  = [double]0
        MissElapsedMs = [double]0
    }

    #region Helper Functions

    function Test-FindSubsetIgnoredTable
    {
        param
        (
            [Parameter(Mandatory = $true)]
            [string]$SchemaName,

            [Parameter(Mandatory = $true)]
            [string]$TableName
        )

        $key = "$SchemaName, $TableName"
        return $ignoredTableKeys.Contains($key) -or $configurationIgnoredTableKeys.Contains($key)
    }

    function Add-FindSubsetPerformanceSample
    {
        param
        (
            [Parameter(Mandatory = $true)]
            [string]$Category,

            [Parameter(Mandatory = $true)]
            [string]$Phase,

            [Parameter(Mandatory = $false)]
            [int]$Iteration = 0,

            [Parameter(Mandatory = $false)]
            [AllowNull()]
            [TraversalOperation]$Operation = $null,

            [Parameter(Mandatory = $false)]
            [AllowNull()]
            [TableInfo]$Table = $null,

            [Parameter(Mandatory = $false)]
            [string]$Direction = "",

            [Parameter(Mandatory = $false)]
            [double]$ElapsedMs = 0,

            [Parameter(Mandatory = $false)]
            [long]$LogicalReads = 0,

            [Parameter(Mandatory = $false)]
            [long]$SqlChars = 0,

            [Parameter(Mandatory = $false)]
            [long]$RelationshipsVisited = 0,

            [Parameter(Mandatory = $false)]
            [long]$FksScanned = 0,

            [Parameter(Mandatory = $false)]
            [long]$FksEmitted = 0,

            [Parameter(Mandatory = $false)]
            [long]$IgnoredChecks = 0,

            [Parameter(Mandatory = $false)]
            [long]$GeneratedQueryCount = 0,

            [Parameter(Mandatory = $false)]
            [long]$RuleBranchCalls = 0,

            [Parameter(Mandatory = $false)]
            [double]$RuleBranchElapsedMs = 0
        )

        if (-not $CollectPerformanceProfile)
        {
            return
        }

        $tableName = ""
        if ($null -ne $Table)
        {
            $tableName = "$($Table.SchemaName).$($Table.TableName)"
        }
        elseif ($null -ne $Operation)
        {
            $tableName = "$($Operation.TableSchema).$($Operation.TableName)"
        }

        $state = ""
        $depth = 0
        if ($null -ne $Operation)
        {
            $state = $Operation.State.ToString()
            $depth = $Operation.Depth
        }

        $performanceSamples.Add([pscustomobject]@{
            Category             = $Category
            Phase                = $Phase
            Iteration            = $Iteration
            Table                = $tableName
            State                = $state
            Depth                = $depth
            Direction            = $Direction
            ElapsedMs            = [Math]::Round($ElapsedMs, 2)
            LogicalReads         = $LogicalReads
            SqlChars             = $SqlChars
            RelationshipsVisited = $RelationshipsVisited
            FksScanned           = $FksScanned
            FksEmitted           = $FksEmitted
            IgnoredChecks        = $IgnoredChecks
            GeneratedQueryCount  = $GeneratedQueryCount
            RuleBranchCalls      = $RuleBranchCalls
            RuleBranchElapsedMs  = [Math]::Round($RuleBranchElapsedMs, 2)
        })
    }

    function Invoke-FindSubsetProfiledPowerShell
    {
        param
        (
            [Parameter(Mandatory = $true)]
            [string]$Phase,

            [Parameter(Mandatory = $true)]
            [int]$Iteration,

            [Parameter(Mandatory = $true)]
            [scriptblock]$ScriptBlock,

            [Parameter(Mandatory = $false)]
            [AllowNull()]
            [TraversalOperation]$Operation = $null,

            [Parameter(Mandatory = $false)]
            [AllowNull()]
            [TableInfo]$Table = $null
        )

        if (-not $CollectPerformanceProfile)
        {
            return & $ScriptBlock
        }

        $watch = [System.Diagnostics.Stopwatch]::StartNew()
        try
        {
            return & $ScriptBlock
        }
        finally
        {
            $watch.Stop()
            Add-FindSubsetPerformanceSample `
                -Category 'PowerShell' `
                -Phase $Phase `
                -Iteration $Iteration `
                -Operation $Operation `
                -Table $Table `
                -ElapsedMs $watch.Elapsed.TotalMilliseconds
        }
    }

    function New-FindSubsetResult
    {
        param
        (
            [Parameter(Mandatory = $true)]
            [bool]$Finished,

            [Parameter(Mandatory = $true)]
            [bool]$Initialized,

            [Parameter(Mandatory = $true)]
            [int]$CompletedIterations,

            [Parameter(Mandatory = $false)]
            [AllowNull()]
            [object]$SubsetSizeGuard
        )

        $profile = $null
        if ($CollectPerformanceProfile)
        {
            $profile = ConvertTo-FindSubsetPerformanceProfile -Samples $performanceSamples.ToArray()
        }

        $totalCalls = $traversalCacheStats.Hits + $traversalCacheStats.Misses
        if ($totalCalls -gt 0)
        {
            $hitPct = [Math]::Round(100 * $traversalCacheStats.Hits / $totalCalls, 1)
            $avgHitMs  = if ($traversalCacheStats.Hits -gt 0)   { [Math]::Round($traversalCacheStats.HitElapsedMs / $traversalCacheStats.Hits, 3) } else { 0 }
            $avgMissMs = if ($traversalCacheStats.Misses -gt 0) { [Math]::Round($traversalCacheStats.MissElapsedMs / $traversalCacheStats.Misses, 2) } else { 0 }
            Write-Verbose ("Traversal cache: {0} hits ({1}%), {2} misses; avg hit {3} ms, avg miss {4} ms; total hit time {5} ms, total miss time {6} ms" -f `
                $traversalCacheStats.Hits, $hitPct, $traversalCacheStats.Misses, `
                $avgHitMs, $avgMissMs, `
                [Math]::Round($traversalCacheStats.HitElapsedMs, 1), [Math]::Round($traversalCacheStats.MissElapsedMs, 1))
        }

        $result = New-FindSubsetResultObject `
            -Finished $Finished `
            -Initialized $Initialized `
            -CompletedIterations $CompletedIterations `
            -SubsetSizeGuard $SubsetSizeGuard `
            -IncludePerformanceProfile $CollectPerformanceProfile `
            -PerformanceProfile $profile

        # Attach cache diagnostics so callers can inspect without -Verbose.
        $result | Add-Member -NotePropertyName TraversalCacheStats -NotePropertyValue ([pscustomobject]$traversalCacheStats) -Force
        return $result
    }

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
            [TraversalOperation]$Operation = $null,
            [int]$Iteration
        )

        $buildWatch = [System.Diagnostics.Stopwatch]::StartNew()
        $directionText = $Direction.ToString()
        $relationshipsVisited = [long]0
        $fksScanned = [long]0
        $fksEmitted = [long]0
        $ignoredChecks = [long]0
        $generatedQueryCount = [long]0
        $ruleBranchCalls = [long]0
        $ruleBranchElapsedMs = [double]0
        $generatedSql = ""

        # Table-level cache check: the entire emitted SQL for a given
        # (Table, Direction, State) is identical across iterations except for
        # the iteration literal. On cache hit we skip the FK foreach entirely.
        $tableCacheKey = "$($Table.SchemaName)|$($Table.TableName)|$([int]$Direction)|$([int]$State)"
        if ($traversalQueryCache.ContainsKey($tableCacheKey))
        {
            $cachedTemplate = $traversalQueryCache[$tableCacheKey]
            $generatedSql = $cachedTemplate.Replace($ITER_TOKEN, [string]$Iteration)
            try
            {
                return $generatedSql
            }
            finally
            {
                $buildWatch.Stop()
                $traversalCacheStats.Hits += 1
                $traversalCacheStats.HitElapsedMs += $buildWatch.Elapsed.TotalMilliseconds
                Add-FindSubsetPerformanceSample `
                    -Category 'PowerShell' `
                    -Phase "Building $directionText traversal SQL (cache hit)" `
                    -Iteration $Iteration `
                    -Operation $Operation `
                    -Table $Table `
                    -Direction $directionText `
                    -ElapsedMs $buildWatch.Elapsed.TotalMilliseconds `
                    -SqlChars $generatedSql.Length
            }
        }

        $queryList = [System.Collections.Generic.List[string]]::new()
        $tableId = $tablesGroupedByName["$($Table.SchemaName), $($Table.TableName)"].Id
        $processing = $structure.GetProcessingName($structure.Tables[$Table], $SessionId)

        try
        {
            $fks = if ($Direction -eq [TraversalDirection]::Incoming) {
                $relationshipsVisited = [long]$Table.IsReferencedBy.Count
                $incomingKey = "$($Table.SchemaName), $($Table.TableName)"
                if ($incomingFksByTarget.ContainsKey($incomingKey))
                {
                    @($incomingFksByTarget[$incomingKey])
                }
                else
                {
                    @()
                }
            } else {
                $relationshipsVisited = [long]$Table.ForeignKeys.Count
                @($Table.ForeignKeys)
            }

            $fksScanned = [long](@($fks).Count)

            foreach ($fk in $fks)
            {
                $targetSchema = if ($Direction -eq [TraversalDirection]::Outgoing) { $fk.Schema } else { $fk.FkSchema }
                $targetTable = if ($Direction -eq [TraversalDirection]::Outgoing) { $fk.Table } else { $fk.FkTable }

                $ignoredChecks += 1
                if (Test-FindSubsetIgnoredTable -SchemaName $targetSchema -TableName $targetTable)
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

                $branchWatch = [System.Diagnostics.Stopwatch]::StartNew()
                try
                {
                    $branches = Get-TraversalRuleBranchesCached `
                        -Cache $ruleBranchCache `
                        -Direction $Direction `
                        -CurrentState $State `
                        -Fk $fk `
                        -SourceSchemaName $Table.SchemaName `
                        -SourceTableName $Table.TableName `
                        -ForeignKeyName $fk.Name `
                        -TraversalConfiguration $TraversalConfiguration `
                        -FullSearch $FullSearch
                }
                finally
                {
                    $branchWatch.Stop()
                    $ruleBranchCalls += 1
                    $ruleBranchElapsedMs += $branchWatch.Elapsed.TotalMilliseconds
                }

                $emittedForFk = $false
                foreach ($branch in $branches)
                {
                    $newState = [TraversalState]$branch.NewState
                    if ($newState -eq [TraversalState]::Exclude)
                    {
                        continue
                    }

                    # Memoize the CTE template by (FK, Direction, NewState, Constraints).
                    # Within a single Find-Subset run, only $Iteration changes between
                    # calls for the same tuple - so we cache the template with a token
                    # and substitute the iteration via a fast string Replace.
                    $constraintsKey = Get-ConstraintsCacheKey -Constraints $branch.Constraints
                    $cacheKey = "$fkId|$([int]$Direction)|$([int]$newState)|$constraintsKey"

                    if ($cteQueryTemplateCache.ContainsKey($cacheKey))
                    {
                        $template = $cteQueryTemplateCache[$cacheKey]
                    }
                    else
                    {
                        $template = New-CTETraversalQuery `
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
                            -Iteration 0 `
                            -SessionId $SessionId `
                            -MaxBatchSize $MaxBatchSize `
                            -FullSearch $FullSearch `
                            -IterationLiteral $ITER_TOKEN
                        $cteQueryTemplateCache[$cacheKey] = $template
                    }

                    # Keep the iteration token embedded so the joined output
                    # can be cached as a template and substituted just once.
                    $queryList.Add($template)
                    $generatedQueryCount += 1
                    $emittedForFk = $true
                }

                if ($emittedForFk)
                {
                    $fksEmitted += 1
                }
            }

            $joinedTemplate = ($queryList -join "`n")
            $traversalQueryCache[$tableCacheKey] = $joinedTemplate
            $generatedSql = $joinedTemplate.Replace($ITER_TOKEN, [string]$Iteration)
            if ($generatedSql.Contains($ITER_TOKEN))
            {
                throw "Iteration token '$ITER_TOKEN' was not substituted in concatenated traversal SQL"
            }
            return $generatedSql
        }
        finally
        {
            $buildWatch.Stop()
            $traversalCacheStats.Misses += 1
            $traversalCacheStats.MissElapsedMs += $buildWatch.Elapsed.TotalMilliseconds
            Add-FindSubsetPerformanceSample `
                -Category 'PowerShell' `
                -Phase "Building $directionText traversal SQL" `
                -Iteration $Iteration `
                -Operation $Operation `
                -Table $Table `
                -Direction $directionText `
                -ElapsedMs $buildWatch.Elapsed.TotalMilliseconds `
                -SqlChars $generatedSql.Length `
                -RelationshipsVisited $relationshipsVisited `
                -FksScanned $fksScanned `
                -FksEmitted $fksEmitted `
                -IgnoredChecks $ignoredChecks `
                -GeneratedQueryCount $generatedQueryCount `
                -RuleBranchCalls $ruleBranchCalls `
                -RuleBranchElapsedMs $ruleBranchElapsedMs
        }
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
                -Operation $Operation `
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
                -Operation $Operation `
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

        if ($userTablesWithPrimaryKey.Count -eq 0)
        {
            Write-Verbose "No user tables with primary keys; nothing to resolve"
            return
        }

        # Build one batched UPDATE wrapped in a shared @TotalExcluded accumulator
        # so we collapse N round-trips into a single SQL execution.
        $batchBuilder = [System.Text.StringBuilder]::new()
        [void]$batchBuilder.AppendLine("DECLARE @TotalExcluded BIGINT = 0;")
        foreach ($table in $userTablesWithPrimaryKey)
        {
            $signature = $structure.Tables[$table]
            $processing = $structure.GetProcessingName($signature, $SessionId)
            $updateSql = New-ExcludePendingQuery -ProcessingTable $processing -TableInfo $table -Bare
            [void]$batchBuilder.AppendLine($updateSql)
            [void]$batchBuilder.AppendLine("SET @TotalExcluded = @TotalExcluded + @@ROWCOUNT;")
        }
        [void]$batchBuilder.AppendLine("SELECT @TotalExcluded AS ExcludedCount;")

        $excludedCount = 0
        $result = Invoke-FindSubsetSql -Sql $batchBuilder.ToString() -Phase "Resolving pending states (batched)" -Iteration $Iteration
        if ($null -ne $result -and $null -ne $result.ExcludedCount)
        {
            $excludedCount = [long]$result.ExcludedCount
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

        if (($null -ne $Operation) -and ($null -ne $Table))
        {
            $progressState.LastOperation = $Operation
            $progressState.LastTable = $Table
        }
        $displayOperation = $progressState.LastOperation
        $displayTable = $progressState.LastTable

        $progressPercent = Get-FindSubsetProgressPercent -Statistics $stats
        $elapsedFormatted = Format-FindSubsetProgressElapsedTime -ElapsedTime $elapsed

        Write-Progress -Id 1 `
                       -Activity "Finding subset $SessionId" `
                       -Status "$Phase | elapsed $elapsedFormatted | iteration $Iteration" `
                       -PercentComplete ([int][Math]::Round($progressPercent))

        $statsStatus = Get-FindSubsetProgressStatus `
            -Statistics $stats `
            -Iteration $Iteration `
            -ElapsedTime $elapsed `
            -Phase ""
        Write-Progress -Id 2 -ParentId 1 `
                       -Activity "Records" `
                       -Status $statsStatus

        $operationStatus = if (($null -ne $displayOperation) -and ($null -ne $displayTable))
        {
            Get-FindSubsetProgressCurrentOperation -Table $displayTable -Operation $displayOperation -Phase $Phase
        }
        else
        {
            $Phase
        }
        Write-Progress -Id 3 -ParentId 1 `
                       -Activity "Last operation" `
                       -Status $operationStatus
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
            Add-FindSubsetPerformanceSample `
                -Category 'SQL' `
                -Phase $Phase `
                -Iteration $Iteration `
                -Operation $Operation `
                -Table $Table `
                -ElapsedMs $watch.Elapsed.TotalMilliseconds `
                -LogicalReads $logicalReads `
                -SqlChars $Sql.Length
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
                return New-FindSubsetResult `
                    -Finished $true `
                    -Initialized $true `
                    -CompletedIterations 0 `
                    -SubsetSizeGuard $null
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
            $null = Invoke-FindSubsetSql -Sql $resetSql -Phase "Resetting abandoned operations" -Iteration $StartIteration
        }
        else
        {
            $subsetGuardPreflight = Invoke-FindSubsetProfiledPowerShell `
                -Phase 'Preflight subset guard check' `
                -Iteration $StartIteration `
                -ScriptBlock {
                    Invoke-SubsetGuardPreflight `
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
                }

            # Normal start: initialize operations
            $null = Invoke-FindSubsetProfiledPowerShell `
                -Phase 'Initializing operations table' `
                -Iteration $StartIteration `
                -ScriptBlock {
                    Initialize-OperationsTable `
                        -SessionId $SessionId `
                        -Database $Database `
                        -ConnectionInfo $ConnectionInfo `
                        -DatabaseInfo $DatabaseInfo `
                        -StartIteration $StartIteration `
                        -Statistics $CollectSqlStatistics
                }

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
        $progressState = @{ LastOperation = $null; LastTable = $null }

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
                $subsetGuardRuntime = Invoke-FindSubsetProfiledPowerShell `
                    -Phase 'Runtime subset guard check' `
                    -Iteration $iteration `
                    -ScriptBlock {
                        Invoke-SubsetGuardRuntimeCheck `
                            -SessionId $SessionId `
                            -Database $Database `
                            -DatabaseInfo $DatabaseInfo `
                            -ConnectionInfo $ConnectionInfo `
                            -MaxSubsetPercentOfSource $MaxSubsetPercentOfSource `
                            -Iteration $iteration `
                            -Phase 'Runtime' `
                            -EmitWarning (-not $subsetGuardRuntimeWarningRaised) `
                            -ThrowOnExceeded $ThrowOnSubsetGuardExceeded
                    }

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

        $subsetGuardRuntime = Invoke-FindSubsetProfiledPowerShell `
            -Phase 'Final subset guard check' `
            -Iteration $iteration `
            -ScriptBlock {
                Invoke-SubsetGuardRuntimeCheck `
                    -SessionId $SessionId `
                    -Database $Database `
                    -DatabaseInfo $DatabaseInfo `
                    -ConnectionInfo $ConnectionInfo `
                    -MaxSubsetPercentOfSource $MaxSubsetPercentOfSource `
                    -Iteration $iteration `
                    -Phase 'Final' `
                    -EmitWarning (-not $subsetGuardRuntimeWarningRaised) `
                    -ThrowOnExceeded $ThrowOnSubsetGuardExceeded
            }

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

        Write-Progress -Id 1 -Activity "Finding subset $SessionId" -Completed
        Write-Progress -Id 2 -Activity "Records" -Completed
        Write-Progress -Id 3 -Activity "Last operation" -Completed

        return New-FindSubsetResult `
            -Finished $true `
            -Initialized $true `
            -CompletedIterations ($iteration - $StartIteration) `
            -SubsetSizeGuard (New-SubsetGuardResult -Preflight $subsetGuardPreflight -Runtime $subsetGuardRuntime)
    }
    else
    {
        # Interactive mode: one iteration at a time
        if ($Iteration -eq 0)
        {
            $subsetGuardPreflight = Invoke-FindSubsetProfiledPowerShell `
                -Phase 'Preflight subset guard check' `
                -Iteration $Iteration `
                -ScriptBlock {
                    Invoke-SubsetGuardPreflight `
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
                }

            $null = Invoke-FindSubsetProfiledPowerShell `
                -Phase 'Initializing operations table' `
                -Iteration $Iteration `
                -ScriptBlock {
                    Initialize-OperationsTable `
                        -SessionId $SessionId `
                        -Database $Database `
                        -ConnectionInfo $ConnectionInfo `
                        -DatabaseInfo $DatabaseInfo `
                        -StartIteration $StartIteration `
                        -Statistics $CollectSqlStatistics
                }

            return New-FindSubsetResult `
                -Finished $false `
                -Initialized $true `
                -CompletedIterations 1 `
                -SubsetSizeGuard (New-SubsetGuardResult -Preflight $subsetGuardPreflight -Runtime $null)
        }
        else
        {
            $startTime = Get-Date
            $progressStats = Get-IterationStatistics -Iteration $Iteration -StartTime $startTime
            $progressState = @{ LastOperation = $null; LastTable = $null }
            $hasMoreWork = Invoke-SearchIteration -Iteration $Iteration

            # Resolve Pending states when traversal is complete
            if (-not $hasMoreWork -and -not $FullSearch)
            {
                Resolve-PendingStates -Iteration $Iteration
            }

            if (-not $hasMoreWork)
            {
                $subsetGuardRuntime = Invoke-FindSubsetProfiledPowerShell `
                    -Phase 'Final subset guard check' `
                    -Iteration $Iteration `
                    -ScriptBlock {
                        Invoke-SubsetGuardRuntimeCheck `
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
            }

            return New-FindSubsetResult `
                -Finished (-not $hasMoreWork) `
                -Initialized $true `
                -CompletedIterations 1 `
                -SubsetSizeGuard $(if (-not $hasMoreWork) { New-SubsetGuardResult -Preflight $null -Runtime $subsetGuardRuntime } else { $null })
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
