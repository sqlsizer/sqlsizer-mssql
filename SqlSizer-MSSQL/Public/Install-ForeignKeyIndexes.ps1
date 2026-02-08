function Install-ForeignKeyIndexes
{
    [cmdletbinding()]
    param
    (
        [Parameter(Mandatory = $true)]
        [string]$Database,

        [Parameter(Mandatory = $true)]
        [Query2[]]$Queries,

        [Parameter(Mandatory = $false)]
        [bool]$OnlyMissing = $true,

        [Parameter(Mandatory = $true)]
        [DatabaseInfo]$DatabaseInfo,

        [Parameter(Mandatory = $true)]
        [SqlConnectionInfo]$ConnectionInfo
    )

    $reachableTables = Find-ReachableTables -Queries $Queries -Connection $ConnectionInfo -DatabaseInfo $DatabaseInfo

    $tablesGrouped = $DatabaseInfo.Tables | Group-Object -Property SchemaName, TableName -AsHashTable -AsString

    foreach ($table in $reachableTables)
    {
        $tableInfo = $tablesGrouped[$table.SchemaName + ", " + $table.TableName]

        foreach ($fk in $tableInfo.ForeignKeys)
        {
            $columns = ""
            $signature = ""

            foreach ($fkColumn in $fk.FkColumns)
            {
                $pk = $tableInfo.PrimaryKey | Where-Object { $_.Name -eq $fkColumn.Name }

                if ($null -ne $pk)
                {
                    break
                }

                if ($OnlyMissing -eq $true)
                {
                    $index = $tableInfo.Indexes | Where-Object { ($null -ne $_.Columns) -and $_.Columns.Contains($fkColumn.Name) }

                    if ($null -ne $index)
                    {
                        Write-Verbose "Index $($index.Name) already exists that covers $($fkColumn.Name) column"
                        break
                    }
                }

                if ($columns -ne "")
                {
                    $columns += ","
                }
                $columns += $fkColumn.Name
                $signature += "_" + $fkColumn.Name
            }

            if ($columns -ne "")
            {
                $indexName = "SqlSizer_$($table.SchemaName)_$($table.TableName)_$($signature)"
                $sql = "IF IndexProperty(OBJECT_ID('$($table.SchemaName).$($table.TableName)'), '$($indexName)', 'IndexId') IS NULL"
                $sql += " CREATE INDEX [$($indexName)] ON [$($table.SchemaName)].[$($table.TableName)] ($($columns))"
                $null = Invoke-SqlcmdEx -Sql $sql -Database $Database -ConnectionInfo $ConnectionInfo -Statistics $false
            }
        }
    }
}

