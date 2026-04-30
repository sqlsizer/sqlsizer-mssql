function Copy-DataFromSubset
{
    [cmdletbinding()]
    param
    (
        [Parameter(Mandatory = $true)]
        [string]$SessionId,

        [Parameter(Mandatory = $true)]
        [string]$Source,

        [Parameter(Mandatory = $true)]
        [string]$Destination,

        [Parameter(Mandatory = $true)]
        [DatabaseInfo]$DatabaseInfo,

        [Parameter(Mandatory = $false)]
        [TableInfo2[]]$IgnoredTables,

        [Parameter(Mandatory = $true)]
        [SqlConnectionInfo]$ConnectionInfo
    )

    $i = 0
    $structure = [Structure]::new($DatabaseInfo)
    $subsetTables = Get-SubsetTables -Database $Source -ConnectionInfo $ConnectionInfo -DatabaseInfo $DatabaseInfo -SessionId $SessionId

    foreach ($table in $subsetTables)
    {
        $i += 1

        $tableInfo = $DatabaseInfo.Tables | Where-Object { ($_.SchemaName -eq $table.SchemaName) -and ($_.TableName -eq $table.TableName) }
        Write-Progress -Activity "Copying data" -PercentComplete (100 * ($i / ($subsetTables.Count))) -CurrentOperation "Table $($table.SchemaName).$($table.TableName)"

        if ($tableInfo.IsHistoric -eq $true)
        {
            continue
        }

        $signature = $structure.Tables[$tableInfo]

        $sql = New-CopyDataFromSubsetQuery `
            -SessionId $SessionId `
            -Source $Source `
            -TableInfo $tableInfo `
            -ProcessingTableName $signature `
            -IgnoredTables $IgnoredTables

        $sql = Add-CopyDataFromSubsetIdentityInsert -Sql $sql -TableInfo $tableInfo
        $null = Invoke-SqlcmdEx -Sql $sql -Database $Destination -ConnectionInfo $ConnectionInfo
    }

    Write-Progress -Activity "Copying data" -Completed
}

function New-CopyDataFromSubsetQuery
{
    param
    (
        [Parameter(Mandatory = $true)]
        [string]$SessionId,

        [Parameter(Mandatory = $true)]
        [string]$Source,

        [Parameter(Mandatory = $true)]
        [TableInfo]$TableInfo,

        [Parameter(Mandatory = $true)]
        [string]$ProcessingTableName,

        [Parameter(Mandatory = $false)]
        [TableInfo2[]]$IgnoredTables
    )

    if (($null -eq $TableInfo.PrimaryKey) -or ($TableInfo.PrimaryKey.Count -eq 0))
    {
        throw "Cannot copy subset data for $($TableInfo.SchemaName).$($TableInfo.TableName) because it has no primary key."
    }

    if ([string]::IsNullOrWhiteSpace($ProcessingTableName))
    {
        throw "Cannot copy subset data for $($TableInfo.SchemaName).$($TableInfo.TableName) because no processing table was found."
    }

    $targetTableSql = Get-CopyDataFromSubsetTargetTableSql -TableInfo $TableInfo
    $sourceTableSql = Get-CopyDataFromSubsetSourceTableSql -Source $Source -TableInfo $TableInfo
    $processingTableSql = Get-CopyDataFromSubsetProcessingTableSql -Source $Source -SessionId $SessionId -ProcessingTableName $ProcessingTableName
    $insertColumns = Get-CopyDataFromSubsetInsertColumnList -TableInfo $TableInfo
    $sourceColumns = Get-CopyDataFromSubsetSourceColumnList -TableInfo $TableInfo -IgnoredTables $IgnoredTables
    $keyColumns = Get-CopyDataFromSubsetKeyColumnList -TableInfo $TableInfo
    $joinCondition = Get-CopyDataFromSubsetKeyJoinCondition -TableInfo $TableInfo
    $includedStates = Get-IncludedTraversalStateSqlList

    return "INSERT INTO $targetTableSql ($insertColumns) SELECT $sourceColumns FROM $sourceTableSql src INNER JOIN (SELECT DISTINCT $keyColumns FROM $processingTableSql WHERE [State] IN ($includedStates)) subsetKeys ON $joinCondition"
}

function Add-CopyDataFromSubsetIdentityInsert
{
    param
    (
        [Parameter(Mandatory = $true)]
        [string]$Sql,

        [Parameter(Mandatory = $true)]
        [TableInfo]$TableInfo
    )

    if ($TableInfo.IsIdentity -eq $false)
    {
        return $Sql
    }

    $targetTableSql = Get-CopyDataFromSubsetTargetTableSql -TableInfo $TableInfo
    return "SET IDENTITY_INSERT $targetTableSql ON; $Sql; SET IDENTITY_INSERT $targetTableSql OFF"
}

function Get-CopyDataFromSubsetTargetTableSql
{
    param
    (
        [Parameter(Mandatory = $true)]
        [TableInfo]$TableInfo
    )

    return "$(ConvertTo-SqlIdentifier $TableInfo.SchemaName).$(ConvertTo-SqlIdentifier $TableInfo.TableName)"
}

function Get-CopyDataFromSubsetSourceTableSql
{
    param
    (
        [Parameter(Mandatory = $true)]
        [string]$Source,

        [Parameter(Mandatory = $true)]
        [TableInfo]$TableInfo
    )

    return "$(ConvertTo-SqlIdentifier $Source).$(ConvertTo-SqlIdentifier $TableInfo.SchemaName).$(ConvertTo-SqlIdentifier $TableInfo.TableName)"
}

function Get-CopyDataFromSubsetProcessingTableSql
{
    param
    (
        [Parameter(Mandatory = $true)]
        [string]$Source,

        [Parameter(Mandatory = $true)]
        [string]$SessionId,

        [Parameter(Mandatory = $true)]
        [string]$ProcessingTableName
    )

    return "$(ConvertTo-SqlIdentifier $Source).$(ConvertTo-SqlIdentifier "SqlSizer_$SessionId").$(ConvertTo-SqlIdentifier $ProcessingTableName)"
}

function Get-CopyDataFromSubsetInsertColumnList
{
    param
    (
        [Parameter(Mandatory = $true)]
        [TableInfo]$TableInfo
    )

    $columns = foreach ($column in $TableInfo.Columns)
    {
        if (Test-CopyDataFromSubsetColumnSkipped -Column $column)
        {
            continue
        }

        ConvertTo-SqlIdentifier $column.Name
    }

    return [string]::Join(', ', $columns)
}

function Get-CopyDataFromSubsetSourceColumnList
{
    param
    (
        [Parameter(Mandatory = $true)]
        [TableInfo]$TableInfo,

        [Parameter(Mandatory = $false)]
        [TableInfo2[]]$IgnoredTables
    )

    $columns = foreach ($column in $TableInfo.Columns)
    {
        if (Test-CopyDataFromSubsetColumnSkipped -Column $column)
        {
            continue
        }

        if (Test-CopyDataFromSubsetIgnoredForeignKeyColumn -TableInfo $TableInfo -ColumnName $column.Name -IgnoredTables $IgnoredTables)
        {
            'NULL'
        }
        else
        {
            "src.$(ConvertTo-SqlIdentifier $column.Name)"
        }
    }

    return [string]::Join(', ', $columns)
}

function Get-CopyDataFromSubsetKeyColumnList
{
    param
    (
        [Parameter(Mandatory = $true)]
        [TableInfo]$TableInfo
    )

    $columns = for ($i = 0; $i -lt $TableInfo.PrimaryKey.Count; $i++)
    {
        ConvertTo-SqlIdentifier "Key$i"
    }

    return [string]::Join(', ', $columns)
}

function Get-CopyDataFromSubsetKeyJoinCondition
{
    param
    (
        [Parameter(Mandatory = $true)]
        [TableInfo]$TableInfo
    )

    $conditions = for ($i = 0; $i -lt $TableInfo.PrimaryKey.Count; $i++)
    {
        "src.$(ConvertTo-SqlIdentifier $TableInfo.PrimaryKey[$i].Name) = subsetKeys.$(ConvertTo-SqlIdentifier "Key$i")"
    }

    return [string]::Join(' AND ', $conditions)
}

function Test-CopyDataFromSubsetColumnSkipped
{
    param
    (
        [Parameter(Mandatory = $true)]
        [ColumnInfo]$Column
    )

    return ($Column.IsComputed -eq $true) -or ($Column.IsGenerated -eq $true) -or ($Column.DataType -eq "timestamp")
}

function Test-CopyDataFromSubsetIgnoredForeignKeyColumn
{
    param
    (
        [Parameter(Mandatory = $true)]
        [TableInfo]$TableInfo,

        [Parameter(Mandatory = $true)]
        [string]$ColumnName,

        [Parameter(Mandatory = $false)]
        [TableInfo2[]]$IgnoredTables
    )

    foreach ($fk in $TableInfo.ForeignKeys)
    {
        if ([TableInfo2]::IsIgnored($fk.Schema, $fk.Table, $IgnoredTables) -eq $false)
        {
            continue
        }

        foreach ($fkColumn in $fk.FkColumns)
        {
            if ($fkColumn.Name -eq $ColumnName)
            {
                return $true
            }
        }
    }

    return $false
}
