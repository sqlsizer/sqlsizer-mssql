function Get-SubsetImpactReport
{
    <#
    .SYNOPSIS
        Builds a read-only impact report for an existing SqlSizer subset session.

    .DESCRIPTION
        Summarizes the current subset session, including original database table row counts,
        subset rows, estimated data size, traversal operation progress, and reached/unreached foreign key relationships.
        The report does not include row samples or full row data.

    .PARAMETER SessionId
        SqlSizer session id returned by Start-SqlSizerSession.

    .PARAMETER Database
        Database containing the SqlSizer session.

    .PARAMETER DatabaseInfo
        Database metadata returned by Get-DatabaseInfo.

    .PARAMETER ConnectionInfo
        SQL Server connection information.

    .OUTPUTS
        PSCustomObject with Summary, Tables, Relationships, Operations, and Warnings.
    #>
    [cmdletbinding()]
    [outputtype([pscustomobject])]
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

    Test-SubsetImpactSessionId -SessionId $SessionId

    $warnings = @()

    $subsetStats = Get-SubsetTableStatistics `
        -SessionId $SessionId `
        -Database $Database `
        -DatabaseInfo $DatabaseInfo `
        -ConnectionInfo $ConnectionInfo

    $subsetTables = @($subsetStats | Where-Object { $_.RowCount -gt 0 } | Sort-Object SchemaName, TableName)
    $subsetStatsByKey = @{}
    foreach ($subsetStat in @($subsetStats))
    {
        $key = Get-SubsetImpactTableKey -SchemaName $subsetStat.SchemaName -TableName $subsetStat.TableName
        $subsetStatsByKey[$key] = $subsetStat
    }

    $originalRowCounts = Get-SubsetImpactOriginalTableRows `
        -Database $Database `
        -ConnectionInfo $ConnectionInfo

    $originalTables = @($DatabaseInfo.Tables | Where-Object { Test-SubsetImpactUserTable -Table $_ } | Sort-Object SchemaName, TableName)
    $tables = @()
    $totalRows = [long]0
    $originalRowsTotal = [long]0
    $estimatedDataTotal = [double]0
    $hasEstimatedData = $false
    $missingOriginalRows = $false
    $missingSizeStatistics = $false

    foreach ($tableInfo in $originalTables)
    {
        $key = Get-SubsetImpactTableKey -SchemaName $tableInfo.SchemaName -TableName $tableInfo.TableName
        $subsetTable = $null
        if ($subsetStatsByKey.ContainsKey($key))
        {
            $subsetTable = $subsetStatsByKey[$key]
        }

        $subsetRows = [long]0
        $primaryKeySize = 0
        if ($null -ne $tableInfo.PrimaryKey)
        {
            $primaryKeySize = [int]$tableInfo.PrimaryKey.Count
        }

        $canBeDeleted = ($tableInfo.IsHistoric -eq $false)
        if ($null -ne $subsetTable)
        {
            $subsetRows = ConvertTo-SubsetImpactLong -Value $subsetTable.RowCount
            if ($null -eq $subsetRows)
            {
                $subsetRows = 0
            }

            $primaryKeySize = [int]$subsetTable.PrimaryKeySize
            $canBeDeleted = [bool]$subsetTable.CanBeDeleted
        }

        $originalRows = $null
        $percentOfOriginalRows = $null
        $rowsExcluded = $null
        $percentRowsExcluded = $null
        $estimatedDataKB = $null

        if ($originalRowCounts.ContainsKey($key))
        {
            $originalRows = $originalRowCounts[$key]
        }
        elseif ($null -ne $tableInfo.Statistics)
        {
            $originalRows = ConvertTo-SubsetImpactLong -Value $tableInfo.Statistics.Rows
        }
        else
        {
            $missingOriginalRows = $true
        }

        if ($null -ne $originalRows)
        {
            $originalRowsTotal += $originalRows
            $rowsExcluded = $originalRows - $subsetRows

            if ($originalRows -gt 0)
            {
                $percentOfOriginalRows = [Math]::Round(100.0 * [double]$subsetRows / [double]$originalRows, 2)
                $percentRowsExcluded = [Math]::Round(100.0 * [double]$rowsExcluded / [double]$originalRows, 2)
            }
        }

        if ($null -ne $tableInfo.Statistics)
        {
            $dataKB = ConvertTo-SubsetImpactDouble -Value $tableInfo.Statistics.DataKB
            if (($null -ne $dataKB) -and ($null -ne $originalRows) -and ($originalRows -gt 0))
            {
                $estimatedDataKB = [Math]::Round($dataKB * [double]$subsetRows / [double]$originalRows, 2)
                if ($subsetRows -gt 0)
                {
                    $estimatedDataTotal += $estimatedDataKB
                    $hasEstimatedData = $true
                }
            }
        }
        elseif ($subsetRows -gt 0)
        {
            $missingSizeStatistics = $true
        }

        $totalRows += $subsetRows
        $tables += [pscustomobject]@{
            SchemaName            = $tableInfo.SchemaName
            TableName             = $tableInfo.TableName
            SubsetRows            = $subsetRows
            OriginalRows          = $originalRows
            SourceRows            = $originalRows
            RowsExcluded          = $rowsExcluded
            PercentOfOriginalRows = $percentOfOriginalRows
            PercentOfSourceRows   = $percentOfOriginalRows
            PercentRowsExcluded   = $percentRowsExcluded
            PrimaryKeySize        = $primaryKeySize
            CanBeDeleted          = [bool]$canBeDeleted
            IsHistoric            = [bool]$tableInfo.IsHistoric
            EstimatedDataKB       = $estimatedDataKB
        }
    }

    if ($missingOriginalRows)
    {
        $warnings += 'Original row counts were unavailable for one or more database tables.'
    }

    if ($missingSizeStatistics)
    {
        $warnings += 'DatabaseInfo does not include measured size statistics for one or more subset tables. Run Get-DatabaseInfo with size measurement enabled for size estimates.'
    }

    if ($subsetTables.Count -eq 0)
    {
        $warnings += 'No subset rows were found for this session.'
    }

    $escapedSessionId = $SessionId.Replace("'", "''")
    $operationSummarySql = "SELECT
            COUNT_BIG(*) AS TotalOperations,
            SUM(CASE WHEN Status = 1 THEN 1 ELSE 0 END) AS CompletedOperations,
            ISNULL(SUM(ISNULL(Processed, 0)), 0) AS TotalRecordsProcessed,
            ISNULL(SUM(ToProcess - ISNULL(Processed, 0)), 0) AS TotalRecordsRemaining,
            MAX(Depth) AS MaxDepthReached,
            MIN(Created) AS StartedAt,
            MAX(ISNULL(ProcessedDate, Created)) AS LastProcessedAt
        FROM SqlSizer.Operations
        WHERE SessionId = '$escapedSessionId'"

    $operationSummaryRow = Invoke-SqlcmdEx -Sql $operationSummarySql -Database $Database -ConnectionInfo $ConnectionInfo

    $totalOperations = ConvertTo-SubsetImpactLong -Value $operationSummaryRow.TotalOperations
    $completedOperations = ConvertTo-SubsetImpactLong -Value $operationSummaryRow.CompletedOperations
    $recordsProcessed = ConvertTo-SubsetImpactLong -Value $operationSummaryRow.TotalRecordsProcessed
    $recordsRemaining = ConvertTo-SubsetImpactLong -Value $operationSummaryRow.TotalRecordsRemaining
    $maxDepthReached = ConvertTo-SubsetImpactLong -Value $operationSummaryRow.MaxDepthReached

    if ($null -eq $totalOperations) { $totalOperations = 0 }
    if ($null -eq $completedOperations) { $completedOperations = 0 }
    if ($null -eq $recordsProcessed) { $recordsProcessed = 0 }
    if ($null -eq $recordsRemaining) { $recordsRemaining = 0 }

    if ($recordsRemaining -gt 0)
    {
        $warnings += "Traversal has $recordsRemaining records remaining in SqlSizer.Operations."
    }

    if ($totalOperations -eq 0)
    {
        $warnings += 'No traversal operations were found for this session.'
    }

    $operationBreakdownSql = "SELECT
            [State],
            [Depth],
            COUNT_BIG(*) AS OperationCount,
            ISNULL(SUM(ToProcess), 0) AS RecordsToProcess,
            ISNULL(SUM(ISNULL(Processed, 0)), 0) AS RecordsProcessed,
            ISNULL(SUM(ToProcess - ISNULL(Processed, 0)), 0) AS RecordsRemaining
        FROM SqlSizer.Operations
        WHERE SessionId = '$escapedSessionId'
        GROUP BY [State], [Depth]
        ORDER BY [Depth], [State]"

    $operationBreakdownRows = Invoke-SqlcmdEx -Sql $operationBreakdownSql -Database $Database -ConnectionInfo $ConnectionInfo
    $operationBreakdown = @()

    foreach ($row in $operationBreakdownRows)
    {
        $stateValue = [int]$row.State
        $stateName = ([TraversalState]$stateValue).ToString()
        $operationBreakdown += [pscustomobject]@{
            State            = $stateName
            StateValue       = $stateValue
            Depth            = [int]$row.Depth
            OperationCount   = [long]$row.OperationCount
            RecordsToProcess = [long]$row.RecordsToProcess
            RecordsProcessed = [long]$row.RecordsProcessed
            RecordsRemaining = [long]$row.RecordsRemaining
        }
    }

    $operations = [pscustomobject]@{
        Summary         = [pscustomobject]@{
            TotalOperations       = $totalOperations
            CompletedOperations   = $completedOperations
            TotalRecordsProcessed = $recordsProcessed
            TotalRecordsRemaining = $recordsRemaining
            MaxDepthReached       = $maxDepthReached
            StartedAt             = $operationSummaryRow.StartedAt
            LastProcessedAt       = $operationSummaryRow.LastProcessedAt
        }
        ByStateAndDepth = @($operationBreakdown)
    }

    $relationships = Get-SubsetRelationshipImpact `
        -SessionId $SessionId `
        -Database $Database `
        -DatabaseInfo $DatabaseInfo `
        -ConnectionInfo $ConnectionInfo

    $summaryOriginalRows = $null
    $summaryRowsExcluded = $null
    $percentOfOriginalRows = $null
    $percentRowsExcluded = $null

    if (-not $missingOriginalRows)
    {
        $summaryOriginalRows = $originalRowsTotal
        $summaryRowsExcluded = $originalRowsTotal - $totalRows

        if ($originalRowsTotal -gt 0)
        {
            $percentOfOriginalRows = [Math]::Round(100.0 * [double]$totalRows / [double]$originalRowsTotal, 2)
            $percentRowsExcluded = [Math]::Round(100.0 * [double]$summaryRowsExcluded / [double]$originalRowsTotal, 2)
        }
    }

    $summary = [pscustomobject]@{
        Database               = $Database
        SessionId              = $SessionId
        GeneratedAt            = (Get-Date).ToString('o')
        TableCount             = [int]$subsetTables.Count
        OriginalTableCount     = [int]$originalTables.Count
        TotalRows              = $totalRows
        OriginalRows           = $summaryOriginalRows
        SourceRows             = $summaryOriginalRows
        RowsExcluded           = $summaryRowsExcluded
        PercentOfOriginalRows  = $percentOfOriginalRows
        PercentOfSourceRows    = $percentOfOriginalRows
        PercentRowsExcluded    = $percentRowsExcluded
        EstimatedDataKB        = $(if ($hasEstimatedData) { [Math]::Round($estimatedDataTotal, 2) } else { $null })
        RelationshipsReached   = [int]$relationships.Reached.Count
        RelationshipsUnreached = [int]$relationships.Unreached.Count
        OperationsComplete     = ($recordsRemaining -eq 0)
    }

    return New-SubsetImpactReportObject `
        -Summary $summary `
        -Tables $tables `
        -Relationships $relationships `
        -Operations $operations `
        -Warnings $warnings
}
