function Find-UnreachableTables
{
    [cmdletbinding()]
    param
    (
        [Parameter(Mandatory = $true)]
        [Query[]]$Queries,

        [Parameter(Mandatory = $false)]
        [ColorMap]$ColorMap = $null,

        [Parameter(Mandatory = $true)]
        [DatabaseInfo]$DatabaseInfo
    )

    $reachableTables = New-Object 'System.Collections.Generic.HashSet[string]'
    $processedTableColors = New-Object 'System.Collections.Generic.HashSet[string]'
    $processingQueue = New-Object System.Collections.Generic.Queue"[TableInfo2WithColor]"

    # Add all tables to processing
    foreach ($query in $Queries)
    {
        $item = New-Object TableInfo2WithColor
        $item.SchemaName = $query.Schema
        $item.TableName = $query.Table
        $item.Color = $query.Color

        $null = $processingQueue.Enqueue($item)
    }

    while ($true)
    {
        if ($processingQueue.Count -eq 0)
        {
            break
        }

        $item = $processingQueue.Dequeue()
        $key = $item.SchemaName + "." + $item.TableName + "." + $item.Color

        if ($processedTableColors.Contains($key))
        {
            continue
        }

        $table = $DatabaseInfo.Tables.Where(({ ($_.TableName -eq $item.TableName) -and ($_.SchemaName -eq $item.SchemaName) }))[0]

        if ($item.Color -eq [Color]::Yellow)
        {
            $newItem = New-Object TableInfo2WithColor
            $newItem.SchemaName = $item.SchemaName
            $newItem.TableName = $item.TableName
            $newItem.Color = [Color]::Green
            $null = $processingQueue.Enqueue($newItem)

            $newItem = New-Object TableInfo2WithColor
            $newItem.SchemaName = $item.SchemaName
            $newItem.TableName = $item.TableName
            $newItem.Color = [Color]::Red
            $null = $processingQueue.Enqueue($newItem)
        }

        if (($item.Color -eq [Color]::Red) -or ($item.Color -eq [Color]::Purple))
        {
            foreach ($fk in $table.ForeignKeys)
            {
                $newItem = New-Object TableInfo2WithColor
                $newItem.SchemaName = $fk.Schema
                $newItem.TableName = $fk.Table

                $newColor = [Color]::Red
                if ($null -ne $ColorMap)
                {
                    $items = $ColorMap.Items | Where-Object { ($_.SchemaName -eq $fk.Schema) -and ($_.TableName -eq $fk.Table) }
                    $items = $items | Where-Object { ($null -eq $_.Condition) -or ((($_.Condition.SourceSchemaName -eq $fk.FkSchema) -or ("" -eq $_.Condition.SourceSchemaName)) -and (($_.Condition.SourceTableName -eq $fk.FkTable) -or ("" -eq $_.Condition.SourceTableName))) }
                    if (($null -ne $items) -and ($null -ne $items.ForcedColor))
                    {
                        $newColor = [int]$items.ForcedColor.Color
                    }
                }

                $newItem.Color = $newColor
                $null = $processingQueue.Enqueue($newItem)
            }
        }

        if (($item.Color -eq [Color]::Green) -or ($item.Color -eq [Color]::Blue) -or ($item.Color -eq [Color]::Purple))
        {
            foreach ($referencedByTable in $table.IsReferencedBy)
            {
                $fks = $referencedByTable.ForeignKeys | Where-Object { ($_.Schema -eq $item.SchemaName) -and ($_.Table -eq $item.TableName) }
                foreach ($fk in $fks)
                {
                    $newItem = New-Object TableInfo2WithColor
                    $newItem.SchemaName = $fk.FkSchema
                    $newItem.TableName = $fk.FkTable

                    if ($item.Color -eq [Color]::Green)
                    {
                        $newItem.Color = [Color]::Yellow
                    }
                    if ($item.Color -eq [Color]::Blue)
                    {
                        $newItem.Color = [Color]::Blue
                    }

                    if ($item.Color -eq [int][Color]::Purple)
                    {
                        $newItem.Color = [int][Color]::Red
                    }

                    # forced color from color map
                    if ($null -ne $ColorMap)
                    {
                        $items = $ColorMap.Items | Where-Object { ($_.SchemaName -eq $fk.FkSchema) -and ($_.TableName -eq $fk.FkTable) }
                        $items = $items | Where-Object { ($null -eq $_.Condition) -or ((($_.Condition.SourceSchemaName -eq $fk.Schema) -or ("" -eq $_.Condition.SourceSchemaName)) -and (($_.Condition.SourceTableName -eq $fk.Table) -or ("" -eq $_.Condition.SourceTableName))) }

                        if (($null -ne $items) -and ($null -ne $items.ForcedColor))
                        {
                            $newItem.Color = [int]$items.ForcedColor.Color
                        }
                    }

                    $null = $processingQueue.Enqueue($newItem)
                }
            }
        }

        $null = $reachableTables.Add($item.SchemaName + "." + $item.TableName)
        $null = $processedTableColors.Add($key)
    }

    $toReturn = @()

    foreach ($table in $DatabaseInfo.Tables)
    {
        if ($table.SchemaName -in @('SqlSizer', 'SqlSizerHistory'))
        {
            continue
        }

        if ($table.SchemaName.StartsWith('SqlSizer'))
        {
            continue
        }

        $key = $table.SchemaName + "." + $table.TableName

        if ($reachableTables.Contains($key) -eq $false)
        {
            $item = New-Object TableInfo2

            $item.SchemaName = $table.SchemaName
            $item.TableName = $table.TableName

            $toReturn += $item
        }
    }

    return $toReturn
}
