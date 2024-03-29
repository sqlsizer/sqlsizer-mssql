﻿function Find-Subset
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
# SIG # Begin signature block
# MIIoigYJKoZIhvcNAQcCoIIoezCCKHcCAQExDzANBglghkgBZQMEAgEFADB5Bgor
# BgEEAYI3AgEEoGswaTA0BgorBgEEAYI3AgEeMCYCAwEAAAQQH8w7YFlLCE63JNLG
# KX7zUQIBAAIBAAIBAAIBAAIBADAxMA0GCWCGSAFlAwQCAQUABCAssYOuHOyyXOG8
# OPQX/kE5GJ7Si3ESVqYzJvJ6Smc8pqCCIL4wggXJMIIEsaADAgECAhAbtY8lKt8j
# AEkoya49fu0nMA0GCSqGSIb3DQEBDAUAMH4xCzAJBgNVBAYTAlBMMSIwIAYDVQQK
# ExlVbml6ZXRvIFRlY2hub2xvZ2llcyBTLkEuMScwJQYDVQQLEx5DZXJ0dW0gQ2Vy
# dGlmaWNhdGlvbiBBdXRob3JpdHkxIjAgBgNVBAMTGUNlcnR1bSBUcnVzdGVkIE5l
# dHdvcmsgQ0EwHhcNMjEwNTMxMDY0MzA2WhcNMjkwOTE3MDY0MzA2WjCBgDELMAkG
# A1UEBhMCUEwxIjAgBgNVBAoTGVVuaXpldG8gVGVjaG5vbG9naWVzIFMuQS4xJzAl
# BgNVBAsTHkNlcnR1bSBDZXJ0aWZpY2F0aW9uIEF1dGhvcml0eTEkMCIGA1UEAxMb
# Q2VydHVtIFRydXN0ZWQgTmV0d29yayBDQSAyMIICIjANBgkqhkiG9w0BAQEFAAOC
# Ag8AMIICCgKCAgEAvfl4+ObVgAxknYYblmRnPyI6HnUBfe/7XGeMycxca6mR5rlC
# 5SBLm9qbe7mZXdmbgEvXhEArJ9PoujC7Pgkap0mV7ytAJMKXx6fumyXvqAoAl4Va
# qp3cKcniNQfrcE1K1sGzVrihQTib0fsxf4/gX+GxPw+OFklg1waNGPmqJhCrKtPQ
# 0WeNG0a+RzDVLnLRxWPa52N5RH5LYySJhi40PylMUosqp8DikSiJucBb+R3Z5yet
# /5oCl8HGUJKbAiy9qbk0WQq/hEr/3/6zn+vZnuCYI+yma3cWKtvMrTscpIfcRnNe
# GWJoRVfkkIJCu0LW8GHgwaM9ZqNd9BjuiMmNF0UpmTJ1AjHuKSbIawLmtWJFfzcV
# WiNoidQ+3k4nsPBADLxNF8tNorMe0AZa3faTz1d1mfX6hhpneLO/lv403L3nUlbl
# s+V1e9dBkQXcXWnjlQ1DufyDljmVe2yAWk8TcsbXfSl6RLpSpCrVQUYJIP4ioLZb
# MI28iQzV13D4h1L92u+sUS4Hs07+0AnacO+Y+lbmbdu1V0vc5SwlFcieLnhO+Nqc
# noYsylfzGuXIkosagpZ6w7xQEmnYDlpGizrrJvojybawgb5CAKT41v4wLsfSRvbl
# jnX98sy50IdbzAYQYLuDNbdeZ95H7JlI8aShFf6tjGKOOVVPORa5sWOd/7cCAwEA
# AaOCAT4wggE6MA8GA1UdEwEB/wQFMAMBAf8wHQYDVR0OBBYEFLahVDkCw6A/joq8
# +tT4HKbROg79MB8GA1UdIwQYMBaAFAh2zcsH/yT2xc3tu5C84oQ3RnX3MA4GA1Ud
# DwEB/wQEAwIBBjAvBgNVHR8EKDAmMCSgIqAghh5odHRwOi8vY3JsLmNlcnR1bS5w
# bC9jdG5jYS5jcmwwawYIKwYBBQUHAQEEXzBdMCgGCCsGAQUFBzABhhxodHRwOi8v
# c3ViY2Eub2NzcC1jZXJ0dW0uY29tMDEGCCsGAQUFBzAChiVodHRwOi8vcmVwb3Np
# dG9yeS5jZXJ0dW0ucGwvY3RuY2EuY2VyMDkGA1UdIAQyMDAwLgYEVR0gADAmMCQG
# CCsGAQUFBwIBFhhodHRwOi8vd3d3LmNlcnR1bS5wbC9DUFMwDQYJKoZIhvcNAQEM
# BQADggEBAFHCoVgWIhCL/IYx1MIy01z4S6Ivaj5N+KsIHu3V6PrnCA3st8YeDrJ1
# BXqxC/rXdGoABh+kzqrya33YEcARCNQOTWHFOqj6seHjmOriY/1B9ZN9DbxdkjuR
# mmW60F9MvkyNaAMQFtXx0ASKhTP5N+dbLiZpQjy6zbzUeulNndrnQ/tjUoCFBMQl
# lVXwfqefAcVbKPjgzoZwpic7Ofs4LphTZSJ1Ldf23SIikZbr3WjtP6MZl9M7JYjs
# NhI9qX7OAo0FmpKnJ25FspxihjcNpDOO16hO0EoXQ0zF8ads0h5YbBRRfopUofbv
# n3l6XYGaFpAP4bvxSgD5+d2+7arszgowggaUMIIEfKADAgECAhAr1K5wudBjWyrp
# hMjWdKowMA0GCSqGSIb3DQEBDAUAMFYxCzAJBgNVBAYTAlBMMSEwHwYDVQQKExhB
# c3NlY28gRGF0YSBTeXN0ZW1zIFMuQS4xJDAiBgNVBAMTG0NlcnR1bSBUaW1lc3Rh
# bXBpbmcgMjAyMSBDQTAeFw0yMjA3MjgwODU2MjZaFw0zMzA3MjcwODU2MjZaMFAx
# CzAJBgNVBAYTAlBMMSEwHwYDVQQKDBhBc3NlY28gRGF0YSBTeXN0ZW1zIFMuQS4x
# HjAcBgNVBAMMFUNlcnR1bSBUaW1lc3RhbXAgMjAyMjCCAiIwDQYJKoZIhvcNAQEB
# BQADggIPADCCAgoCggIBAMrFXu0fCUbwRMtqXliGb6KwhLCeP4vySHEqQBI78xFc
# jqQae26x7v21UvkWS+X0oTh61yTcdoZaQAg5hNcBqWbGn7b8OOEXkGwUvGZ65MWK
# l2lXBjisc6d1GWVI5fXkP9+ddLVX4G/pP7eIdAtI5Fh4rGC/x9/vNan9C8C4I56N
# 525HwiKzqPSz6Z5N2XYM0+bT4VdYsZxyPRwLkjhcqdzg2tCB2+YP6ld+uBOkcfCr
# hFCeeTB4Y/ZalrZXaCGFIlBWjIyXb9UGspAaoDvP2LCSSRcnvrP49qIIGD7TqHbD
# oYumubWDgx8/YE7M5Bfd7F14mQOqnr7ImCFS5Ty/nfSO7XVSQ6TrlIYX8rLA4BSj
# nOu0WoYZTLOWyaekWPraAAhvzJQ3mXt6ruGa6VEljyzDTUfgEmSDpnxP6OFSOOc4
# xBOXbkV8OO4ivGf0pIff+IOsysOwvuSSHfF1FxSerNZb3VcUneyQaT+omC+kaGTP
# pvsyly53V/MUKuHVhgRIrGiWIJgN9Tr73oZXHk6mbuzkXiHhao/1AQrQ35q+mtGK
# vnXtf62dsJFztYf/XceELTw/KJd1YL7hlQ9zGR/fFE+fx9pvLd2yZ3Y1PCtpaNzq
# 6i7JZ2mRldC1XwikBtjoQ6GT2T3kyRn0lAU8Y4/TdN/4pptwouFk+75JsdToPQ6B
# AgMBAAGjggFiMIIBXjAMBgNVHRMBAf8EAjAAMB0GA1UdDgQWBBQjwTzMUzMZVo7Y
# 4/POPPyoc0dW6jAfBgNVHSMEGDAWgBS+VAIvv0Bsc0POrAklTp5DRBru4DAOBgNV
# HQ8BAf8EBAMCB4AwFgYDVR0lAQH/BAwwCgYIKwYBBQUHAwgwMwYDVR0fBCwwKjAo
# oCagJIYiaHR0cDovL2NybC5jZXJ0dW0ucGwvY3RzY2EyMDIxLmNybDBvBggrBgEF
# BQcBAQRjMGEwKAYIKwYBBQUHMAGGHGh0dHA6Ly9zdWJjYS5vY3NwLWNlcnR1bS5j
# b20wNQYIKwYBBQUHMAKGKWh0dHA6Ly9yZXBvc2l0b3J5LmNlcnR1bS5wbC9jdHNj
# YTIwMjEuY2VyMEAGA1UdIAQ5MDcwNQYLKoRoAYb2dwIFAQswJjAkBggrBgEFBQcC
# ARYYaHR0cDovL3d3dy5jZXJ0dW0ucGwvQ1BTMA0GCSqGSIb3DQEBDAUAA4ICAQBr
# xvc9Iz4vV5D57BeApm1pfVgBjTKWgflb1htxJA9HSvXneq/j/+5kohu/1p0j6IJM
# YTpSbT7oHAtg59m0wM0HnmrjcN43qMNo5Ts/gX/SBmY0qMzdlO6m1D9egn7U49Eg
# GO+IZFAnmMH1hLx+pse6dgtThZ4aqr+zRfRNoTFNSUxyOSo6cmVKfRbZgTiLEcMe
# hGJTeM5CQs1AmDpF+hqyq0X6Mv0BMtHU2wPoVlI3xrRQ167lM64/gl8dCYzMPF8l
# 8W89ds2Rfro9Y1p5dI0L8x60opb1f8n5Hf4ayW9Kc7rgUdlnfJc4cYdvV0JxWYpS
# ZPN5LJM54xSKrveXnYq1NNIuovqJOM9mixVMJ2TTWPkfQ2pl0H/ZokxxXB4qEKAy
# Sa6bfcijoQiOaR5wKQR+0yrc7KIdqt+hOVhl5uUti9cZxA8JMiNdX6SaasglnJ9o
# lTSMJ4BRO6tCASEvJeeCzX6ZViKRDHbFQCaMZ1XdxlwR6Cqkfa2p5EN1DKQSjxI1
# p6lddQmc9PTVGWM8dpbRKtHHBoOQvfWEdigP3EI7RGZqWTonwr8AaMCgTzYbFpuZ
# ed3lG7yi0jwUJo9/ryUNFA82m9CpzLcaAKaLQ0s1uboR6zaWSt9fqUASNz9zD+8I
# iGlyUqKIAFViQMqqyHej0vK7G2gPqEy5GDdxL/DBaTCCBrkwggShoAMCAQICEQCZ
# o4AKJlU7ZavcboSms+o5MA0GCSqGSIb3DQEBDAUAMIGAMQswCQYDVQQGEwJQTDEi
# MCAGA1UEChMZVW5pemV0byBUZWNobm9sb2dpZXMgUy5BLjEnMCUGA1UECxMeQ2Vy
# dHVtIENlcnRpZmljYXRpb24gQXV0aG9yaXR5MSQwIgYDVQQDExtDZXJ0dW0gVHJ1
# c3RlZCBOZXR3b3JrIENBIDIwHhcNMjEwNTE5MDUzMjE4WhcNMzYwNTE4MDUzMjE4
# WjBWMQswCQYDVQQGEwJQTDEhMB8GA1UEChMYQXNzZWNvIERhdGEgU3lzdGVtcyBT
# LkEuMSQwIgYDVQQDExtDZXJ0dW0gQ29kZSBTaWduaW5nIDIwMjEgQ0EwggIiMA0G
# CSqGSIb3DQEBAQUAA4ICDwAwggIKAoICAQCdI88EMCM7wUYs5zNzPmNdenW6vlxN
# ur3rLfi+5OZ+U3iZIB+AspO+CC/bj+taJUbMbFP1gQBJUzDUCPx7BNLgid1TyztV
# Ln52NKgxxu8gpyTr6EjWyGzKU/gnIu+bHAse1LCitX3CaOE13rbuHbtrxF2tPU8f
# 253QgX6eO8yTbGps1Mg+yda3DcTsOYOhSYNCJiL+5wnjZ9weoGRtvFgMHtJg6i67
# 1OPXIciiHO4Lwo2p9xh/tnj+JmCQEn5QU0NxzrOiRna4kjFaA9ZcwSaG7WAxeC/x
# oZSxF1oK1UPZtKVt+yrsGKqWONoK6f5EmBOAVEK2y4ATDSkb34UD7JA32f+Rm0ws
# r5ajzftDhA5mBipVZDjHpwzv8bTKzCDUSUuUmPo1govD0RwFcTtMXcfJtm1i+P2U
# NXadPyYVKRxKQATHN3imsfBiNRdN5kiVVeqP55piqgxOkyt+HkwIA4gbmSc3hD8k
# e66t9MjlcNg73rZZlrLHsAIV/nJ0mmgSjBI/TthoGJDydekOQ2tQD2Dup/+sKQpt
# alDlui59SerVSJg8gAeV7N/ia4mrGoiez+SqV3olVfxyLFt3o/OQOnBmjhKUANoK
# LYlKmUpKEFI0PfoT8Q1W/y6s9LTI6ekbi0igEbFUIBE8KDUGfIwnisEkBw5KcBZ3
# XwnHmfznwlKo8QIDAQABo4IBVTCCAVEwDwYDVR0TAQH/BAUwAwEB/zAdBgNVHQ4E
# FgQU3XRdTADbe5+gdMqxbvc8wDLAcM0wHwYDVR0jBBgwFoAUtqFUOQLDoD+Oirz6
# 1PgcptE6Dv0wDgYDVR0PAQH/BAQDAgEGMBMGA1UdJQQMMAoGCCsGAQUFBwMDMDAG
# A1UdHwQpMCcwJaAjoCGGH2h0dHA6Ly9jcmwuY2VydHVtLnBsL2N0bmNhMi5jcmww
# bAYIKwYBBQUHAQEEYDBeMCgGCCsGAQUFBzABhhxodHRwOi8vc3ViY2Eub2NzcC1j
# ZXJ0dW0uY29tMDIGCCsGAQUFBzAChiZodHRwOi8vcmVwb3NpdG9yeS5jZXJ0dW0u
# cGwvY3RuY2EyLmNlcjA5BgNVHSAEMjAwMC4GBFUdIAAwJjAkBggrBgEFBQcCARYY
# aHR0cDovL3d3dy5jZXJ0dW0ucGwvQ1BTMA0GCSqGSIb3DQEBDAUAA4ICAQB1iFgP
# 5Y9QKJpTnxDsQ/z0O23JmoZifZdEOEmQvo/79PQg9nLF/GJe6ZiUBEyDBHMtFRK0
# mXj3Qv3gL0sYXe+PPMfwmreJHvgFGWQ7XwnfMh2YIpBrkvJnjwh8gIlNlUl4KENT
# K5DLqsYPEtRQCw7R6p4s2EtWyDDr/M58iY2UBEqfUU/ujR9NuPyKk0bEcEi62JGx
# auFYzZ/yld13fHaZskIoq2XazjaD0pQkcQiIueL0HKiohS6XgZuUtCKA7S6CHttZ
# EsObQJ1j2s0urIDdqF7xaXFVaTHKtAuMfwi0jXtF3JJphrJfc+FFILgCbX/uYBPB
# lbBIP4Ht4xxk2GmfzMn7oxPITpigQFJFWuzTMUUgdRHTxaTSKRJ/6Uh7ki/pFjf9
# sUASWgxT69QF9Ki4JF5nBIujxZ2sOU9e1HSCJwOfK07t5nnzbs1LbHuAIGJsRJiQ
# 6HX/DW1XFOlXY1rc9HufFhWU+7Uk+hFkJsfzqBz3pRO+5aI6u5abI4Qws4YaeJH7
# H7M8X/YNoaArZbV4Ql+jarKsE0+8XvC4DJB+IVcvC9Ydqahi09mjQse4fxfef0L7
# E3hho2O3bLDM6v60rIRUCi2fJT2/IRU5ohgyTch4GuYWefSBsp5NPJh4QRTP9DC3
# gc5QEKtbrTY0Ka87Web7/zScvLmvQBm8JDFpDjCCBrkwggShoAMCAQICEQDn/2nH
# OzXOS5Em2HR8aKWHMA0GCSqGSIb3DQEBDAUAMIGAMQswCQYDVQQGEwJQTDEiMCAG
# A1UEChMZVW5pemV0byBUZWNobm9sb2dpZXMgUy5BLjEnMCUGA1UECxMeQ2VydHVt
# IENlcnRpZmljYXRpb24gQXV0aG9yaXR5MSQwIgYDVQQDExtDZXJ0dW0gVHJ1c3Rl
# ZCBOZXR3b3JrIENBIDIwHhcNMjEwNTE5MDUzMjA3WhcNMzYwNTE4MDUzMjA3WjBW
# MQswCQYDVQQGEwJQTDEhMB8GA1UEChMYQXNzZWNvIERhdGEgU3lzdGVtcyBTLkEu
# MSQwIgYDVQQDExtDZXJ0dW0gVGltZXN0YW1waW5nIDIwMjEgQ0EwggIiMA0GCSqG
# SIb3DQEBAQUAA4ICDwAwggIKAoICAQDpEh8ENe25XXrFppVBvoplf0530W0lddNm
# jtv4YSh/f7eDQKFaIqc7tHj7ox+u8vIsJZlroakUeMS3i3T8aJRC+eQs4FF0Gqvk
# M6+WZO8kmzZfxmZaBYmMLs8FktgFYCzywmXeQ1fEExflee2OpbHVk665eXRHjH7M
# YZIzNnjl2m8Hy8ulB9mR8wL/W0v0pjKNT6G0sfrx1kk+3OGosFUb7yWNnVkWKU4q
# SxLv16kJ6oVJ4BSbZ4xMak6JLeB8szrK9vwGDpvGDnKCUMYL3NuviwH1x4gZG0JA
# XU3x2pOAz91JWKJSAmRy/l0s0l5bEYKolg+DMqVhlOANd8Yh5mkQWaMEvBRE/kAG
# zIqgWhwzN2OsKIVtO8mf5sPWSrvyplSABAYa13rMYnzwfg08nljZHghquCJYCa/x
# HK9acev9UD7Y+usr15d7mrszzxhF1JOr1Mpup2chNSBlyOObhlSO16rwrffVrg/S
# zaKfSndS5swRhr8bnDqNJY9TNyEYvBYpgF95K7p0g4LguR4A++Z1nFIHWVY5v0fN
# VZmgzxD9uVo/gta3onGOQj3JCxgYx0KrCXu4yc9QiVwTFLWbNdHFSjBCt5/8Q9pL
# uRhVocdCunhcHudMS1CGQ/Rn0+7P+fzMgWdRKfEOh/hjLrnQ8BdJiYrZNxvIOhM2
# aa3zEDHNwwIDAQABo4IBVTCCAVEwDwYDVR0TAQH/BAUwAwEB/zAdBgNVHQ4EFgQU
# vlQCL79AbHNDzqwJJU6eQ0Qa7uAwHwYDVR0jBBgwFoAUtqFUOQLDoD+Oirz61Pgc
# ptE6Dv0wDgYDVR0PAQH/BAQDAgEGMBMGA1UdJQQMMAoGCCsGAQUFBwMIMDAGA1Ud
# HwQpMCcwJaAjoCGGH2h0dHA6Ly9jcmwuY2VydHVtLnBsL2N0bmNhMi5jcmwwbAYI
# KwYBBQUHAQEEYDBeMCgGCCsGAQUFBzABhhxodHRwOi8vc3ViY2Eub2NzcC1jZXJ0
# dW0uY29tMDIGCCsGAQUFBzAChiZodHRwOi8vcmVwb3NpdG9yeS5jZXJ0dW0ucGwv
# Y3RuY2EyLmNlcjA5BgNVHSAEMjAwMC4GBFUdIAAwJjAkBggrBgEFBQcCARYYaHR0
# cDovL3d3dy5jZXJ0dW0ucGwvQ1BTMA0GCSqGSIb3DQEBDAUAA4ICAQC4k1l3yUwV
# /ZQHCKCneqAs8EGTnwEUJLdDpokN/dMhKjK0rR5qX8nIIHzxpQR3TAw2IRw1Uxsr
# 2PliG3bCFqSdQTUbfaTq6V3vBzEebDru9QFjqlKnxCF2h1jhLNFFplbPJiW+JSnJ
# Th1fKEqEdKdxgl9rVTvlxfEJ7exOn25MGbd/wGPwuSmMxRJVO0wnqgS7kmoJjNF9
# zqeehFSDDP8ZVkWg4EZ2tIS0M3uZmByRr+1Lkwjjt8AtW83mVnZTyTsOb+FNfwJY
# 7DS4FmWhkRbgcHRetreoTirPOr/ozyDKhT8MTSTf6Lttg6s6T/u08mDWw6HK04ZR
# DfQ9sb77QV8mKgO44WGP31vXnVKoWVJpFBjPvjL8/Zck/5wXX2iqjOaLStFOR/IQ
# ki+Ehn4zlcgVm22ZVCBPF+l8nAwUUShCtKuSU7GmZLKCmmxQMkSiWILTm8EtVD6A
# xnJhoq8EnhjEEyUoflkeRF2WhFiVQOmWTwZRr44IxWGkNJC6tTorW5rl2Zl+2e9J
# LPYf3pStAPMDoPKIjVXd6NW2+fZrNUBeDo2eOa5Fn7Brs/HLQff5Xgris5MeUbdV
# gDrF8uxO6cLPvZPo63j62SsNg55pTWk9fUIF9iPoRbb4QurjoY/woI1RAOKtYtTi
# c6aAJq3u83RIPpGXBSJKwx4KJAOZnCDCtTCCBtswggTDoAMCAQICEGKUqNjbtPSE
# Tu16moosTdUwDQYJKoZIhvcNAQELBQAwVjELMAkGA1UEBhMCUEwxITAfBgNVBAoT
# GEFzc2VjbyBEYXRhIFN5c3RlbXMgUy5BLjEkMCIGA1UEAxMbQ2VydHVtIENvZGUg
# U2lnbmluZyAyMDIxIENBMB4XDTIyMDcwNjE3NTkxOFoXDTIzMDcwNjE3NTkxN1ow
# gYAxCzAJBgNVBAYTAlBMMRIwEAYDVQQIDAlwb21vcnNraWUxHTAbBgNVBAoMFE1h
# cmNpbiBHb8WCxJliaW93c2tpMR0wGwYDVQQDDBRNYXJjaW4gR2/FgsSZYmlvd3Nr
# aTEfMB0GCSqGSIb3DQEJARYQeG9ybXVzQGdtYWlsLmNvbTCCAiIwDQYJKoZIhvcN
# AQEBBQADggIPADCCAgoCggIBAKr2WuURfyFgf3jRzAxUJ8B4MGl2pgHcGnvTjeiB
# L6xwGlWzYiF1ucSUW8MkgulVc+WT2yNXK+Sm2F8IyZzskB0R+vZfp5hPMl8GoyB7
# oEtuwunEJDIoUCWatRMvVPCT7+TlL0+fZuPnQ3oqnY+AqT/ET8Im8oVO0McJndqa
# Rfto1k7ak3No4u1W/274hu4DelYAxeb9mpNeFnYfkAruoYsgN9NVhD9FMOrdcwG8
# ic7tQGPoMXa9C8qdgyeXESSrgSkcHXq62TwEVoK7Hv2A73e/hlxzPqX5VwUkZkV1
# jwCwQwj0kGIPFzVUpx4gruYWuJ5btHwHtZlB7IhpQBwuQkF0XtWmJ6IWzR2RKyyx
# GHt2BYbBCTDEMVwpM5mLP4KkuwOcpJL2sgKCVquX29X9oPpqqQzeIHhsbyvAmlrf
# xQFUz690JeDYLr3d2HpxD7jzniJcDaq4sf/bxdtqU1ZIAXAI1KErB6B6VWQoesWx
# dPDXSTbmhw/7d8adUYGhxWicUY0Vp9N7r2oEsL7hA73hsccveJBeHovUDUt2yVYZ
# xMNfBA+a94d2gXDy4dPfZ1CmT7ifQ38ClgkDWZUxekjhtx+1WPnYT4F4SuGneKDI
# l9JnRztt6xG0UTIMcLgzE5NrLlaKdILPXG/qP4VRJRyjEJgdD1IwvAfTdAYGaXLX
# z6O9AgMBAAGjggF4MIIBdDAMBgNVHRMBAf8EAjAAMD0GA1UdHwQ2MDQwMqAwoC6G
# LGh0dHA6Ly9jY3NjYTIwMjEuY3JsLmNlcnR1bS5wbC9jY3NjYTIwMjEuY3JsMHMG
# CCsGAQUFBwEBBGcwZTAsBggrBgEFBQcwAYYgaHR0cDovL2Njc2NhMjAyMS5vY3Nw
# LWNlcnR1bS5jb20wNQYIKwYBBQUHMAKGKWh0dHA6Ly9yZXBvc2l0b3J5LmNlcnR1
# bS5wbC9jY3NjYTIwMjEuY2VyMB8GA1UdIwQYMBaAFN10XUwA23ufoHTKsW73PMAy
# wHDNMB0GA1UdDgQWBBSbo4Vic2BmodM1NmsAW4N1/N0VlDBLBgNVHSAERDBCMAgG
# BmeBDAEEATA2BgsqhGgBhvZ3AgUBBDAnMCUGCCsGAQUFBwIBFhlodHRwczovL3d3
# dy5jZXJ0dW0ucGwvQ1BTMBMGA1UdJQQMMAoGCCsGAQUFBwMDMA4GA1UdDwEB/wQE
# AwIHgDANBgkqhkiG9w0BAQsFAAOCAgEADZ14LtIisUdnaERD8OHOpbMMZY7zloi7
# aVuP0euezvciM5l0S/1y6LdwQKyC8EoLm8ImdSW5HL9rgLmdDhAZlmFqDf+OrscM
# 3rOIvOY/Zs0VmRY5cOn6Ht760PvPsdBSHodPhZ3zCTASWUaakf+AI3cRBkEqzqtY
# R4L4+9RhLyDTkCIAKdRYzBhmNAGWziI6iW9EwnxxNR8JxVsYdspcgb7wVKI0IFDZ
# 0JzXIotahi1+tAHgS+PXWXrffC6jG3Zr7ZdNanxYTDn4wyT11fNuT1MJDMCOpuvt
# IsnXQexxVsVovSzf/4wtaKQp4nyckgjrSQQUkFRTT5ynyEALBhEs42o8zY61WaKI
# 2jWjZeLAALFBooIiEK0hye/UqcxEc2q76Diub8H7HFMO3+fIsFDZMaXB3JBmoZW4
# X8CX45nv76Vdt6ldlH/6WzS1J3LdfW51kbOwby8ZLZkyz6cawcsfmeiHMzY9w3aL
# 459i7xeLEn57BfDZMvi3F24LoAEA6D2CM/vvCK2+KL5nzbNhaq1Ksfl7QDDdhg88
# tz8qsHjY6PEEcwedcB9YEc9yEuMaLNmxTjga0hi5yIL7FsXZ/tqf5kmLwUSyO7r5
# azilEYS1PQ4O5y+UWURDQ7tKH6CbPE5QuQ35kDfGaVMQziExOW1QQKwf0N0R393c
# 184HgEAr0bUxggciMIIHHgIBATBqMFYxCzAJBgNVBAYTAlBMMSEwHwYDVQQKExhB
# c3NlY28gRGF0YSBTeXN0ZW1zIFMuQS4xJDAiBgNVBAMTG0NlcnR1bSBDb2RlIFNp
# Z25pbmcgMjAyMSBDQQIQYpSo2Nu09IRO7XqaiixN1TANBglghkgBZQMEAgEFAKCB
# hDAYBgorBgEEAYI3AgEMMQowCKACgAChAoAAMBkGCSqGSIb3DQEJAzEMBgorBgEE
# AYI3AgEEMBwGCisGAQQBgjcCAQsxDjAMBgorBgEEAYI3AgEVMC8GCSqGSIb3DQEJ
# BDEiBCCRx6HWizmoqOYe2DW6tqnzj/EVjrO7mFnsFZS+grKasTANBgkqhkiG9w0B
# AQEFAASCAgCiSwwC6kiHMsCqksQqIVzW+SeZ7hKX8Lo6ue5nXk5TvPuQC87fSr5P
# F3c59jqwQay8uutBu9wJ3ApnD8v2/OsGywC/difmRaW7jiKfgkjvYmb/G2A8oDba
# yQtczflwstAJXOoFN+SHS6TIpKo7TKPuwCAQUI5ILqpVz5nr9LIX54hFcsrGGu+8
# EZy5YS5lgd4XS85j8zJSIkzYoKBBkeHChcq+pwnqnlN0S6eo5tKFwd93wyCRQsJB
# qJyUmlaICCznAInakjQDQOnxBUxGJFD8csCZCjzqmU/E7cHf2es/EtGfiCel4nBh
# xXDUSCsXzF8F0QoLzbSC4v7WT4YphpA2ubpZAj5412AZRaEVAj9KWoUNRgs9WEbu
# nbNXTi5TwyNunuSRp/hO8xOB8wuZEgJxuQMZ+gVkbg/1LjxPOKT6WEH1vv3+GSTK
# UQmYijL6FJH9+GqW+kwdecJYwskd07OTlWvf9KaexS9Sdy3HCtU1ZUNLK9HS3sCv
# fcOPKaw9CGk4XsoDFgH8q+x9mQpPFZ98GCU9fWfvToAEY0GVPN4jCLZmCN++RrGe
# QKkPs3mbVqOuR6YmHWFSNChXEjA+yfkCJYxIWtNG5hwtUgRkdziGlLqqmVHf0NuR
# JboL0CmgFAGceHouC2MazjSUGkhnIZu5FzLkQoB91VODSOeGGeu2rqGCBAIwggP+
# BgkqhkiG9w0BCQYxggPvMIID6wIBATBqMFYxCzAJBgNVBAYTAlBMMSEwHwYDVQQK
# ExhBc3NlY28gRGF0YSBTeXN0ZW1zIFMuQS4xJDAiBgNVBAMTG0NlcnR1bSBUaW1l
# c3RhbXBpbmcgMjAyMSBDQQIQK9SucLnQY1sq6YTI1nSqMDANBglghkgBZQMEAgIF
# AKCCAVYwGgYJKoZIhvcNAQkDMQ0GCyqGSIb3DQEJEAEEMBwGCSqGSIb3DQEJBTEP
# Fw0yMzAyMTgyMzAyMzZaMDcGCyqGSIb3DQEJEAIvMSgwJjAkMCIEIAO5mmRJdJhK
# lbbMXYDTRNB0+972yiQEhCvmzw5EIgeKMD8GCSqGSIb3DQEJBDEyBDC6vUjXUB3Q
# KxyDgs2B9WSEpAU5GOBVd2WLefAu8YJ6BKblLorCTgnazryG1pnbwgIwgZ8GCyqG
# SIb3DQEJEAIMMYGPMIGMMIGJMIGGBBS/T2vEmC3eFQWo78jHp51NFDUAzjBuMFqk
# WDBWMQswCQYDVQQGEwJQTDEhMB8GA1UEChMYQXNzZWNvIERhdGEgU3lzdGVtcyBT
# LkEuMSQwIgYDVQQDExtDZXJ0dW0gVGltZXN0YW1waW5nIDIwMjEgQ0ECECvUrnC5
# 0GNbKumEyNZ0qjAwDQYJKoZIhvcNAQEBBQAEggIAK1N8Xiz3UHZYULQ6roD4wE0y
# acffnegbryXNIthQH3lMkitWwwdnVGGRxnEgRg/IDyGA6d2rsS/s0bbWByK0jm/4
# 6qX4SQn01+hM9l31ZAxEemLrW5BdsALftSCJ3H5nUuOijF4ECZUQZDDwcKOMN3Ib
# LYYhWusvkRPSOFknnLOpebXlhogBzaZnftlOyGQuQwVC8Ip2XEetBYeH1VXZffKC
# N50CMdKoCoESzGvSmm0Tnh1KaJsy7GKy4/eb4b6pecuN5/bXuQmKh2wbspSBjWGD
# DzicqFzum2oA8AB76A2kZgMfOBmYR1Ezeyien0e4Qwd45dWuDLk0njrMPTTqtz1D
# rb2uQz/lD3OedtkKPi+LEAB49+itk2vAdlc2+5MqY+viiRJBLxTIm8P2mpRIs3m1
# 98jK5C5Xwpx7vxwaOZaAT8mElvmSRrmmEjthPWvvRM0XMpr0bAXD2KfyDfP4gIhV
# GucSuci8bAZyTMx2eZS7AgjodAT9ynQM8Sy23NoJbCm5O0trAPGupCYA0RZykDzZ
# rjV9/FyV1LKKL+/rmayvaEoIvNOA/cWzHOxgaROdk5c5mtMF548j2a/wBhWZsh9p
# 8iuqw78k9fE2j2arUTVQw6RG+D+EkRz6dtnPkzkdGtHECDn9swYudi8RvhgE09VV
# EerckqUtNGsexpDWj8w=
# SIG # End signature block
