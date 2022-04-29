﻿function Get-DatabaseInfo
{
    param (
        [Parameter(Mandatory=$true)]
        [string]$Database,

        [Parameter(Mandatory=$true)]
        [SqlConnectionInfo]$ConnectionInfo
    )

    $sql = Get-Content -Raw -Path ($PSScriptRoot + "\..\Queries\TablesInfo.sql")
    $rows = Execute-SQL -Sql $sql -Database $Database -ConnectionInfo $ConnectionInfo
    $result = New-Object -TypeName DatabaseInfo

    $sql = Get-Content -Raw -Path ($PSScriptRoot + "\..\Queries\TablesPrimaryKeys.sql")
    $primaryKeyRows = Execute-SQL -Sql $sql -Database $Database -ConnectionInfo $ConnectionInfo
    $primaryKeyRowsGrouped = $primaryKeyRows | Group-Object -Property schema, table -AsHashTable -AsString

    $sql = Get-Content -Raw -Path ($PSScriptRoot + "\..\Queries\TablesColumns.sql")
    $columnsRows = Execute-SQL -Sql $sql -Database $Database -ConnectionInfo $ConnectionInfo
    $columnsRowsGrouped = $columnsRows | Group-Object -Property schema, table -AsHashTable -AsString

    $sql = Get-Content -Raw -Path ($PSScriptRoot + "\..\Queries\TablesForeignKeys.sql")
    $foreignKeyRows = Execute-SQL -Sql $sql -Database $Database -ConnectionInfo $ConnectionInfo
    $foreignKeyRowsGrouped = $foreignKeyRows | Group-Object -Property fk_schema, fk_table -AsHashTable -AsString

    foreach ($row in $rows)
    {
        $table = New-Object -TypeName TableInfo
        $table.SchemaName = $row["schema"]
        $table.TableName = $row["table"]
        $table.IsIdentity = $row["identity"]
        $table.IsHistoric = $row["is_historic"]
        $table.HistoryOwner = $row["history_owner"]
        $table.HistoryOwnerSchema = $row["history_owner_schema"]
        $key = $table.SchemaName + ", " + $table.TableName

        $tableKey = $primaryKeyRowsGrouped[$key]

        foreach ($tableKeyColumn in $tableKey)
        {
            $pkColumn = New-Object -TypeName ColumnInfo
            $pkColumn.Name = $tableKeyColumn["column"]
            $pkColumn.DataType = $tableKeyColumn["dataType"]
            $pkColumn.IsNullable = $false
            $pkColumn.IsComputed = $false
            $table.PrimaryKey += $pkColumn
        }

        $tableColumns = $columnsRowsGrouped[$key]

        foreach ($tableColumn in $tableColumns)
        {
            $column = New-Object -TypeName ColumnInfo
            $column.Name = $tableColumn["column"]
            $column.DataType = $tableColumn["dataType"]
            $column.IsComputed = $tableColumn["isComputed"]
            $column.IsGenerated = $tableColumn["isGenerated"]
            $column.IsNullable = $tableColumn["isNullable"] -eq "YES"
            $table.Columns += $column
        }

        $tableForeignKeys = $foreignKeyRowsGrouped[$key]

        $tableForeignKeysGrouped = $tableForeignKeys | Group-Object -Property fk_name

        foreach ($item in $tableForeignKeysGrouped)
        {
            $fk = New-Object -TypeName TableFk
            $fk.Name = $item.Name

            foreach ($column in $item.Group)
            {
                $fk.Schema = $column["schema"]
                $fk.Table = $column["table"]
                $fk.FkSchema = $column["fk_schema"]
                $fk.FkTable = $column["fk_table"]

                $fkColumn = New-Object -TypeName ColumnInfo
                $fkColumn.Name = $column["fk_column"]
                $fkColumn.DataType = $column["fk_column_data_type"]
                $fkColumn.IsNullable = $column["fk_column_is_nullable"]
                $fkColumn.IsComputed = $false

                $column = New-Object -TypeName ColumnInfo
                $column.Name = $column["column"]
                $column.DataType = $column["fk_column_data_type"]
                $column.IsNullable = $false
                $column.IsComputed = $false

                $fk.Columns += $column
                $fk.FkColumns += $fkColumn
            }

            $table.ForeignKeys += $fk
        }

        $result.Tables += $table
    }

    $primaryKeyMaxSize = 0

    $tablesGrouped = @{}
    foreach ($table in $result.Tables)
    {
        $tablesGrouped[$table.SchemaName + ", " + $table.TableName] = $table
    }

    foreach ($table in $result.Tables)
    {
        if ($table.PrimaryKey.Count -gt $primaryKeyMaxSize)
        {
            $primaryKeyMaxSize = $table.PrimaryKey.Count
        }

        $table.HasHistory = $false
        $historic = $result.Tables | Where-Object { ($_.HistoryOwner -eq $table.TableName) -and ($_.HistoryOwnerSchema -eq $table.SchemaName) }
        if ($historic)        
        {
            $table.HasHistory = $true
        }

        foreach ($fk in $table.ForeignKeys)
        {
            $schema = $fk.Schema
            $tableName = $fk.Table

            $primaryTable = $tablesGrouped[$schema + ", " + $tableName]
            $primaryTable.IsReferencedBy += $table
        }
    }
    
    $result.PrimaryKeyMaxSize = $primaryKeyMaxSize    

    return $result
}

