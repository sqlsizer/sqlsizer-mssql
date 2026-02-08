function Compare-SavedSubsets
{
    [cmdletbinding()]
    param
    (
        [Parameter(Mandatory = $true)]
        [string]$SourceDatabase,

        [Parameter(Mandatory = $true)]
        [string]$TargetDatabase,

        [Parameter(Mandatory = $true)]
        [string]$SourceSubsetGuid,

        [Parameter(Mandatory = $true)]
        [string]$TargetSubsetGuid,

        [Parameter(Mandatory = $true)]
        [SqlConnectionInfo]$ConnectionInfo
    )

    #TODO: make it faster someday

    $sourceTables = Get-SavedSubsetTables -Database $SourceDatabase -SubsetGuid $SourceSubsetGuid -ConnectionInfo $ConnectionInfo
    $targetTables = Get-SavedSubsetTables -Database $TargetDatabase -SubsetGuid $TargetSubsetGuid -ConnectionInfo $ConnectionInfo

    $changed = @()
    $removed = @()
    $added = @()

    foreach ($sourceTable in $sourceTables)
    {
        $found = $false
        foreach ($targetTable in $targetTables)
        {
            if (($sourceTable.SchemaName -eq $targetTable.SchemaName) -and ($sourceTable.TableName -eq $targetTable.TableName))
            {
                $found = $true
                break
            }
        }

        if ($found -eq $true)
        {
            $keys = @()
            $conds = @()
            for ($i = 0; $i -lt $sourceTable.PrimaryKeySize; $i++)
            {
                $keys += "t.Key$i as Key$i"
                $conds += "t.Key$i = s.Key$i"
            }

            #query database to find changed data based on HASH

            $sql = "SELECT $([string]::Join(',', $keys))
                    FROM $($TargetDatabase).[SqlSizerHistory].[SubsetTableRow_$($targetTable.PrimaryKeySize)] t
                    INNER JOIN $($SourceDatabase).[SqlSizerHistory].[SubsetTableRow_$($sourceTable.PrimaryKeySize)] s ON $([string]::Join(' AND ', $conds))
                    WHERE t.Hash <> s.Hash AND t.TableId = $($targetTable.TableId) AND s.TableId = $($sourceTable.TableId)"

            $changeRows = Invoke-SqlcmdEx -Sql $sql -Database $SourceDatabase -ConnectionInfo $ConnectionInfo

            foreach ($changeRow in $changeRows)
            {
                $key = @()
                foreach ($item in $changeRow)
                {
                    $key += $item
                }

                $changed += [pscustomobject] @{
                    SchemaName = $sourceTable.SchemaName
                    TableName  = $sourceTable.TableName
                    Key        = $key
                }
            }

            $keys = @()
            for ($i = 0; $i -lt $sourceTable.PrimaryKeySize; $i++)
            {
                $keys += "s.Key$i as Key$i"
            }

            $sql = "SELECT $([string]::Join(',', $keys))
                FROM $($SourceDatabase).[SqlSizerHistory].[SubsetTableRow_$($sourceTable.PrimaryKeySize)] s
                LEFT JOIN $($TargetDatabase).[SqlSizerHistory].[SubsetTableRow_$($targetTable.PrimaryKeySize)] t ON t.TableId = $($targetTable.TableId) AND $([string]::Join(' AND ', $conds))
                WHERE t.Key0 IS NULL AND s.TableId = $($sourceTable.TableId)"
            $removedRows = Invoke-SqlcmdEx -Sql $sql -Database $SourceDatabase -ConnectionInfo $ConnectionInfo

            foreach ($removedRow in $removedRows)
            {
                $key = @()
                foreach ($item in $removedRow)
                {
                    $key += $item
                }

                $removed += [pscustomobject] @{
                    SchemaName = $sourceTable.SchemaName
                    TableName  = $sourceTable.TableName
                    Key        = $key
                }
            }
        }
        else
        {
            $keys = @()
            for ($i = 0; $i -lt $sourceTable.PrimaryKeySize; $i++)
            {
                $keys += "s.Key$i as Key$i"
            }

            $sql = "SELECT $([string]::Join(',', $keys))
                FROM $($SourceDatabase).[SqlSizerHistory].[SubsetTableRow_$($sourceTable.PrimaryKeySize)] s
                WHERE s.TableId = $($sourceTable.TableId)"

            $removedRows = Invoke-SqlcmdEx -Sql $sql -Database $SourceDatabase -ConnectionInfo $ConnectionInfo

            foreach ($removedRow in $removedRows)
            {
                $key = @()
                foreach ($item in $removedRow)
                {
                    $key += $item
                }

                $removed += [pscustomobject] @{
                    SchemaName = $sourceTable.SchemaName
                    TableName  = $sourceTable.TableName
                    Key        = $key
                }
            }
        }
    }

    foreach ($targetTable in $targetTables)
    {
        $found = $false
        foreach ($sourceTable in $sourceTables)
        {
            if (($sourceTable.SchemaName -eq $targetTable.SchemaName) -and ($sourceTable.TableName -eq $targetTable.TableName))
            {
                $found = $true
                break
            }
        }

        $keys = @()
        $conds = @()
        for ($i = 0; $i -lt $targetTable.PrimaryKeySize; $i++)
        {
            $keys += "t.Key$i as Key$i"
            $conds += "t.Key$i = s.Key$i"
        }

        if ($found -eq $true)
        {
            $sql = "SELECT $([string]::Join(',', $keys))
            FROM $($TargetDatabase).[SqlSizerHistory].[SubsetTableRow_$($targetTable.PrimaryKeySize)] t
            LEFT JOIN $($SourceDatabase).[SqlSizerHistory].[SubsetTableRow_$($sourceTable.PrimaryKeySize)] s ON s.TableId = $($targetTable.TableId) AND $([string]::Join(' AND ', $conds))
            WHERE s.Key0 IS NULL AND t.TableId = $($targetTable.TableId)"

            $addedRows = Invoke-SqlcmdEx -Sql $sql -Database $SourceDatabase -ConnectionInfo $ConnectionInfo

            foreach ($addedRow in $addedRows)
            {
                $key = @()
                foreach ($item in $addedRow)
                {
                    $key += $item
                }

                $added += [pscustomobject] @{
                    SchemaName = $sourceTable.SchemaName
                    TableName  = $sourceTable.TableName
                    Key        = $key
                }
            }
        }
        else
        {
            $sql = "SELECT $([string]::Join(',', $keys))
            FROM $($TargetDatabase).[SqlSizerHistory].[SubsetTableRow_$($targetTable.PrimaryKeySize)] t
            WHERE t.TableId = $($targetTable.TableId)"

            $addedRows = Invoke-SqlcmdEx -Sql $sql -Database $SourceDatabase -ConnectionInfo $ConnectionInfo

            foreach ($addedRow in $addedRows)
            {
                $key = @()
                foreach ($item in $addedRow)
                {
                    $key += $item
                }

                $added += [pscustomobject] @{
                    SchemaName = $sourceTable.SchemaName
                    TableName  = $sourceTable.TableName
                    Key        = $key
                }
            }
        }
    }

    $result = [pscustomobject]@{
        ChangedData = $changed
        AddedData   = $added
        RemovedData = $removed
    }

    return $result

}
