function Export-SubsetAsSql
{
    [cmdletbinding()]
    param
    (
        [Parameter(Mandatory = $true)]
        [string]$Database,

        [Parameter(Mandatory = $true)]
        [string]$SessionId,

        [Parameter(Mandatory = $true)]
        [DatabaseInfo]$DatabaseInfo,

        [Parameter(Mandatory = $true)]
        [SqlConnectionInfo]$ConnectionInfo,

        [Parameter(Mandatory = $true)]
        [string]$OutputPath,

        [Parameter(Mandatory = $false)]
        [TableInfo2[]]$IgnoredTables,

        [Parameter(Mandatory = $false)]
        [int]$BatchSize = 500,

        [Parameter(Mandatory = $false)]
        [switch]$InsertOnly
    )

    if ($BatchSize -lt 1)
    {
        throw "BatchSize must be at least 1."
    }

    $structure    = [Structure]::new($DatabaseInfo)
    $subsetTables = @(Get-SubsetTables -Database $Database -DatabaseInfo $DatabaseInfo -ConnectionInfo $ConnectionInfo -SessionId $SessionId)

    if ($null -ne $IgnoredTables -and $IgnoredTables.Count -gt 0)
    {
        $subsetTables = @($subsetTables | Where-Object { -not [TableInfo2]::IsIgnored($_.SchemaName, $_.TableName, $IgnoredTables) })
    }

    if ($subsetTables.Count -gt 1)
    {
        $subsetTables = @(Get-CopyDataFromSubsetForeignKeySafeOrder -SubsetTables $subsetTables -DatabaseInfo $DatabaseInfo)
    }

    $includedStates = Get-IncludedTraversalStateSqlList
    $modeLabel      = if ($InsertOnly) { "InsertOnly" } else { "Upsert (MERGE)" }
    $timestamp      = [DateTime]::UtcNow.ToString("yyyy-MM-ddTHH:mm:ssZ")

    $sb = [System.Text.StringBuilder]::new()

    $null = $sb.AppendLine("-- SqlSizer | Export-SubsetAsSql")
    $null = $sb.AppendLine("-- Source database : $Database")
    $null = $sb.AppendLine("-- Session         : $SessionId")
    $null = $sb.AppendLine("-- Generated at    : $timestamp")
    $null = $sb.AppendLine("-- Tables          : $($subsetTables.Count)")
    $null = $sb.AppendLine("-- Mode            : $modeLabel")
    $null = $sb.AppendLine("")
    $null = $sb.AppendLine("SET XACT_ABORT ON;")
    $null = $sb.AppendLine("SET NOCOUNT ON;")
    $null = $sb.AppendLine("BEGIN TRANSACTION;")
    $null = $sb.AppendLine("")

    $tableIndex = 0
    foreach ($table in $subsetTables)
    {
        $tableIndex++
        Write-Progress -Activity "Exporting subset as SQL" `
                       -Status "[$tableIndex/$($subsetTables.Count)] $($table.SchemaName).$($table.TableName)" `
                       -PercentComplete ([int](100 * $tableIndex / $subsetTables.Count))

        $tableInfo = $DatabaseInfo.Tables | Where-Object { ($_.SchemaName -eq $table.SchemaName) -and ($_.TableName -eq $table.TableName) }
        if ($null -eq $tableInfo)
        {
            continue
        }

        if ($tableInfo.IsHistoric -eq $true)
        {
            continue
        }

        if ($null -eq $tableInfo.PrimaryKey -or $tableInfo.PrimaryKey.Count -eq 0)
        {
            continue
        }

        $exportCols = @($tableInfo.Columns | Where-Object { (-not $_.IsComputed) -and (-not $_.IsGenerated) -and ($_.DataType -ne "timestamp") })
        if ($exportCols.Count -eq 0)
        {
            continue
        }

        $signature  = $structure.Tables[$tableInfo]
        $processing = $structure.GetProcessingName($signature, $SessionId)
        $tableSql   = "$(ConvertTo-SqlIdentifier $tableInfo.SchemaName).$(ConvertTo-SqlIdentifier $tableInfo.TableName)"

        $selectList = ($exportCols | ForEach-Object { "t.$(ConvertTo-SqlIdentifier $_.Name)" }) -join ", "
        $joinCond   = (0..($tableInfo.PrimaryKey.Count - 1) | ForEach-Object {
            "t.$(ConvertTo-SqlIdentifier $tableInfo.PrimaryKey[$_].Name) = p.Key$_"
        }) -join " AND "

        $sql  = "SELECT $selectList FROM $tableSql t WHERE EXISTS (SELECT 1 FROM $processing p WHERE $joinCond AND p.[State] IN ($includedStates))"
        $rows = @(Invoke-SqlcmdEx -Sql $sql -Database $Database -ConnectionInfo $ConnectionInfo)

        if ($rows.Count -eq 0)
        {
            continue
        }

        $colNames      = ($exportCols | ForEach-Object { ConvertTo-SqlIdentifier $_.Name }) -join ", "
        $sourceColList = ($exportCols | ForEach-Object { "_source.$(ConvertTo-SqlIdentifier $_.Name)" }) -join ", "

        $pkColNames = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
        foreach ($pkCol in $tableInfo.PrimaryKey) { [void]$pkColNames.Add($pkCol.Name) }

        $pkOnCondition = ($tableInfo.PrimaryKey | ForEach-Object { "_target.$(ConvertTo-SqlIdentifier $_.Name) = _source.$(ConvertTo-SqlIdentifier $_.Name)" }) -join " AND "
        $nonPkCols     = @($exportCols | Where-Object { -not $pkColNames.Contains($_.Name) })
        $updateSetList = ($nonPkCols | ForEach-Object { "_target.$(ConvertTo-SqlIdentifier $_.Name) = _source.$(ConvertTo-SqlIdentifier $_.Name)" }) -join ", "

        $null = $sb.AppendLine("-- [$tableIndex/$($subsetTables.Count)] $($tableInfo.SchemaName).$($tableInfo.TableName) -- $($rows.Count) rows")

        if ($tableInfo.IsIdentity -eq $true)
        {
            $null = $sb.AppendLine("SET IDENTITY_INSERT $tableSql ON;")
        }

        $batchStart = 0
        while ($batchStart -lt $rows.Count)
        {
            $batchEnd  = [Math]::Min($batchStart + $BatchSize, $rows.Count)
            $batchRows = @($rows[$batchStart..($batchEnd - 1)])
            $batchStart = $batchEnd

            $null = $sb.AppendLine("MERGE INTO $tableSql AS _target")
            $null = $sb.AppendLine("USING (VALUES")
            for ($vi = 0; $vi -lt $batchRows.Count; $vi++)
            {
                $row  = $batchRows[$vi]
                $vals = ($exportCols | ForEach-Object { ConvertTo-SqlExportLiteral $row[$_.Name] }) -join ", "
                $sep  = if ($vi -lt $batchRows.Count - 1) { "," } else { "" }
                $null = $sb.AppendLine("    ($vals)$sep")
            }
            $null = $sb.AppendLine(") AS _source ($colNames)")
            $null = $sb.AppendLine("ON ($pkOnCondition)")
            $null = $sb.AppendLine("WHEN NOT MATCHED BY TARGET THEN")
            $null = $sb.AppendLine("    INSERT ($colNames) VALUES ($sourceColList)")
            if ((-not $InsertOnly) -and ($nonPkCols.Count -gt 0))
            {
                $null = $sb.AppendLine("WHEN MATCHED THEN")
                $null = $sb.AppendLine("    UPDATE SET $updateSetList")
            }
            $null = $sb.AppendLine(";")
            $null = $sb.AppendLine("")
        }

        if ($tableInfo.IsIdentity -eq $true)
        {
            $null = $sb.AppendLine("SET IDENTITY_INSERT $tableSql OFF;")
            $null = $sb.AppendLine("")
        }
    }

    $null = $sb.AppendLine("COMMIT TRANSACTION;")

    $encoding = New-Object System.Text.UTF8Encoding $false
    [System.IO.File]::WriteAllText($OutputPath, $sb.ToString(), $encoding)

    Write-Progress -Activity "Exporting subset as SQL" -Completed
}

function ConvertTo-SqlExportLiteral
{
    param ([object]$Value)

    if ($null -eq $Value -or $Value -is [System.DBNull])
    {
        return "NULL"
    }

    if ($Value -is [bool])
    {
        return if ($Value) { "1" } else { "0" }
    }

    if ($Value -is [int16] -or $Value -is [int32] -or $Value -is [int64] -or
        $Value -is [byte]  -or $Value -is [uint16] -or $Value -is [uint32] -or
        $Value -is [uint64] -or $Value -is [sbyte])
    {
        return $Value.ToString()
    }

    if ($Value -is [decimal] -or $Value -is [double] -or $Value -is [System.Single])
    {
        return $Value.ToString("R", [System.Globalization.CultureInfo]::InvariantCulture)
    }

    if ($Value -is [DateTime])
    {
        return "'" + $Value.ToString("yyyy-MM-dd HH:mm:ss.fffffff") + "'"
    }

    if ($Value -is [DateTimeOffset])
    {
        return "'" + $Value.ToString("yyyy-MM-dd HH:mm:ss.fffffff zzz") + "'"
    }

    if ($Value -is [TimeSpan])
    {
        return "'" + ([DateTime]::MinValue + $Value).ToString("HH:mm:ss.fffffff") + "'"
    }

    if ($Value -is [Guid])
    {
        return "'" + $Value.ToString() + "'"
    }

    if ($Value -is [byte[]])
    {
        if ($Value.Length -eq 0)
        {
            return "0x"
        }
        return "0x" + [BitConverter]::ToString($Value).Replace("-", "")
    }

    return "N'" + $Value.ToString().Replace("'", "''") + "'"
}
