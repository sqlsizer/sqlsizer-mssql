function Find-UnreachableTables
{
    [cmdletbinding()]
    param
    (
        [Parameter(Mandatory = $true)]
        [Query2[]]$Queries,

        [Parameter(Mandatory = $false)]
        [TraversalConfiguration]$TraversalConfig = $null,

        [Parameter(Mandatory = $true)]
        [DatabaseInfo]$DatabaseInfo
    )

    $reachableTables = New-Object 'System.Collections.Generic.HashSet[string]'
    $processedTableStates = New-Object 'System.Collections.Generic.HashSet[string]'
    $processingQueue = New-Object System.Collections.Generic.Queue"[TableInfo2WithState]"

    # Add all tables to processing
    foreach ($query in $Queries)
    {
        $item = New-Object TableInfo2WithState
        $item.SchemaName = $query.Schema
        $item.TableName = $query.Table
        $item.State = $query.State

        $null = $processingQueue.Enqueue($item)
    }

    while ($true)
    {
        if ($processingQueue.Count -eq 0)
        {
            break
        }

        $item = $processingQueue.Dequeue()
        $key = $item.SchemaName + "." + $item.TableName + "." + $item.State

        if ($processedTableStates.Contains($key))
        {
            continue
        }

        $table = $DatabaseInfo.Tables.Where(({ ($_.TableName -eq $item.TableName) -and ($_.SchemaName -eq $item.SchemaName) }))[0]

        if ($item.State -eq [TraversalState]::Pending)
        {
            $newItem = New-Object TableInfo2WithState
            $newItem.SchemaName = $item.SchemaName
            $newItem.TableName = $item.TableName
            $newItem.State = [TraversalState]::Include
            $null = $processingQueue.Enqueue($newItem)

            $newItem = New-Object TableInfo2WithState
            $newItem.SchemaName = $item.SchemaName
            $newItem.TableName = $item.TableName
            $newItem.State = [TraversalState]::Exclude
            $null = $processingQueue.Enqueue($newItem)
        }

        if ($item.State -eq [TraversalState]::Exclude)
        {
            foreach ($fk in $table.ForeignKeys)
            {
                $newItem = New-Object TableInfo2WithState
                $newItem.SchemaName = $fk.Schema
                $newItem.TableName = $fk.Table

                $newState = [TraversalState]::Exclude
                if ($null -ne $TraversalConfig)
                {
                    $rule = $TraversalConfig.GetItemForTable($fk.Schema, $fk.Table)
                    if ($null -eq $rule)
                    {
                        $rules = $TraversalConfig.Rules | Where-Object { ($_.SchemaName -eq $fk.Schema) -and ($_.TableName -eq $fk.Table) }
                        $rules = $rules | Where-Object { ($null -eq $_.Constraints) -or ((($_.Constraints.SourceSchemaName -eq $fk.FkSchema) -or ("" -eq $_.Constraints.SourceSchemaName)) -and (($_.Constraints.SourceTableName -eq $fk.FkTable) -or ("" -eq $_.Constraints.SourceTableName))) }
                        $rule = $rules | Select-Object -First 1
                    }
                    if (($null -ne $rule) -and ($null -ne $rule.StateOverride))
                    {
                        $newState = $rule.StateOverride.State
                    }
                }

                $newItem.State = $newState
                $null = $processingQueue.Enqueue($newItem)
            }
        }

        if (($item.State -eq [TraversalState]::Include) -or ($item.State -eq [TraversalState]::InboundOnly))
        {
            foreach ($referencedByTable in $table.IsReferencedBy)
            {
                $fks = $referencedByTable.ForeignKeys | Where-Object { ($_.Schema -eq $item.SchemaName) -and ($_.Table -eq $item.TableName) }
                foreach ($fk in $fks)
                {
                    $newItem = New-Object TableInfo2WithState
                    $newItem.SchemaName = $fk.FkSchema
                    $newItem.TableName = $fk.FkTable

                    if ($item.State -eq [TraversalState]::Include)
                    {
                        $newItem.State = [TraversalState]::Pending
                    }
                    if ($item.State -eq [TraversalState]::InboundOnly)
                    {
                        $newItem.State = [TraversalState]::InboundOnly
                    }

                    # forced state from traversal config
                    if ($null -ne $TraversalConfig)
                    {
                        $rule = $TraversalConfig.GetItemForTable($fk.FkSchema, $fk.FkTable)
                        if ($null -eq $rule)
                        {
                            $rules = $TraversalConfig.Rules | Where-Object { ($_.SchemaName -eq $fk.FkSchema) -and ($_.TableName -eq $fk.FkTable) }
                            $rules = $rules | Where-Object { ($null -eq $_.Constraints) -or ((($_.Constraints.SourceSchemaName -eq $fk.Schema) -or ("" -eq $_.Constraints.SourceSchemaName)) -and (($_.Constraints.SourceTableName -eq $fk.Table) -or ("" -eq $_.Constraints.SourceTableName))) }
                            $rule = $rules | Select-Object -First 1
                        }

                        if (($null -ne $rule) -and ($null -ne $rule.StateOverride))
                        {
                            $newItem.State = $rule.StateOverride.State
                        }
                    }

                    $null = $processingQueue.Enqueue($newItem)
                }
            }
        }

        $null = $reachableTables.Add($item.SchemaName + "." + $item.TableName)
        $null = $processedTableStates.Add($key)
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
