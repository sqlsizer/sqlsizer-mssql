function Find-RemovalSubset
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

        [Parameter(Mandatory = $true)]
        [DatabaseInfo]$DatabaseInfo,

        [Parameter(Mandatory = $true)]
        [SqlConnectionInfo]$ConnectionInfo
    )

    $incomingCache = New-Object "System.Collections.Generic.Dictionary[[string], [string]]"

    function CreateIncomingQueryPattern
    {
        param
        (
            [TableInfo]$table,
            [int]$color
        )

        if ($ConnectionInfo.IsSynapse)
        {
            $result = "DECLARE @SqlSizerCount INT = 0
            " 
        }
        else
        {
            $result = ""
        }

        $tableId = $tablesGroupedByName[$table.SchemaName + ", " + $table.TableName].Id

        foreach ($referencedByTable in $table.IsReferencedBy)
        {
            $fks = $referencedByTable.ForeignKeys | Where-Object { ($_.Schema -eq $table.SchemaName) -and ($_.Table -eq $table.TableName) }
            foreach ($fk in $fks)
            {
                if ([TableInfo2]::IsIgnored($fk.FkSchema, $fk.FkTable, $ignoredTables) -eq $true)
                {
                    continue
                }

                $newColor = $color
                $fkTable = $DatabaseInfo.Tables | Where-Object { ($_.SchemaName -eq $fk.FkSchema) -and ($_.TableName -eq $fk.FkTable) }
                $fkTableId = $tablesGroupedByName[$fk.FkSchema + ", " + $fk.FkTable].Id
                $fkSignature = $structure.Tables[$fkTable]
                $fkProcessing = $structure.GetProcessingName($fkSignature, $SessionId)
                $primaryKey = $referencedByTable.PrimaryKey
                $fkId = $fkGroupedByName[$fk.FkSchema + ", " + $fk.FkTable + ", " + $fk.Name].Id

                if (($null -eq $primaryKey) -or ($primaryKey.Count -eq 0))
                {
                    continue
                }

                #where
                $columns = ""
                $i = 0
                foreach ($pk in $primaryKey)
                {
                    if ($i -gt 0)
                    {
                        $columns += " and "
                    }
                    $columns = $columns + " f.$($pk.Name) = p.Key$i "
                    $i += 1
                }
                $where = " WHERE NOT EXISTS(SELECT 1 FROM $fkProcessing p WHERE $columns) AND EXISTS(SELECT 1 FROM  $processing s WHERE "

                $i = 0
                foreach ($fkColumn in $fk.FkColumns)
                {
                    if ($i -gt 0)
                    {
                        $where += " AND "
                    }

                    $where += " s.Key$i = f.$($fkColumn.Name)"
                    $i += 1
                }

                $where += " AND s.Depth = ##depth## ) "
                $from = " FROM " + $referencedByTable.SchemaName + "." + $referencedByTable.TableName + " f "

                # select
                $columns = ""
                $i = 0
                foreach ($primaryKeyColumn in $primaryKey)
                {
                    if ($columns -ne "")
                    {
                        $columns += ", "
                    }
                    $columns += (Get-ColumnValue -ColumnName $primaryKeyColumn.Name -Prefix "f." -dataType $primaryKeyColumn.dataType) + " as val$i "
                    $i += 1
                }

                $topPhrase = " "

                if ($MaxBatchSize -ne -1)
                {
                    $top = $MaxBatchSize
                }

                if (($null -ne $top) -and ($top -ne -1))
                {
                    $topPhrase = " TOP $($top) "
                }

                $select = "SELECT " + $topPhrase + $columns
                $sql = $select + $from + $where

                $columns = ""
                for ($i = 0; $i -lt $primaryKey.Count; $i = $i + 1)
                {
                    $columns = $columns + "x.val" + $i + ","
                }

                if ($ConnectionInfo.IsSynapse -eq $false)
                {
                    $insert = "DECLARE @SqlSizerCount INT = 0
                    " 
                }
                $insert += " SELECT $columns " + $newColor + " as Color, $tableId as TableId, ##depth## + 1 as Depth, $fkId as FkId, ##iteration## as Iteration INTO #tmp FROM (" + $sql + ") x SET @SqlSizerCount = @@ROWCOUNT "
                $insert += " INSERT INTO $fkProcessing SELECT * FROM #tmp "
                if ($MaxBatchSize -ne -1)
                {
                    # reset operation if MaxBatchSize limit is reached
                    $insert += "IF (@SqlSizerCount = $MaxBatchSize)
                                BEGIN
                                    UPDATE SqlSizer.Operations SET [Status] = NULL WHERE [SessionId] = '$SessionId' AND [Status] = 0 AND [Table] = $($table.Id)
                                END"
                }
                $insert += " INSERT INTO SqlSizer.Operations SELECT $fkTableId, $newColor, @SqlSizerCount, 0, NULL, $tableId, $fkId, ##depth## + 1, GETDATE(), NULL, '$SessionId', ##iteration##, NULL"
                $insert += " DROP TABLE #tmp "
                
                if ($ConnectionInfo.IsSynapse -eq $false)
                {
                    $insert += " 
                    GO 
                    "
                }
                $result += $insert
            }
        }

        return $result
    }

    function HandleIncoming
    {
        param
        (
            [TableInfo]$table,
            [int]$color,
            [int]$iteration,
            [int]$depth
        )

        $key = "$($table.SchemaName)_$($table.TableName)_$($color)"

        if ($incomingCache.ContainsKey($key))
        {   
            $query = $incomingCache[$key]
        }
        else
        {
            $query = CreateIncomingQueryPattern -table $table -color $color
            $incomingCache[$key] = $query
        }

        if ($query -ne "")
        {
            $query = $query.Replace("##iteration##", $iteration)
            $query = $query.Replace("##depth##", $depth)
            $null = Invoke-SqlcmdEx -Sql $query -Database $Database -ConnectionInfo $ConnectionInfo
        }
    }

    function DoSearch()
    {
        param
        (
            [int]$iteration
        )

        Write-Progress -Activity "Finding subset $SessionId" -PercentComplete 0 

        $interval = 5
        $percent = 0
        # Progress handling
        $totalSeconds = (New-TimeSpan -Start $start -End (Get-Date)).TotalSeconds
        if ($totalSeconds -gt ($lastTotalSeconds + $interval))
        {
            $lastTotalSeconds = $totalSeconds
            $progress = Get-SubsetProgress -Database $Database -ConnectionInfo $ConnectionInfo
            $percent = (100 * ($progress.Processed / ($progress.Processed + $progress.ToProcess)))
            Write-Progress -Activity "Finding subset $SessionId" -PercentComplete $percent
        }
        
        $q = "SELECT TOP 1
                    [Table],
                    [Depth],
                    [Color],
                    SUM([ToProcess] - [Processed]) as [Count]
                FROM
                    [SqlSizer].[Operations]
                WHERE
                    [Status] IS NULL AND [SessionId] = '$SessionId'
                GROUP BY
                    [Table], [Depth], [Color]
                ORDER BY
                    [Depth] ASC, [Count] DESC"
        
        $operation = Invoke-SqlcmdEx -Sql $q -Database $Database -ConnectionInfo $ConnectionInfo

        if ($null -eq $operation)
        {
            Write-Progress -Activity "Finding subset $SessionId" -Completed
            return $false
        }

        # load node info
        $tableId = $operation.Table
        $color = $operation.Color
        $depth = $operation.Depth
        $tableData = $tablesGroupedById["$($tableId)"]
        $table = $DatabaseInfo.Tables | Where-Object { ($_.SchemaName -eq $tableData.SchemaName) -and ($_.TableName -eq $tableData.TableName) }
        $table.Id = $tableId

        Write-Progress -Activity "Finding subset $SessionId" -CurrentOperation  "$($table.SchemaName).$($table.TableName) table is being processed with color $([Color]$color)" -PercentComplete $percent

        $q = "SELECT [Id], [ToProcess], [Processed] FROM [SqlSizer].[Operations] WHERE [Table] = $tableId AND Status IS NULL AND [Color] = $color AND [Depth] = $depth AND [SessionId] = '$SessionId'"
        $operations = Invoke-SqlcmdEx -Sql $q -Database $Database -ConnectionInfo $ConnectionInfo


        if ($MaxBatchSize -eq -1)
        {
            foreach ($operation in $operations)
            {
                $q = "UPDATE [SqlSizer].[Operations] SET Status = 0, Processed = ToProcess WHERE Id = $($operation.Id)"
                $null = Invoke-SqlcmdEx -Sql $q -Database $Database -ConnectionInfo $ConnectionInfo
            }
        }
        else
        {
            $tmp = $MaxBatchSize
            foreach ($operation in $operations)
            {   
                if ($tmp -gt 0)
                {
                    $diff = $operation.ToProcess - $operation.Processed
                    if ($diff -gt $tmp)
                    {
                        $q = "UPDATE [SqlSizer].[Operations] SET Status = 0, Processed = Processed + $tmp WHERE Id = $($operation.Id)"
                        $tmp  = 0
                    }
                    else
                    {
                        if ($operation.ToProcess -ge ($operation.Processed + $diff))
                        {
                            $q = "UPDATE [SqlSizer].[Operations] SET Status = 0, Processed = Processed + $diff WHERE Id = $($operation.Id)"
                        }
                        else
                        {
                            $q = "UPDATE [SqlSizer].[Operations] SET Status = 0, Processed = ToProcess  WHERE Id = $($operation.Id)"
                        }
                        $tmp -= $diff
                    }
                            
                    $null = Invoke-SqlcmdEx -Sql $q -Database $Database -ConnectionInfo $ConnectionInfo
                }
            }
        }

        $signature = $structure.Tables[$table]
        $processing = $structure.GetProcessingName($signature, $SessionId)

        HandleIncoming -table $table -color $color -iteration $iteration -depth $depth

        # mark operations as processed
        $q = "UPDATE SqlSizer.Operations SET Status = NULL WHERE Status = 0 AND ToProcess <> Processed AND [SessionId] = '$SessionId'"
        $null = Invoke-SqlcmdEx -Sql $q -Database $Database -ConnectionInfo $ConnectionInfo

        $q = "UPDATE SqlSizer.Operations SET Status = 1, ProcessedIteration = $iteration, ProcessedDate = GETDATE() WHERE Status = 0 AND [SessionId] = '$SessionId'"
        $null = Invoke-SqlcmdEx -Sql $q -Database $Database -ConnectionInfo $ConnectionInfo
        return $true
    }

    # get meta data
    $structure = [Structure]::new($DatabaseInfo)
    $sqlSizerInfo = Get-SqlSizerInfo -Database $Database -ConnectionInfo $ConnectionInfo
    $tablesGroupedById = $sqlSizerInfo.Tables | Group-Object -Property Id -AsHashTable -AsString
    $tablesGroupedByName = $sqlSizerInfo.Tables | Group-Object -Property SchemaName, TableName -AsHashTable -AsString
    $fkGroupedByName = $sqlSizerInfo.ForeignKeys | Group-Object -Property FkSchemaName, FkTableName, Name -AsHashTable -AsString

    if ($false -eq $Interactive)
    {
        $null = Initialize-OperationsTable -SessionId $SessionId -Database $Database -ConnectionInfo $ConnectionInfo -DatabaseInfo $DatabaseInfo -StartIteration $StartIteration
        $start = Get-Date
        $iteration = $StartIteration + 1

        do
        {
            $result = DoSearch -iteration $iteration
            $iteration = $iteration + 1
        }
        while ($result -eq $true)

        return [pscustomobject]@{
            Finished            = $true
            Initialized         = $true
            CompletedIterations = $iteration - $StartIteration
        }
    }
    else
    {
        if ($Iteration -eq 0)
        {
            $null = Initialize-OperationsTable -SessionId $SessionId -Database $Database -ConnectionInfo $ConnectionInfo -DatabaseInfo $DatabaseInfo -StartIteration $StartIteration
            return [pscustomobject]@{
                Finished            = $false
                Initialized         = $true
                CompletedIterations = 1
            }
        }
        else
        {
            $start = Get-Date
            $result = DoSearch -iteration $Iteration

            return [pscustomobject]@{
                Finished            = $result -eq $false
                Initialized         = $true
                CompletedIterations = 1
            }
        }
    }
}
