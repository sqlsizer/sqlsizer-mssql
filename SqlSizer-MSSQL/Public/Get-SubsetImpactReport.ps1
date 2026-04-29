function Get-SubsetImpactReport
{
    <#
    .SYNOPSIS
        Builds a read-only impact report for an existing SqlSizer subset session.

    .DESCRIPTION
        Summarizes the current subset session, including impacted tables, estimated data size,
        traversal operation progress, and reached/unreached foreign key relationships.
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
    $tableLookup = @{}
    foreach ($tableInfo in $DatabaseInfo.Tables)
    {
        $tableLookup["$($tableInfo.SchemaName), $($tableInfo.TableName)"] = $tableInfo
    }

    $subsetStats = Get-SubsetTableStatistics `
        -SessionId $SessionId `
        -Database $Database `
        -DatabaseInfo $DatabaseInfo `
        -ConnectionInfo $ConnectionInfo

    $subsetTables = @($subsetStats | Where-Object { $_.RowCount -gt 0 } | Sort-Object SchemaName, TableName)
    $tables = @()
    $totalRows = [long]0
    $sourceRowsTotal = [long]0
    $estimatedDataTotal = [double]0
    $hasEstimatedData = $false
    $missingStatistics = $false

    foreach ($subsetTable in $subsetTables)
    {
        $tableInfo = $tableLookup["$($subsetTable.SchemaName), $($subsetTable.TableName)"]
        $sourceRows = $null
        $percentOfSourceRows = $null
        $estimatedDataKB = $null
        $isHistoric = $false

        if ($null -ne $tableInfo)
        {
            $isHistoric = $tableInfo.IsHistoric

            if ($null -ne $tableInfo.Statistics)
            {
                $sourceRows = ConvertTo-SubsetImpactLong -Value $tableInfo.Statistics.Rows

                if (($null -ne $sourceRows) -and ($sourceRows -gt 0))
                {
                    $sourceRowsTotal += $sourceRows
                    $percentOfSourceRows = [Math]::Round(100.0 * [double]$subsetTable.RowCount / [double]$sourceRows, 2)

                    $dataKB = ConvertTo-SubsetImpactDouble -Value $tableInfo.Statistics.DataKB
                    if ($null -ne $dataKB)
                    {
                        $estimatedDataKB = [Math]::Round($dataKB * [double]$subsetTable.RowCount / [double]$sourceRows, 2)
                        $estimatedDataTotal += $estimatedDataKB
                        $hasEstimatedData = $true
                    }
                }
                elseif ($null -ne $sourceRows)
                {
                    $sourceRowsTotal += $sourceRows
                }
            }
            else
            {
                $missingStatistics = $true
            }
        }

        $totalRows += [long]$subsetTable.RowCount
        $tables += [pscustomobject]@{
            SchemaName          = $subsetTable.SchemaName
            TableName           = $subsetTable.TableName
            SubsetRows          = [long]$subsetTable.RowCount
            SourceRows          = $sourceRows
            PercentOfSourceRows = $percentOfSourceRows
            PrimaryKeySize      = [int]$subsetTable.PrimaryKeySize
            CanBeDeleted        = [bool]$subsetTable.CanBeDeleted
            IsHistoric          = [bool]$isHistoric
            EstimatedDataKB     = $estimatedDataKB
        }
    }

    if ($missingStatistics)
    {
        $warnings += 'DatabaseInfo does not include measured statistics for one or more subset tables. Run Get-DatabaseInfo with size measurement enabled for size estimates.'
    }

    if ($subsetTables.Count -eq 0)
    {
        $warnings += 'No subset rows were found for this session.'
    }

    $escapedSessionId = $SessionId.Replace("'", "''")
    $operationSummarySql = "SELECT
            COUNT(*) AS TotalOperations,
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
            COUNT(*) AS OperationCount,
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

    $percentOfSourceRows = $null
    if ($sourceRowsTotal -gt 0)
    {
        $percentOfSourceRows = [Math]::Round(100.0 * [double]$totalRows / [double]$sourceRowsTotal, 2)
    }

    $summary = [pscustomobject]@{
        Database              = $Database
        SessionId             = $SessionId
        GeneratedAt           = (Get-Date).ToString('o')
        TableCount            = [int]$subsetTables.Count
        TotalRows             = $totalRows
        SourceRows            = $sourceRowsTotal
        PercentOfSourceRows   = $percentOfSourceRows
        EstimatedDataKB       = $(if ($hasEstimatedData) { [Math]::Round($estimatedDataTotal, 2) } else { $null })
        RelationshipsReached  = [int]$relationships.Reached.Count
        RelationshipsUnreached = [int]$relationships.Unreached.Count
        OperationsComplete    = ($recordsRemaining -eq 0)
    }

    return New-SubsetImpactReportObject `
        -Summary $summary `
        -Tables $tables `
        -Relationships $relationships `
        -Operations $operations `
        -Warnings $warnings
}
