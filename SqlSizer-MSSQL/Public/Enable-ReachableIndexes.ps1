function Enable-ReachableIndexes
{
    [cmdletbinding()]
    param
    (
        [Parameter(Mandatory = $true)]
        [Query[]]$Queries,

        [Parameter(Mandatory = $true)]
        [string]$Database,

        [Parameter(Mandatory = $true)]
        [DatabaseInfo]$DatabaseInfo,

        [Parameter(Mandatory = $true)]
        [SqlConnectionInfo]$ConnectionInfo
    )

    $tablesGrouped = $DatabaseInfo.Tables | Group-Object -Property SchemaName, TableName -AsHashTable -AsString
    $reachable = Find-ReachableTables -Queries $Queries -DatabaseInfo $DatabaseInfo -ConnectionInfo $ConnectionInfo

    Write-Progress -Activity "Enabling reachable indexes" -PercentComplete 0

    foreach ($tableInfo in $reachable)
    {
        $table = $tablesGrouped[$tableInfo.SchemaName + ", " + $tableInfo.TableName]

        foreach ($index in $table.Indexes)
        {
            $isPk = $false
            foreach ($indexColumn in $index.Columns)
            {
                foreach ($pkColumn in $table.PrimaryKey)
                {
                    if ($indexColumn -eq $pkColumn.Name)
                    {
                        $isPk = $true
                        break
                    }
                }
            }

            if ($isPk -eq $false)
            {
                $sql  = "ALTER INDEX $($index.Name) ON $($table.SchemaName).$($table.TableName) REBUILD"
                $null = Invoke-SqlcmdEx -Sql $sql -Database $Database -ConnectionInfo $ConnectionInfo
            }
        }
    }

    Write-Progress -Activity "Enable reachable indexes" -Completed
}
