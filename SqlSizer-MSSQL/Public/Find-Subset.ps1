function Find-Subset
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

        [Parameter(Mandatory = $false)]
        [TableInfo2[]]$IgnoredTables,

        [Parameter(Mandatory = $true)]
        [DatabaseInfo]$DatabaseInfo,

        [Parameter(Mandatory = $false)]
        [ColorMap]$ColorMap = $null,

        [Parameter(Mandatory = $false)]
        [bool]$FullSearch = $false,

        [Parameter(Mandatory = $false)]
        [bool]$UseDfs = $false,

        [Parameter(Mandatory = $true)]
        [SqlConnectionInfo]$ConnectionInfo
    )

    $outgoingCache = New-Object "System.Collections.Generic.Dictionary[[string], [string]]"
    $incomingCache = New-Object "System.Collections.Generic.Dictionary[[string], [string]]"

    function GetIncomingNewColor
    {
        param
        (
            [TableFk]$fk,
            [int]$color,
            [ColorMap]$colorMap
        )

        $newColor = $color

        if ($color -eq [int][Color]::Green)
        {
            if ($FullSearch -ne $true)
            {
                $newColor = [int][Color]::Yellow
            }
        }

        if ($color -eq [int][Color]::Purple)
        {
            $newColor = [int][Color]::Red
        }

        if ($null -ne $colorMap)
        {
            $items = $colorMap.Items | Where-Object { ($_.SchemaName -eq $fk.FkSchema) -and ($_.TableName -eq $fk.FkTable) }
            $items = $items | Where-Object { ($null -eq $_.Condition) -or ($_.Condition.FkName -eq $fk.Name) -or ((($_.Condition.SourceSchemaName -eq $fk.Schema) -or ("" -eq $_.Condition.SourceSchemaName)) -and (($_.Condition.SourceTableName -eq $fk.Table) -or ("" -eq $_.Condition.SourceTableName))) }

            if (($null -ne $items) -and ($null -ne $items.ForcedColor))
            {
                $newColor = [int]$items.ForcedColor.Color
            }
        }
        return $newColor
    }

    function GetMaxDepth
    {
        param
        (
            [TableFk]$fk,
            [int]$color,
            [ColorMap]$colorMap
        )

        $maxDepth = $null

        if ($null -ne $colorMap)
        {
            $items = $colorMap.Items | Where-Object { ($_.SchemaName -eq $fk.FkSchema) -and ($_.TableName -eq $fk.FkTable) }
            $items = $items | Where-Object { ($null -eq $_.Condition) -or ($_.Condition.FkName -eq $fk.Name) -or ((($_.Condition.SourceSchemaName -eq $fk.Schema) -or ("" -eq $_.Condition.SourceSchemaName)) -and (($_.Condition.SourceTableName -eq $fk.Table) -or ("" -eq $_.Condition.SourceTableName))) }

            if (($null -ne $items) -and ($null -ne $items.Condition) -and ($items.Condition.MaxDepth -ne -1))
            {
                $maxDepth = [int]$items.Condition.MaxDepth
            }
        }
        return $maxDepth
    }

    function GetTop
    {
        param
        (
            [TableFk]$fk,
            [int]$color,
            [ColorMap]$colorMap
        )

        $top = $null

        if ($null -ne $colorMap)
        {
            $items = $colorMap.Items | Where-Object { ($_.SchemaName -eq $fk.FkSchema) -and ($_.TableName -eq $fk.FkTable) }
            $items = $items | Where-Object { ($null -eq $_.Condition) -or ($_.Condition.FkName -eq $fk.Name) -or ((($_.Condition.SourceSchemaName -eq $fk.Schema) -or ("" -eq $_.Condition.SourceSchemaName)) -and (($_.Condition.SourceTableName -eq $fk.Table) -or ("" -eq $_.Condition.SourceTableName))) }

            if (($null -ne $items) -and ($null -ne $items.Condition) -and ($items.Condition.Top -ne -1))
            {
                $top = [int]$items.Condition.Top
            }
        }
        return $top
    }
    function GetOutgoingColor
    {
        param
        (
            [TableFk]$fk,
            [int]$color,
            [ColorMap]$colorMap
        )

        if ($color -eq [int][Color]::Green)
        {
            $newColor = [int][Color]::Green
        }
        else
        {
            $newColor = [int][Color]::Red
        }

        if ($null -ne $colorMap)
        {
            $items = $colorMap.Items | Where-Object { ($_.SchemaName -eq $fk.Schema) -and ($_.TableName -eq $fk.Table) }
            $items = $items | Where-Object { ($null -eq $_.Condition) -or ((($_.Condition.SourceSchemaName -eq $fk.FkSchema) -or ("" -eq $_.Condition.SourceSchemaName)) -and (($_.Condition.SourceTableName -eq $fk.FkTable) -or ("" -eq $_.Condition.SourceTableName))) }
            if (($null -ne $items) -and ($null -ne $items.ForcedColor))
            {
                $newColor = [int]$items.ForcedColor.Color
            }
        }
        return $newColor
    }

    function CreateOutgoingQueryPattern
    {
        param
        (
            [TableInfo]$table,
            [int]$color,
            [ColorMap]$colorMap
        )

        $result = ""
        $primaryKey = $table.PrimaryKey
        $tableId = $tablesGroupedByName[$table.SchemaName + ", " + $table.TableName].Id

        $cond = ""
        for ($i = 0; $i -lt $table.PrimaryKey.Count; $i++)
        {
            if ($i -gt 0)
            {
                $cond += " and "
            }

            $cond = $cond + "(p.Key" + $i + " = s.Key" + $i + ")"
        }

        if ($table.ForeignKeys.Count -eq 0)
        {
            return $result
        }

        foreach ($fk in $table.ForeignKeys)
        {
            if ([TableInfo2]::IsIgnored($fk.Schema, $fk.Table, $ignoredTables) -eq $true)
            {
                continue
            }

            $newColor = GetOutgoingColor -color $color -fk $fk -colorMap $colorMap

            $baseTable = $DatabaseInfo.Tables | Where-Object { ($_.SchemaName -eq $fk.Schema) -and ($_.TableName -eq $fk.Table) }
            $baseTableId = $tablesGroupedByName[$fk.Schema + ", " + $fk.Table].Id
            $baseSignature = $structure.Tables[$baseTable]
            $baseProcessing = $structure.GetProcessingName($baseSignature, $SessionId)

            #where
            $columns = ""
            $i = 0
            foreach ($fkColumn in $fk.FkColumns)
            {
                if ($i -gt 0)
                {
                    $columns += " and "
                }
                $columns = $columns + " f." + $fkColumn.Name + " = p.Key" + $i
                $i += 1
            }
            $where = " WHERE " + $fk.FkColumns[0].Name + " IS NOT NULL AND NOT EXISTS(SELECT * FROM $baseProcessing p WHERE p.[Color] = $newColor AND $columns)"

            # from
            $join = " INNER JOIN $processing s ON "
            $i = 0
            foreach ($primaryKeyColumn in $primaryKey)
            {
                if ($i -gt 0)
                {
                    $join += " AND "
                }

                $join += " s.Key" + $i + " = f." + $primaryKeyColumn.Name
                $i += 1
            }

            $join += " AND s.Iteration IN (SELECT FoundIteration FROM SqlSizer.Operations o WHERE o.Status = 0 AND o.[SessionId] = '$SessionId') "
            $from = " FROM " + $table.SchemaName + "." + $table.TableName + " f " + $join

            # select
            $columns = ""
            $i = 0
            foreach ($fkColumn in $fk.FkColumns)
            {
                if ($columns -ne "")
                {
                    $columns += ","
                }
                $columns = $columns + (Get-ColumnValue -ColumnName $fkColumn.Name -Prefix "f." -DataType $fkColumn.dataType) + " as val$i "
                $i += 1
            }

            $select = "SELECT DISTINCT " + $columns + ", s.Depth"
            $sql = $select + $from + $where

            $columns = ""
            for ($i = 0; $i -lt $fk.FkColumns.Count; $i = $i + 1)
            {
                $columns = $columns + "x.val" + $i + ","
            }

            $fkId = $fkGroupedByName[$fk.FkSchema + ", " + $fk.FkTable + ", " + $fk.Name].Id

            $insert = " SELECT $columns " + $newColor + " as Color, $tableId as TableId, x.Depth + 1 as Depth, $fkId as FkId, ##iteration## as Iteration INTO #tmp2 FROM (" + $sql + ") x "
            $insert += " INSERT INTO $baseProcessing SELECT * FROM #tmp2 "
            $insert += " INSERT INTO SqlSizer.Operations SELECT $baseTableId, $newColor, t.[Count], 0, NULL, $tableId, $fkId, t.Depth, GETDATE(), NULL, '$SessionId', ##iteration##, NULL FROM (SELECT Depth, COUNT(*) as [Count] FROM #tmp2 GROUP BY Depth) t "
            $insert += " DROP TABLE #tmp2"

            if ($ConnectionInfo.IsSynapse -eq $false)
            {
                $insert += " 
                GO
                "
            }

            $result += $insert
        }

        return $result
    }

    function HandleOutgoing
    {
        param
        (
            [TableInfo]$table,
            [int]$color,
            [bool]$useDfs = $false,
            [ColorMap]$colorMap,
            [int]$iteration
        )

        $key = "$($table.SchemaName)_$($table.TableName)_$($color)"

        if ($outgoingCache.ContainsKey($key))
        {
            $query = $outgoingCache[$key]
        }
        else
        {
            $query = CreateOutgoingQueryPattern -table $table -color $color -useDfs $useDfs -colorMap $colorMap -iteration $iteration
            $outgoingCache[$key] = $query
        }

        if ($query -ne "")
        {
            $query = $query.Replace("##iteration##", $iteration)

            $null = Invoke-SqlcmdEx -Sql $query -Database $Database -ConnectionInfo $ConnectionInfo
        }
    }

    function CreateIncomingQueryPattern
    {
        param
        (
            [TableInfo]$table,
            [int]$color,
            [bool]$useDfs = $false,
            [ColorMap]$colorMap
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

                $newColor = GetIncomingNewColor -color $color -fk $fk -colorMap $colorMap
                $maxDepth = GetMaxDepth -color $color -fk $fk -colorMap $colorMap
                $top = GetTop -color $color -fk $fk -colorMap $colorMap

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
                $where = " WHERE " + $fk.FkColumns[0].Name + " IS NOT NULL AND NOT EXISTS(SELECT * FROM $fkProcessing p WHERE p.[Color] = $newColor AND $columns)"

                if ($null -ne $maxDepth)
                {
                    $where += " AND s.Depth <= $maxDepth"
                }

                # prevent go-back if this is not full search
                if ($FullSearch -eq $false)
                {
                    $where += " AND ((s.Fk <> $($fkId)) OR (s.Fk IS NULL))"
                }

                # from
                $join = " INNER JOIN $processing s ON "
                $i = 0

                foreach ($fkColumn in $fk.FkColumns)
                {
                    if ($i -gt 0)
                    {
                        $join += " AND "
                    }

                    $join += " s.Key$i = f.$($fkColumn.Name)"
                    $i += 1
                }

                $join += " AND s.Iteration IN (SELECT FoundIteration FROM SqlSizer.Operations o WHERE o.Status = 0 AND o.[SessionId] = '$SessionId') "
                $from = " FROM " + $referencedByTable.SchemaName + "." + $referencedByTable.TableName + " f " + $join

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

                $select = "SELECT DISTINCT " + $topPhrase + $columns + ", s.Depth"
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

                $insert += "SELECT $columns " + $newColor + " as Color, $tableId as TableId, x.Depth + 1 as Depth, $fkId as FkId, ##iteration## as Iteration INTO #tmp FROM (" + $sql + ") x SET @SqlSizerCount = @@ROWCOUNT "
                $insert += " INSERT INTO $fkProcessing SELECT * FROM #tmp "
                if ($MaxBatchSize -ne -1)
                {
                    # reset operation if MaxBatchSize limit is reached
                    $insert += "IF (@SqlSizerCount = $MaxBatchSize)
                                BEGIN
                                    UPDATE SqlSizer.Operations SET [Status] = NULL WHERE [SessionId] = '$SessionId' AND [Status] = 0 AND [Table] = $($table.Id)
                                END"
                }
                $insert += " INSERT INTO SqlSizer.Operations SELECT $fkTableId, $newColor, t.[Count], 0, NULL, $tableId, $fkId, t.Depth, GETDATE(), NULL, '$SessionId', ##iteration##, NULL FROM (SELECT Depth, COUNT(*) as [Count] FROM #tmp GROUP BY Depth) t "
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
            [bool]$useDfs = $false,
            [ColorMap]$colorMap,
            [int]$iteration
        )

        $key = "$($table.SchemaName)_$($table.TableName)_$($color)"

        if ($incomingCache.ContainsKey($key))
        {   
            $query = $incomingCache[$key]
        }
        else
        {
            $query = CreateIncomingQueryPattern -table $table -color $color -useDfs $useDfs -colorMap $colorMap
            $incomingCache[$key] = $query
        }

        if ($query -ne "")
        {
            $query = $query.Replace("##iteration##", $iteration)
            $null = Invoke-SqlcmdEx -Sql $query -Database $Database -ConnectionInfo $ConnectionInfo
        }
    }

    function CreateSplitQuery
    {
        param
        (
            [TableInfo]$table,
            [int]$color,
            [int]$depth,
            [int]$iteration
        )

        $result = ""
        $tableId = $tablesGroupedByName[$table.SchemaName + ", " + $table.TableName].Id

        $cond = ""
        for ($i = 0; $i -lt $table.PrimaryKey.Count; $i++)
        {
            if ($i -gt 0)
            {
                $cond += " and "
            }

            $cond = $cond + "(p.Key$i = s.Key$i )"
        }

        $columns = ""
        for ($i = 0; $i -lt $table.PrimaryKey.Count; $i++)
        {
            $columns = $columns + "s.Key$i,"
        }

        # red
        $where = " WHERE NOT EXISTS(SELECT * FROM $processing p WHERE p.[Color] = " + [int][Color]::Red + "  and " + $cond + ")"
        $where += " AND s.Iteration IN (SELECT FoundIteration FROM SqlSizer.Operations o WHERE o.Status = 0 AND o.[SessionId] = '$SessionId') "
        $q = " SELECT  $columns " + [int][Color]::Red + " as Color, s.Source, s.Depth, s.Fk, $iteration as Iteration INTO #tmp1 FROM $processing s" + $where
        $q += " INSERT INTO $processing SELECT * FROM #tmp1 "
        $q += " INSERT INTO SqlSizer.Operations SELECT $tableId, $([int][Color]::Red), t.[Count], 0, NULL, t.Source, t.Fk, t.Depth, GETDATE(), NULL, '$SessionId', $iteration, NULL FROM (SELECT Source, Depth, Fk, COUNT(*) as [Count] FROM #tmp1 GROUP BY Source, Depth, Fk) t "
        $result += $q

        # green
        $where = " WHERE NOT EXISTS(SELECT * FROM $processing p WHERE p.[Color] = " + [int][Color]::Green + " and " + $cond + ")"
        $where += " AND s.Iteration IN (SELECT FoundIteration FROM SqlSizer.Operations o WHERE o.Status = 0 AND o.[SessionId] = '$SessionId') "
        $q = " SELECT $columns " + [int][Color]::Green + " as Color, s.Source, s.Depth, s.Fk, $iteration as Iteration INTO #tmp2 FROM $processing s" + $where
        $q += " INSERT INTO $processing SELECT * FROM #tmp2 "
        $q += " INSERT INTO SqlSizer.Operations SELECT $tableId, $([int][Color]::Green), t.[Count], 0, NULL, t.Source, t.Fk, t.Depth, GETDATE(), NULL, '$SessionId', $iteration, NULL FROM (SELECT Source, Depth, Fk, COUNT(*) as [Count] FROM #tmp2 GROUP BY Source, Depth, Fk) t "
        $result += $q
        $result += "DROP TABLE #tmp1 DROP TABLE #tmp2"

        if ($ConnectionInfo.IsSynapse -eq $false)
        {
            $result += " 
            GO 
            "
        }

        return $result
    }

    function Split
    {
        param
        (
            [TableInfo]$table,
            [int]$color,
            [int]$depth,
            [bool]$useDfs,
            [int]$iteration
        )
        $query = CreateSplitQuery -table $table -color $color -depth $depth -iteration $iteration

        $null = Invoke-SqlcmdEx -Sql $query -Database $Database -ConnectionInfo $ConnectionInfo
    }


    function ShouldAddOutgoing
    {
        param
        (
            [int]$color
        )

        return ($color -eq [int][Color]::Red) -or (($FullSearch -eq $true) -and ($color -eq [int][Color]::Green)) -or ($color -eq [int][Color]::Purple)
    }

    function ShouldAddIncoming
    {
        param
        (
            [int]$color
        )

        return ($color -eq [int][Color]::Green) -or ($color -eq [int][Color]::Purple) -or ($color -eq [int][Color]::Blue)
    }

    function DoSearch()
    {
        param
        (
            [bool]$useDfs = $false,
            [int]$iteration
        )

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

        if ($false -eq $useDfs)
        {
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
        }
        else
        {
            $q = "SELECT TOP 1
                    [Table],
                    [Color],
                    SUM([ToProcess] - [Processed]) as [Count]
                FROM
                    [SqlSizer].[Operations]
                WHERE
                    ([Status] IS NULL OR [Status] = 0) AND [SessionId] = '$SessionId'
                GROUP BY
                    [Table], [Color]
                ORDER BY
                    [Count] DESC"
        }

        $operation = Invoke-SqlcmdEx -Sql $q -Database $Database -ConnectionInfo $ConnectionInfo

        if ($null -eq $operation)
        {
            Write-Progress -Activity "Finding subset" -Completed
            return $false
        }
        $tableId = $operation.Table
        $color = $operation.Color
        $depth = $operation.Depth
        $tableData = $tablesGroupedById["$($tableId)"]
        $table = $DatabaseInfo.Tables | Where-Object { ($_.SchemaName -eq $tableData.SchemaName) -and ($_.TableName -eq $tableData.TableName) }
        $table.Id = $tableId

        Write-Progress -Activity "Finding subset $SessionId" -CurrentOperation  "$($table.SchemaName).$($table.TableName) table is being processed with color $([Color]$color)" -PercentComplete $percent

        $signature = $structure.Tables[$table]
        $processing = $structure.GetProcessingName($signature, $SessionId)

        if ($false -eq $useDfs)
        {
            $q = "SELECT [Id], [ToProcess], [Processed] FROM [SqlSizer].[Operations] WHERE [Table] = $tableId AND Status IS NULL AND [Color] = $color AND [Depth] = $depth AND [SessionId] = '$SessionId'"
            $operations = Invoke-SqlcmdEx -Sql $q -Database $Database -ConnectionInfo $ConnectionInfo
        }
        else
        {
            $q = "SELECT [Id], [ToProcess], [Processed] FROM [SqlSizer].[Operations] WHERE [Table] = $tableId AND Status IS NULL AND [Color] = $color AND [SessionId] = '$SessionId'"
            $operations = Invoke-SqlcmdEx -Sql $q -Database $Database -ConnectionInfo $ConnectionInfo
        }

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

        $addOutgoing = ShouldAddOutgoing -color $color
        if ($true -eq $addOutgoing)
        {
            HandleOutgoing -table $table -color $color -useDfs $useDfs -colorMap $ColorMap -iteration $iteration
        }

        $addIncoming = ShouldAddIncoming -color $color
        if ($true -eq $addIncoming)
        {
            HandleIncoming -table $table -color $color -useDfs $useDfs -colorMap $ColorMap -iteration $iteration
        }

        # Yellow -> Split into Red and Green
        if ($color -eq [int][Color]::Yellow)
        {
            Split -table $table -useDfs $useDfs -iteration $iteration
        }

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
            $result = DoSearch -useDfs $UseDfs -iteration $iteration
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
            $result = DoSearch -useDfs $UseDfs -iteration $Iteration

            return [pscustomobject]@{
                Finished            = $result -eq $false
                Initialized         = $true
                CompletedIterations = 1
            }
        }
    }
}
