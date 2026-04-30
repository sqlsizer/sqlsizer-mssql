function Test-SubsetGuardUserTable
{
    [CmdletBinding()]
    [OutputType([bool])]
    param
    (
        [Parameter(Mandatory = $true)]
        [TableInfo]$Table
    )

    if ($null -eq $Table.PrimaryKey -or $Table.PrimaryKey.Count -eq 0)
    {
        return $false
    }

    return -not $Table.SchemaName.StartsWith('SqlSizer')
}

function Get-SubsetGuardTableKey
{
    [CmdletBinding()]
    [OutputType([string])]
    param
    (
        [Parameter(Mandatory = $true)]
        [string]$SchemaName,

        [Parameter(Mandatory = $true)]
        [string]$TableName
    )

    return "$SchemaName, $TableName"
}

function Get-SubsetGuardTableMetrics
{
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param
    (
        [Parameter(Mandatory = $true)]
        [DatabaseInfo]$DatabaseInfo
    )

    $tables = @($DatabaseInfo.Tables | Where-Object { Test-SubsetGuardUserTable -Table $_ })
    $byKey = @{}
    $sourceRows = [long]0
    $missingStatistics = $false

    foreach ($table in $tables)
    {
        $key = Get-SubsetGuardTableKey -SchemaName $table.SchemaName -TableName $table.TableName
        $byKey[$key] = $table

        if ($null -eq $table.Statistics)
        {
            $missingStatistics = $true
            continue
        }

        $sourceRows += [long]$table.Statistics.Rows
    }

    return [pscustomobject]@{
        Tables            = $tables
        TablesByKey       = $byKey
        TotalTableCount   = [int]$tables.Count
        SourceRows        = $(if ($missingStatistics) { $null } else { $sourceRows })
        MissingStatistics = [bool]$missingStatistics
    }
}

function Test-SubsetGuardTableIgnored
{
    [CmdletBinding()]
    [OutputType([bool])]
    param
    (
        [Parameter(Mandatory = $true)]
        [string]$SchemaName,

        [Parameter(Mandatory = $true)]
        [string]$TableName,

        [Parameter(Mandatory = $false)]
        [TableInfo2[]]$IgnoredTables,

        [Parameter(Mandatory = $false)]
        [TraversalConfiguration]$TraversalConfiguration
    )

    if ([TableInfo2]::IsIgnored($SchemaName, $TableName, $IgnoredTables))
    {
        return $true
    }

    if ($TraversalConfiguration -and [TableInfo2]::IsIgnored($SchemaName, $TableName, $TraversalConfiguration.IgnoredTables))
    {
        return $true
    }

    return $false
}

function Get-SubsetGuardReachableTables
{
    [CmdletBinding()]
    [OutputType([string[]])]
    param
    (
        [Parameter(Mandatory = $true)]
        [DatabaseInfo]$DatabaseInfo,

        [Parameter(Mandatory = $false)]
        [object[]]$SeedStates = @(),

        [Parameter(Mandatory = $false)]
        [TableInfo2[]]$IgnoredTables,

        [Parameter(Mandatory = $false)]
        [TraversalConfiguration]$TraversalConfiguration,

        [Parameter(Mandatory = $false)]
        [bool]$FullSearch = $false
    )

    $metrics = Get-SubsetGuardTableMetrics -DatabaseInfo $DatabaseInfo
    $includedStates = [System.Collections.Generic.HashSet[int]]::new()
    foreach ($state in (Get-IncludedTraversalStateValues))
    {
        $null = $includedStates.Add([int]$state)
    }

    $reachable = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    $visitedDepthByState = @{}
    $queue = [System.Collections.Generic.Queue[object]]::new()

    foreach ($seed in $SeedStates)
    {
        $key = Get-SubsetGuardTableKey -SchemaName $seed.SchemaName -TableName $seed.TableName
        if (-not $metrics.TablesByKey.ContainsKey($key))
        {
            continue
        }

        $state = [TraversalState]([int]$seed.State)
        if ($includedStates.Contains([int]$state))
        {
            $null = $reachable.Add($key)
        }

        $stateKey = "$key|$([int]$state)"
        if ((-not $visitedDepthByState.ContainsKey($stateKey)) -or $visitedDepthByState[$stateKey] -gt 0)
        {
            $visitedDepthByState[$stateKey] = 0
            $queue.Enqueue([pscustomobject]@{
                Table = $metrics.TablesByKey[$key]
                State = $state
                Depth = 0
            })
        }
    }

    while ($queue.Count -gt 0)
    {
        $item = $queue.Dequeue()
        $table = [TableInfo]$item.Table
        $state = [TraversalState]$item.State
        $depth = [int]$item.Depth

        foreach ($direction in @([TraversalDirection]::Outgoing, [TraversalDirection]::Incoming))
        {
            if (-not (Test-ShouldTraverseDirection -State $state -Direction $direction -FullSearch $FullSearch))
            {
                continue
            }

            $relationships = if ($direction -eq [TraversalDirection]::Outgoing) {
                $table.ForeignKeys
            } else {
                $table.IsReferencedBy
            }

            foreach ($relationship in $relationships)
            {
                $fks = if ($direction -eq [TraversalDirection]::Incoming) {
                    $relationship.ForeignKeys | Where-Object {
                        ($_.Schema -eq $table.SchemaName) -and ($_.Table -eq $table.TableName)
                    }
                } else {
                    @($relationship)
                }

                foreach ($fk in $fks)
                {
                    $targetSchema = if ($direction -eq [TraversalDirection]::Outgoing) { $fk.Schema } else { $fk.FkSchema }
                    $targetTable = if ($direction -eq [TraversalDirection]::Outgoing) { $fk.Table } else { $fk.FkTable }

                    if (Test-SubsetGuardTableIgnored `
                            -SchemaName $targetSchema `
                            -TableName $targetTable `
                            -IgnoredTables $IgnoredTables `
                            -TraversalConfiguration $TraversalConfiguration)
                    {
                        continue
                    }

                    $constraints = Get-TraversalConstraints -Fk $fk -Direction $direction -TraversalConfiguration $TraversalConfiguration
                    if (($null -ne $constraints.MaxDepth) -and ($depth -ge $constraints.MaxDepth))
                    {
                        continue
                    }

                    if (-not (Test-TraversalConstraintsMatch `
                                -Constraints $constraints `
                                -SourceSchemaName $table.SchemaName `
                                -SourceTableName $table.TableName `
                                -ForeignKeyName $fk.Name))
                    {
                        continue
                    }

                    $newState = Get-NewTraversalState `
                        -Direction $direction `
                        -CurrentState $state `
                        -Fk $fk `
                        -TraversalConfiguration $TraversalConfiguration `
                        -FullSearch $FullSearch

                    if ($newState -eq [TraversalState]::Exclude)
                    {
                        continue
                    }

                    $targetKey = Get-SubsetGuardTableKey -SchemaName $targetSchema -TableName $targetTable
                    if (-not $metrics.TablesByKey.ContainsKey($targetKey))
                    {
                        continue
                    }

                    if ($includedStates.Contains([int]$newState))
                    {
                        $null = $reachable.Add($targetKey)
                    }

                    $targetStateKey = "$targetKey|$([int]$newState)"
                    $targetDepth = $depth + 1
                    if ((-not $visitedDepthByState.ContainsKey($targetStateKey)) -or $visitedDepthByState[$targetStateKey] -gt $targetDepth)
                    {
                        $visitedDepthByState[$targetStateKey] = $targetDepth
                        $queue.Enqueue([pscustomobject]@{
                            Table = $metrics.TablesByKey[$targetKey]
                            State = $newState
                            Depth = $targetDepth
                        })
                    }
                }
            }
        }
    }

    $result = foreach ($key in $reachable) { $key }
    return $result
}

function New-SubsetGuardPreflightResult
{
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param
    (
        [Parameter(Mandatory = $false)]
        [string[]]$ReachableTableKeys = @(),

        [Parameter(Mandatory = $true)]
        [pscustomobject]$TableMetrics,

        [Parameter(Mandatory = $true)]
        [double]$MaxReachableTablePercent
    )

    $enabled = $MaxReachableTablePercent -gt 0
    $reachableCount = @($ReachableTableKeys).Count
    $tablePercent = $null
    if ($TableMetrics.TotalTableCount -gt 0)
    {
        $tablePercent = [Math]::Round(100.0 * [double]$reachableCount / [double]$TableMetrics.TotalTableCount, 2)
    }

    $reachableRows = [long]0
    $reachableRowsAvailable = $true
    foreach ($key in $ReachableTableKeys)
    {
        if (-not $TableMetrics.TablesByKey.ContainsKey($key))
        {
            continue
        }

        $table = $TableMetrics.TablesByKey[$key]
        if ($null -eq $table.Statistics)
        {
            $reachableRowsAvailable = $false
            continue
        }

        $reachableRows += [long]$table.Statistics.Rows
    }

    $exceeded = $false
    if ($enabled -and $null -ne $tablePercent -and $tablePercent -gt $MaxReachableTablePercent)
    {
        $exceeded = $true
    }

    return [pscustomobject]@{
        Enabled                   = [bool]$enabled
        ThresholdPercent          = [double]$MaxReachableTablePercent
        TotalTableCount           = [int]$TableMetrics.TotalTableCount
        ReachableTableCount       = [int]$reachableCount
        ReachableTablePercent     = $tablePercent
        ReachableTables           = @($ReachableTableKeys)
        SourceRowsAvailable       = [bool](-not $TableMetrics.MissingStatistics)
        SourceRows                = $TableMetrics.SourceRows
        ReachableSourceRows       = $(if ($reachableRowsAvailable) { $reachableRows } else { $null })
        MissingStatistics         = [bool]$TableMetrics.MissingStatistics
        Exceeded                  = [bool]$exceeded
    }
}

function New-SubsetGuardRuntimeResult
{
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param
    (
        [Parameter(Mandatory = $true)]
        [long]$SubsetRows,

        [Parameter(Mandatory = $true)]
        [long]$SourceRows,

        [Parameter(Mandatory = $true)]
        [double]$MaxSubsetPercentOfSource,

        [Parameter(Mandatory = $false)]
        [object]$TopExpansion = $null,

        [Parameter(Mandatory = $false)]
        [int]$Iteration = -1,

        [Parameter(Mandatory = $false)]
        [string]$Phase = 'Runtime'
    )

    $enabled = $MaxSubsetPercentOfSource -gt 0
    $percent = $null
    if ($SourceRows -gt 0)
    {
        $percent = [Math]::Round(100.0 * [double]$SubsetRows / [double]$SourceRows, 2)
    }

    $exceeded = $false
    if ($enabled -and $null -ne $percent -and $percent -gt $MaxSubsetPercentOfSource)
    {
        $exceeded = $true
    }

    return [pscustomobject]@{
        Enabled             = [bool]$enabled
        ThresholdPercent    = [double]$MaxSubsetPercentOfSource
        SourceRows          = [long]$SourceRows
        SubsetRows          = [long]$SubsetRows
        PercentOfSourceRows = $percent
        Exceeded            = [bool]$exceeded
        Iteration           = [int]$Iteration
        Phase               = $Phase
        TopExpansion        = $TopExpansion
    }
}

function Get-SubsetGuardSeedStates
{
    [CmdletBinding()]
    [OutputType([object[]])]
    param
    (
        [Parameter(Mandatory = $true)]
        [string]$SessionId,

        [Parameter(Mandatory = $true)]
        [string]$Database,

        [Parameter(Mandatory = $true)]
        [DatabaseInfo]$DatabaseInfo,

        [Parameter(Mandatory = $true)]
        [SqlConnectionInfo]$ConnectionInfo,

        [Parameter(Mandatory = $true)]
        [Structure]$Structure,

        [Parameter(Mandatory = $false)]
        [int]$StartIteration = 0
    )

    $states = [System.Collections.Generic.List[object]]::new()

    foreach ($table in $DatabaseInfo.Tables)
    {
        if (-not (Test-SubsetGuardUserTable -Table $table))
        {
            continue
        }

        $signature = $Structure.Tables[$table]
        if ([string]::IsNullOrWhiteSpace($signature))
        {
            continue
        }

        $processing = ConvertTo-SqlMultipartIdentifier ($Structure.GetProcessingName($signature, $SessionId))
        $sql = "SELECT DISTINCT [State] FROM $processing WHERE [Iteration] >= $StartIteration"

        try
        {
            $rows = Invoke-SqlcmdEx -Sql $sql -Database $Database -ConnectionInfo $ConnectionInfo -Statistics $false
        }
        catch
        {
            continue
        }

        foreach ($row in @($rows))
        {
            if ($null -eq $row -or $null -eq $row.State)
            {
                continue
            }

            $states.Add([pscustomobject]@{
                SchemaName = $table.SchemaName
                TableName  = $table.TableName
                State      = [int]$row.State
            })
        }
    }

    return $states.ToArray()
}

function Get-SubsetGuardLiveSourceRows
{
    [CmdletBinding()]
    [OutputType([long])]
    param
    (
        [Parameter(Mandatory = $true)]
        [string]$Database,

        [Parameter(Mandatory = $true)]
        [SqlConnectionInfo]$ConnectionInfo
    )

    $sql = @"
SELECT ISNULL(SUM(p.[rows]), 0) AS SourceRows
FROM sys.tables t
INNER JOIN sys.schemas s ON t.schema_id = s.schema_id
INNER JOIN sys.partitions p ON t.object_id = p.object_id
WHERE p.index_id IN (0, 1)
    AND s.name NOT LIKE 'SqlSizer%'
    AND EXISTS (
        SELECT 1
        FROM sys.indexes i
        WHERE i.object_id = t.object_id
            AND i.is_primary_key = 1
    );
"@

    $row = Invoke-SqlcmdEx -Sql $sql -Database $Database -ConnectionInfo $ConnectionInfo -Statistics $false
    if ($null -eq $row -or $null -eq $row.SourceRows)
    {
        return 0
    }

    return [long]$row.SourceRows
}

function Get-SubsetGuardTopExpansion
{
    [CmdletBinding()]
    [OutputType([object])]
    param
    (
        [Parameter(Mandatory = $true)]
        [string]$SessionId,

        [Parameter(Mandatory = $true)]
        [string]$Database,

        [Parameter(Mandatory = $true)]
        [SqlConnectionInfo]$ConnectionInfo
    )

    $sessionIdLiteral = ConvertTo-SqlStringLiteral $SessionId
    $includedStates = Get-IncludedTraversalStateSqlList

    $sql = @"
SELECT TOP (1)
    target.[Schema] AS TargetSchemaName,
    target.TableName AS TargetTableName,
    source.[Schema] AS SourceSchemaName,
    source.TableName AS SourceTableName,
    fk.Name AS ForeignKeyName,
    SUM(ISNULL(o.ToProcess, 0)) AS RowsFound
FROM SqlSizer.Operations o
INNER JOIN SqlSizer.Tables target ON o.[Table] = target.Id
LEFT JOIN SqlSizer.Tables source ON o.[Source] = source.Id
LEFT JOIN SqlSizer.ForeignKeys fk ON o.Fk = fk.Id
WHERE o.SessionId = $sessionIdLiteral
    AND o.[State] IN ($includedStates)
    AND o.Fk IS NOT NULL
GROUP BY target.[Schema], target.TableName, source.[Schema], source.TableName, fk.Name
ORDER BY RowsFound DESC;
"@

    $row = Invoke-SqlcmdEx -Sql $sql -Database $Database -ConnectionInfo $ConnectionInfo -Statistics $false
    if ($null -eq $row -or $null -eq $row.RowsFound)
    {
        return $null
    }

    return [pscustomobject]@{
        TargetSchemaName = $row.TargetSchemaName
        TargetTableName  = $row.TargetTableName
        SourceSchemaName = $row.SourceSchemaName
        SourceTableName  = $row.SourceTableName
        ForeignKeyName   = $row.ForeignKeyName
        RowsFound        = [long]$row.RowsFound
    }
}

function Get-SubsetGuardSubsetRows
{
    [CmdletBinding()]
    [OutputType([long])]
    param
    (
        [Parameter(Mandatory = $true)]
        [string]$SessionId,

        [Parameter(Mandatory = $true)]
        [string]$Database,

        [Parameter(Mandatory = $true)]
        [DatabaseInfo]$DatabaseInfo,

        [Parameter(Mandatory = $true)]
        [SqlConnectionInfo]$ConnectionInfo
    )

    $subsetStats = Get-SubsetTableStatistics `
        -SessionId $SessionId `
        -Database $Database `
        -DatabaseInfo $DatabaseInfo `
        -ConnectionInfo $ConnectionInfo

    $sum = ($subsetStats | Measure-Object -Property RowCount -Sum).Sum
    if ($null -eq $sum)
    {
        return 0
    }

    return [long]$sum
}

function Write-SubsetGuardPreflightWarning
{
    [CmdletBinding()]
    param
    (
        [Parameter(Mandatory = $true)]
        [pscustomobject]$Preflight
    )

    if (-not $Preflight.Enabled -or -not $Preflight.Exceeded)
    {
        return
    }

    $message = "Subset size guard preflight: reachable table graph includes $($Preflight.ReachableTableCount) of $($Preflight.TotalTableCount) user tables ($($Preflight.ReachableTablePercent)%), exceeding threshold $($Preflight.ThresholdPercent)%."
    if ($Preflight.MissingStatistics)
    {
        $message += " Table row estimates are unavailable because DatabaseInfo is missing table statistics."
    }
    elseif ($null -ne $Preflight.ReachableSourceRows)
    {
        $message += " Reachable source row estimate: $($Preflight.ReachableSourceRows) of $($Preflight.SourceRows)."
    }

    Write-Warning $message
}

function Write-SubsetGuardRuntimeWarning
{
    [CmdletBinding()]
    param
    (
        [Parameter(Mandatory = $true)]
        [pscustomobject]$Runtime
    )

    if (-not $Runtime.Enabled -or -not $Runtime.Exceeded)
    {
        return
    }

    $message = "Subset size guard: subset has reached $($Runtime.SubsetRows) of $($Runtime.SourceRows) source rows ($($Runtime.PercentOfSourceRows)%), exceeding threshold $($Runtime.ThresholdPercent)%."
    if ($null -ne $Runtime.TopExpansion)
    {
        $top = $Runtime.TopExpansion
        $message += " Largest FK expansion: $($top.ForeignKeyName) from $($top.SourceSchemaName).$($top.SourceTableName) to $($top.TargetSchemaName).$($top.TargetTableName) ($($top.RowsFound) rows)."
    }

    Write-Warning $message
}

function Throw-SubsetGuardRuntimeError
{
    [CmdletBinding()]
    param
    (
        [Parameter(Mandatory = $true)]
        [pscustomobject]$Runtime
    )

    if (-not $Runtime.Enabled -or -not $Runtime.Exceeded)
    {
        return
    }

    $message = "Subset size guard exceeded: subset has reached $($Runtime.SubsetRows) of $($Runtime.SourceRows) source rows ($($Runtime.PercentOfSourceRows)%), exceeding threshold $($Runtime.ThresholdPercent)%."
    if ($null -ne $Runtime.TopExpansion)
    {
        $top = $Runtime.TopExpansion
        $message += " Largest FK expansion: $($top.ForeignKeyName) from $($top.SourceSchemaName).$($top.SourceTableName) to $($top.TargetSchemaName).$($top.TargetTableName) ($($top.RowsFound) rows)."
    }

    throw $message
}

function Invoke-SubsetGuardPreflight
{
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param
    (
        [Parameter(Mandatory = $true)]
        [string]$SessionId,

        [Parameter(Mandatory = $true)]
        [string]$Database,

        [Parameter(Mandatory = $true)]
        [DatabaseInfo]$DatabaseInfo,

        [Parameter(Mandatory = $true)]
        [SqlConnectionInfo]$ConnectionInfo,

        [Parameter(Mandatory = $true)]
        [Structure]$Structure,

        [Parameter(Mandatory = $false)]
        [int]$StartIteration = 0,

        [Parameter(Mandatory = $false)]
        [TableInfo2[]]$IgnoredTables,

        [Parameter(Mandatory = $false)]
        [TraversalConfiguration]$TraversalConfiguration,

        [Parameter(Mandatory = $false)]
        [bool]$FullSearch = $false,

        [Parameter(Mandatory = $true)]
        [double]$MaxReachableTablePercent
    )

    $metrics = Get-SubsetGuardTableMetrics -DatabaseInfo $DatabaseInfo
    $seedStates = Get-SubsetGuardSeedStates `
        -SessionId $SessionId `
        -Database $Database `
        -DatabaseInfo $DatabaseInfo `
        -ConnectionInfo $ConnectionInfo `
        -Structure $Structure `
        -StartIteration $StartIteration

    $reachableTables = Get-SubsetGuardReachableTables `
        -DatabaseInfo $DatabaseInfo `
        -SeedStates $seedStates `
        -IgnoredTables $IgnoredTables `
        -TraversalConfiguration $TraversalConfiguration `
        -FullSearch $FullSearch

    $preflight = New-SubsetGuardPreflightResult `
        -ReachableTableKeys $reachableTables `
        -TableMetrics $metrics `
        -MaxReachableTablePercent $MaxReachableTablePercent

    Write-SubsetGuardPreflightWarning -Preflight $preflight
    return $preflight
}

function Invoke-SubsetGuardRuntimeCheck
{
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param
    (
        [Parameter(Mandatory = $true)]
        [string]$SessionId,

        [Parameter(Mandatory = $true)]
        [string]$Database,

        [Parameter(Mandatory = $true)]
        [DatabaseInfo]$DatabaseInfo,

        [Parameter(Mandatory = $true)]
        [SqlConnectionInfo]$ConnectionInfo,

        [Parameter(Mandatory = $true)]
        [double]$MaxSubsetPercentOfSource,

        [Parameter(Mandatory = $false)]
        [int]$Iteration = -1,

        [Parameter(Mandatory = $false)]
        [string]$Phase = 'Runtime',

        [Parameter(Mandatory = $false)]
        [bool]$EmitWarning = $true,

        [Parameter(Mandatory = $false)]
        [bool]$ThrowOnExceeded = $false
    )

    $subsetRows = Get-SubsetGuardSubsetRows `
        -SessionId $SessionId `
        -Database $Database `
        -DatabaseInfo $DatabaseInfo `
        -ConnectionInfo $ConnectionInfo

    $sourceRows = Get-SubsetGuardLiveSourceRows -Database $Database -ConnectionInfo $ConnectionInfo
    $topExpansion = Get-SubsetGuardTopExpansion -SessionId $SessionId -Database $Database -ConnectionInfo $ConnectionInfo

    $runtime = New-SubsetGuardRuntimeResult `
        -SubsetRows $subsetRows `
        -SourceRows $sourceRows `
        -MaxSubsetPercentOfSource $MaxSubsetPercentOfSource `
        -TopExpansion $topExpansion `
        -Iteration $Iteration `
        -Phase $Phase

    if ($ThrowOnExceeded)
    {
        Throw-SubsetGuardRuntimeError -Runtime $runtime
    }
    elseif ($EmitWarning)
    {
        Write-SubsetGuardRuntimeWarning -Runtime $runtime
    }

    return $runtime
}

function New-SubsetGuardResult
{
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param
    (
        [Parameter(Mandatory = $false)]
        [object]$Preflight = $null,

        [Parameter(Mandatory = $false)]
        [object]$Runtime = $null
    )

    return [pscustomobject]@{
        Preflight = $Preflight
        Runtime   = $Runtime
    }
}

Export-ModuleMember -Function @(
    'Test-SubsetGuardUserTable',
    'Get-SubsetGuardTableKey',
    'Get-SubsetGuardTableMetrics',
    'Test-SubsetGuardTableIgnored',
    'Get-SubsetGuardReachableTables',
    'New-SubsetGuardPreflightResult',
    'New-SubsetGuardRuntimeResult',
    'Get-SubsetGuardSeedStates',
    'Get-SubsetGuardLiveSourceRows',
    'Get-SubsetGuardTopExpansion',
    'Get-SubsetGuardSubsetRows',
    'Write-SubsetGuardPreflightWarning',
    'Write-SubsetGuardRuntimeWarning',
    'Throw-SubsetGuardRuntimeError',
    'Invoke-SubsetGuardPreflight',
    'Invoke-SubsetGuardRuntimeCheck',
    'New-SubsetGuardResult'
)
