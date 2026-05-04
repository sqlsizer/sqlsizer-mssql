function Test-SubsetImpactSessionId
{
    [cmdletbinding()]
    param
    (
        [Parameter(Mandatory = $true)]
        [string]$SessionId
    )

    if ($SessionId -notmatch '^[A-Za-z0-9_]+$')
    {
        throw "SessionId '$SessionId' contains characters that cannot be used in SqlSizer session object names."
    }
}

function ConvertTo-SubsetImpactLong
{
    param
    (
        [Parameter(Mandatory = $false)]
        $Value
    )

    if (($null -eq $Value) -or ($Value -is [System.DBNull]))
    {
        return $null
    }

    return [long]$Value
}

function ConvertTo-SubsetImpactDouble
{
    param
    (
        [Parameter(Mandatory = $false)]
        $Value
    )

    if (($null -eq $Value) -or ($Value -is [System.DBNull]))
    {
        return $null
    }

    return [double]$Value
}

function Get-SubsetImpactTableKey
{
    param
    (
        [Parameter(Mandatory = $true)]
        [string]$SchemaName,

        [Parameter(Mandatory = $true)]
        [string]$TableName
    )

    return "$SchemaName, $TableName"
}

function Test-SubsetImpactUserTable
{
    param
    (
        [Parameter(Mandatory = $true)]
        [TableInfo]$Table
    )

    if (($null -eq $Table.SchemaName) -or ($Table.SchemaName.StartsWith('SqlSizer')))
    {
        return $false
    }

    return $true
}

function Get-SubsetImpactOriginalTableRows
{
    [cmdletbinding()]
    [outputtype([hashtable])]
    param
    (
        [Parameter(Mandatory = $true)]
        [string]$Database,

        [Parameter(Mandatory = $true)]
        [SqlConnectionInfo]$ConnectionInfo
    )

    $sql = @"
SELECT s.[name] AS SchemaName,
       t.[name] AS TableName,
       ISNULL(SUM(CASE WHEN p.index_id IN (0, 1) THEN p.[rows] ELSE 0 END), 0) AS OriginalRows
FROM sys.tables t
INNER JOIN sys.schemas s ON s.schema_id = t.schema_id
LEFT JOIN sys.partitions p ON p.object_id = t.object_id
WHERE s.[name] NOT LIKE 'SqlSizer%'
GROUP BY s.[name], t.[name]
ORDER BY s.[name], t.[name];
"@

    $result = @{}
    $rows = Invoke-SqlcmdEx -Sql $sql -Database $Database -ConnectionInfo $ConnectionInfo -Statistics $false

    foreach ($row in @($rows))
    {
        if (($null -eq $row) -or ($null -eq $row.SchemaName) -or ($null -eq $row.TableName))
        {
            continue
        }

        $key = Get-SubsetImpactTableKey -SchemaName $row.SchemaName -TableName $row.TableName
        $result[$key] = ConvertTo-SubsetImpactLong -Value $row.OriginalRows
    }

    return $result
}

function New-SubsetImpactReportObject
{
    [cmdletbinding()]
    param
    (
        [Parameter(Mandatory = $true)]
        [pscustomobject]$Summary,

        [Parameter(Mandatory = $false)]
        [object[]]$Tables = @(),

        [Parameter(Mandatory = $true)]
        [pscustomobject]$Relationships,

        [Parameter(Mandatory = $true)]
        [pscustomobject]$Operations,

        [Parameter(Mandatory = $false)]
        [string[]]$Warnings = @()
    )

    return [pscustomobject]@{
        Summary       = $Summary
        Tables        = @($Tables)
        Relationships = $Relationships
        Operations    = $Operations
        Warnings      = @($Warnings)
    }
}

function Get-SubsetRelationshipImpact
{
    [cmdletbinding()]
    param
    (
        [Parameter(Mandatory = $true)]
        [string]$SessionId,

        [Parameter(Mandatory = $true)]
        [string]$Database,

        [Parameter(Mandatory = $true)]
        $DatabaseInfo,

        [Parameter(Mandatory = $true)]
        $ConnectionInfo
    )

    Test-SubsetImpactSessionId -SessionId $SessionId

    $structure = [Structure]::new($DatabaseInfo)
    $reachedIds = New-Object 'System.Collections.Generic.HashSet[int]'

    foreach ($table in $DatabaseInfo.Tables)
    {
        if (($table.PrimaryKey.Count -eq 0) -or ($table.SchemaName.StartsWith('SqlSizer')))
        {
            continue
        }

        if (-not $structure.Tables.ContainsKey($table))
        {
            continue
        }

        $processing = $structure.GetProcessingName($structure.Tables[$table], $SessionId)
        $sql = "SELECT DISTINCT [Fk] FROM $processing WHERE [Fk] IS NOT NULL"
        $rows = Invoke-SqlcmdEx -Sql $sql -Database $Database -ConnectionInfo $ConnectionInfo

        foreach ($row in $rows)
        {
            if (($null -ne $row.Fk) -and ($row.Fk -isnot [System.DBNull]))
            {
                $null = $reachedIds.Add([int]$row.Fk)
            }
        }
    }

    $sql = "SELECT f.[Id],
                   f.[Name],
                   child.[Schema] AS FkSchema,
                   child.[TableName] AS FkTable,
                   parent.[Schema] AS SchemaName,
                   parent.[TableName] AS TableName
            FROM SqlSizer.ForeignKeys f
            INNER JOIN SqlSizer.Tables child ON child.Id = f.FkTableId
            INNER JOIN SqlSizer.Tables parent ON parent.Id = f.TableId
            ORDER BY child.[Schema], child.[TableName], f.[Name]"

    $fkRows = Invoke-SqlcmdEx -Sql $sql -Database $Database -ConnectionInfo $ConnectionInfo
    $all = @()
    $reached = @()
    $unreached = @()

    foreach ($row in $fkRows)
    {
        $isReached = $reachedIds.Contains([int]$row.Id)
        $relationship = [pscustomobject]@{
            Id         = [int]$row.Id
            Name       = $row.Name
            FromSchema = $row.FkSchema
            FromTable  = $row.FkTable
            ToSchema   = $row.SchemaName
            ToTable    = $row.TableName
            IsReached  = $isReached
        }

        $all += $relationship

        if ($isReached)
        {
            $reached += $relationship
        }
        else
        {
            $unreached += $relationship
        }
    }

    return [pscustomobject]@{
        Reached   = @($reached)
        Unreached = @($unreached)
        All       = @($all)
    }
}

function Format-SubsetImpactValue
{
    param
    (
        [Parameter(Mandatory = $false)]
        $Value
    )

    if (($null -eq $Value) -or ($Value -is [System.DBNull]))
    {
        return ''
    }

    if ($Value -is [bool])
    {
        return $Value.ToString()
    }

    return [string]$Value
}

function Format-SubsetImpactMarkdownValue
{
    param
    (
        [Parameter(Mandatory = $false)]
        $Value
    )

    $text = Format-SubsetImpactValue -Value $Value
    return $text.Replace('|', '\|').Replace("`r", ' ').Replace("`n", ' ')
}

function Format-SubsetImpactHtmlValue
{
    param
    (
        [Parameter(Mandatory = $false)]
        $Value
    )

    $text = Format-SubsetImpactValue -Value $Value
    return [System.Net.WebUtility]::HtmlEncode($text)
}

function Format-SubsetImpactTableName
{
    param
    (
        [Parameter(Mandatory = $true)]
        [string]$Schema,

        [Parameter(Mandatory = $true)]
        [string]$Table
    )

    return "$Schema.$Table"
}

function ConvertTo-SubsetImpactReportMarkdown
{
    [cmdletbinding()]
    [OutputType([string])]
    param
    (
        [Parameter(Mandatory = $true)]
        [pscustomobject]$Report
    )

    $lines = [System.Collections.Generic.List[string]]::new()
    $summaryOriginalRows = $Report.Summary.OriginalRows
    if ($null -eq $summaryOriginalRows) { $summaryOriginalRows = $Report.Summary.SourceRows }

    $summaryPercentOfOriginalRows = $Report.Summary.PercentOfOriginalRows
    if ($null -eq $summaryPercentOfOriginalRows) { $summaryPercentOfOriginalRows = $Report.Summary.PercentOfSourceRows }

    $lines.Add('# SqlSizer Subset Impact Report')
    $lines.Add('')
    $lines.Add('## Summary')
    $lines.Add('| Metric | Value |')
    $lines.Add('|---|---|')
    $lines.Add("| Database | $(Format-SubsetImpactMarkdownValue $Report.Summary.Database) |")
    $lines.Add("| Session | $(Format-SubsetImpactMarkdownValue $Report.Summary.SessionId) |")
    $lines.Add("| Generated | $(Format-SubsetImpactMarkdownValue $Report.Summary.GeneratedAt) |")
    $lines.Add("| Subset tables | $(Format-SubsetImpactMarkdownValue $Report.Summary.TableCount) |")
    $lines.Add("| Original tables | $(Format-SubsetImpactMarkdownValue $Report.Summary.OriginalTableCount) |")
    $lines.Add("| Subset rows | $(Format-SubsetImpactMarkdownValue $Report.Summary.TotalRows) |")
    $lines.Add("| Original rows | $(Format-SubsetImpactMarkdownValue $summaryOriginalRows) |")
    $lines.Add("| Percent of original rows | $(Format-SubsetImpactMarkdownValue $summaryPercentOfOriginalRows) |")
    $lines.Add("| Rows excluded | $(Format-SubsetImpactMarkdownValue $Report.Summary.RowsExcluded) |")
    $lines.Add("| Percent rows excluded | $(Format-SubsetImpactMarkdownValue $Report.Summary.PercentRowsExcluded) |")
    $lines.Add("| Estimated data KB | $(Format-SubsetImpactMarkdownValue $Report.Summary.EstimatedDataKB) |")
    $lines.Add("| Operations complete | $(Format-SubsetImpactMarkdownValue $Report.Summary.OperationsComplete) |")
    $lines.Add('')

    $lines.Add('## Tables')
    $lines.Add('| Table | Subset Rows | Original Rows | Rows Excluded | % Original | % Rows Excluded | Estimated Data KB | PK Size | Deletable | Historic |')
    $lines.Add('|---|---:|---:|---:|---:|---:|---:|---:|---|---|')
    foreach ($table in $Report.Tables)
    {
        $name = Format-SubsetImpactTableName -Schema $table.SchemaName -Table $table.TableName
        $originalRows = $table.OriginalRows
        if ($null -eq $originalRows) { $originalRows = $table.SourceRows }

        $percentOfOriginalRows = $table.PercentOfOriginalRows
        if ($null -eq $percentOfOriginalRows) { $percentOfOriginalRows = $table.PercentOfSourceRows }

        $lines.Add("| $(Format-SubsetImpactMarkdownValue $name) | $(Format-SubsetImpactMarkdownValue $table.SubsetRows) | $(Format-SubsetImpactMarkdownValue $originalRows) | $(Format-SubsetImpactMarkdownValue $table.RowsExcluded) | $(Format-SubsetImpactMarkdownValue $percentOfOriginalRows) | $(Format-SubsetImpactMarkdownValue $table.PercentRowsExcluded) | $(Format-SubsetImpactMarkdownValue $table.EstimatedDataKB) | $(Format-SubsetImpactMarkdownValue $table.PrimaryKeySize) | $(Format-SubsetImpactMarkdownValue $table.CanBeDeleted) | $(Format-SubsetImpactMarkdownValue $table.IsHistoric) |")
    }
    if ($Report.Tables.Count -eq 0)
    {
        $lines.Add('| _(none)_ |  |  |  |  |  |  |  |  |  |')
    }
    $lines.Add('')

    $lines.Add('## Relationships')
    $lines.Add('')
    $lines.Add('### Reached')
    $lines.Add('| Foreign Key | From | To |')
    $lines.Add('|---|---|---|')
    foreach ($relationship in $Report.Relationships.Reached)
    {
        $from = Format-SubsetImpactTableName -Schema $relationship.FromSchema -Table $relationship.FromTable
        $to = Format-SubsetImpactTableName -Schema $relationship.ToSchema -Table $relationship.ToTable
        $lines.Add("| $(Format-SubsetImpactMarkdownValue $relationship.Name) | $(Format-SubsetImpactMarkdownValue $from) | $(Format-SubsetImpactMarkdownValue $to) |")
    }
    if ($Report.Relationships.Reached.Count -eq 0)
    {
        $lines.Add('| _(none)_ |  |  |')
    }
    $lines.Add('')
    $lines.Add('### Unreached')
    $lines.Add('| Foreign Key | From | To |')
    $lines.Add('|---|---|---|')
    foreach ($relationship in $Report.Relationships.Unreached)
    {
        $from = Format-SubsetImpactTableName -Schema $relationship.FromSchema -Table $relationship.FromTable
        $to = Format-SubsetImpactTableName -Schema $relationship.ToSchema -Table $relationship.ToTable
        $lines.Add("| $(Format-SubsetImpactMarkdownValue $relationship.Name) | $(Format-SubsetImpactMarkdownValue $from) | $(Format-SubsetImpactMarkdownValue $to) |")
    }
    if ($Report.Relationships.Unreached.Count -eq 0)
    {
        $lines.Add('| _(none)_ |  |  |')
    }
    $lines.Add('')

    $lines.Add('## Operations')
    $lines.Add('| State | Depth | Operations | To Process | Processed | Remaining |')
    $lines.Add('|---|---:|---:|---:|---:|---:|')
    foreach ($operation in $Report.Operations.ByStateAndDepth)
    {
        $lines.Add("| $(Format-SubsetImpactMarkdownValue $operation.State) | $(Format-SubsetImpactMarkdownValue $operation.Depth) | $(Format-SubsetImpactMarkdownValue $operation.OperationCount) | $(Format-SubsetImpactMarkdownValue $operation.RecordsToProcess) | $(Format-SubsetImpactMarkdownValue $operation.RecordsProcessed) | $(Format-SubsetImpactMarkdownValue $operation.RecordsRemaining) |")
    }
    if ($Report.Operations.ByStateAndDepth.Count -eq 0)
    {
        $lines.Add('| _(none)_ |  |  |  |  |  |')
    }
    $lines.Add('')

    if ($Report.Warnings.Count -gt 0)
    {
        $lines.Add('## Warnings')
        foreach ($warning in $Report.Warnings)
        {
            $lines.Add("- $(Format-SubsetImpactMarkdownValue $warning)")
        }
        $lines.Add('')
    }

    return ($lines -join [Environment]::NewLine)
}

function ConvertTo-SubsetImpactReportHtml
{
    [cmdletbinding()]
    [OutputType([string])]
    param
    (
        [Parameter(Mandatory = $true)]
        [pscustomobject]$Report
    )

    $lines = [System.Collections.Generic.List[string]]::new()
    $summaryOriginalRows = $Report.Summary.OriginalRows
    if ($null -eq $summaryOriginalRows) { $summaryOriginalRows = $Report.Summary.SourceRows }

    $summaryPercentOfOriginalRows = $Report.Summary.PercentOfOriginalRows
    if ($null -eq $summaryPercentOfOriginalRows) { $summaryPercentOfOriginalRows = $Report.Summary.PercentOfSourceRows }

    $lines.Add('<!doctype html>')
    $lines.Add('<html lang="en">')
    $lines.Add('<head>')
    $lines.Add('<meta charset="utf-8">')
    $lines.Add('<meta name="viewport" content="width=device-width, initial-scale=1">')
    $lines.Add('<title>SqlSizer Subset Impact Report</title>')
    $lines.Add('<style>')
    $lines.Add('body{font-family:Segoe UI,Arial,sans-serif;margin:32px;color:#1f2933;background:#fff;}')
    $lines.Add('h1{font-size:28px;margin:0 0 24px;}h2{font-size:20px;margin:28px 0 12px;}h3{font-size:16px;margin:22px 0 10px;}')
    $lines.Add('table{border-collapse:collapse;width:100%;margin:0 0 18px;}th,td{border:1px solid #d8dee4;padding:7px 9px;text-align:left;font-size:13px;}th{background:#f3f6f8;}td.num{text-align:right;}')
    $lines.Add('.summary{max-width:820px}.warning{background:#fff8dc;border:1px solid #e6d28a;padding:10px 12px;margin:8px 0;}')
    $lines.Add('</style>')
    $lines.Add('</head>')
    $lines.Add('<body>')
    $lines.Add('<h1>SqlSizer Subset Impact Report</h1>')

    $lines.Add('<h2>Summary</h2>')
    $lines.Add('<table class="summary"><tbody>')
    $summaryRows = @(
        @('Database', $Report.Summary.Database),
        @('Session', $Report.Summary.SessionId),
        @('Generated', $Report.Summary.GeneratedAt),
        @('Subset tables', $Report.Summary.TableCount),
        @('Original tables', $Report.Summary.OriginalTableCount),
        @('Subset rows', $Report.Summary.TotalRows),
        @('Original rows', $summaryOriginalRows),
        @('Percent of original rows', $summaryPercentOfOriginalRows),
        @('Rows excluded', $Report.Summary.RowsExcluded),
        @('Percent rows excluded', $Report.Summary.PercentRowsExcluded),
        @('Estimated data KB', $Report.Summary.EstimatedDataKB),
        @('Operations complete', $Report.Summary.OperationsComplete)
    )
    foreach ($row in $summaryRows)
    {
        $lines.Add("<tr><th>$(Format-SubsetImpactHtmlValue $row[0])</th><td>$(Format-SubsetImpactHtmlValue $row[1])</td></tr>")
    }
    $lines.Add('</tbody></table>')

    $lines.Add('<h2>Tables</h2>')
    $lines.Add('<table><thead><tr><th>Table</th><th>Subset Rows</th><th>Original Rows</th><th>Rows Excluded</th><th>% Original</th><th>% Rows Excluded</th><th>Estimated Data KB</th><th>PK Size</th><th>Deletable</th><th>Historic</th></tr></thead><tbody>')
    foreach ($table in $Report.Tables)
    {
        $name = Format-SubsetImpactTableName -Schema $table.SchemaName -Table $table.TableName
        $originalRows = $table.OriginalRows
        if ($null -eq $originalRows) { $originalRows = $table.SourceRows }

        $percentOfOriginalRows = $table.PercentOfOriginalRows
        if ($null -eq $percentOfOriginalRows) { $percentOfOriginalRows = $table.PercentOfSourceRows }

        $lines.Add("<tr><td>$(Format-SubsetImpactHtmlValue $name)</td><td class=""num"">$(Format-SubsetImpactHtmlValue $table.SubsetRows)</td><td class=""num"">$(Format-SubsetImpactHtmlValue $originalRows)</td><td class=""num"">$(Format-SubsetImpactHtmlValue $table.RowsExcluded)</td><td class=""num"">$(Format-SubsetImpactHtmlValue $percentOfOriginalRows)</td><td class=""num"">$(Format-SubsetImpactHtmlValue $table.PercentRowsExcluded)</td><td class=""num"">$(Format-SubsetImpactHtmlValue $table.EstimatedDataKB)</td><td class=""num"">$(Format-SubsetImpactHtmlValue $table.PrimaryKeySize)</td><td>$(Format-SubsetImpactHtmlValue $table.CanBeDeleted)</td><td>$(Format-SubsetImpactHtmlValue $table.IsHistoric)</td></tr>")
    }
    if ($Report.Tables.Count -eq 0)
    {
        $lines.Add('<tr><td colspan="10"><em>none</em></td></tr>')
    }
    $lines.Add('</tbody></table>')

    $lines.Add('<h2>Relationships</h2>')
    $relationshipSections = @(
        [pscustomobject]@{ Name = 'Reached'; Items = @($Report.Relationships.Reached) },
        [pscustomobject]@{ Name = 'Unreached'; Items = @($Report.Relationships.Unreached) }
    )
    foreach ($section in $relationshipSections)
    {
        $lines.Add("<h3>$(Format-SubsetImpactHtmlValue $section.Name)</h3>")
        $lines.Add('<table><thead><tr><th>Foreign Key</th><th>From</th><th>To</th></tr></thead><tbody>')
        foreach ($relationship in $section.Items)
        {
            $from = Format-SubsetImpactTableName -Schema $relationship.FromSchema -Table $relationship.FromTable
            $to = Format-SubsetImpactTableName -Schema $relationship.ToSchema -Table $relationship.ToTable
            $lines.Add("<tr><td>$(Format-SubsetImpactHtmlValue $relationship.Name)</td><td>$(Format-SubsetImpactHtmlValue $from)</td><td>$(Format-SubsetImpactHtmlValue $to)</td></tr>")
        }
        if ($section.Items.Count -eq 0)
        {
            $lines.Add('<tr><td colspan="3"><em>none</em></td></tr>')
        }
        $lines.Add('</tbody></table>')
    }

    $lines.Add('<h2>Operations</h2>')
    $lines.Add('<table><thead><tr><th>State</th><th>Depth</th><th>Operations</th><th>To Process</th><th>Processed</th><th>Remaining</th></tr></thead><tbody>')
    foreach ($operation in $Report.Operations.ByStateAndDepth)
    {
        $lines.Add("<tr><td>$(Format-SubsetImpactHtmlValue $operation.State)</td><td class=""num"">$(Format-SubsetImpactHtmlValue $operation.Depth)</td><td class=""num"">$(Format-SubsetImpactHtmlValue $operation.OperationCount)</td><td class=""num"">$(Format-SubsetImpactHtmlValue $operation.RecordsToProcess)</td><td class=""num"">$(Format-SubsetImpactHtmlValue $operation.RecordsProcessed)</td><td class=""num"">$(Format-SubsetImpactHtmlValue $operation.RecordsRemaining)</td></tr>")
    }
    if ($Report.Operations.ByStateAndDepth.Count -eq 0)
    {
        $lines.Add('<tr><td colspan="6"><em>none</em></td></tr>')
    }
    $lines.Add('</tbody></table>')

    if ($Report.Warnings.Count -gt 0)
    {
        $lines.Add('<h2>Warnings</h2>')
        foreach ($warning in $Report.Warnings)
        {
            $lines.Add("<div class=""warning"">$(Format-SubsetImpactHtmlValue $warning)</div>")
        }
    }

    $lines.Add('</body>')
    $lines.Add('</html>')

    return ($lines -join [Environment]::NewLine)
}
