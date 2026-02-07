function Get-TableSelect
{
    param (
        [bool]$Conversion,
        [bool]$SkipGenerated = $true,
        [string]$Prefix,
        [TableInfo]$TableInfo,
        [TableInfo2[]]$IgnoredTables,
        [bool]$AddAs,
        [bool]$Array = $false,
        [bool]$OnlyXml = $false,
        [string]$MaxLength = $null
    )

    $result = [System.Collections.Generic.List[string]]@()

    $j = 0
    for ($i = 0; $i -lt $TableInfo.Columns.Count; $i++)
    {
        $select = ""
        $column = $TableInfo.Columns[$i]
        $columnName = $column.Name

        if ($SkipGenerated -and (($column.IsComputed -eq $true) -or ($column.IsGenerated -eq $true) -or ($column.DataType -eq "timestamp")))
        {
            continue
        }
        else
        {
            $include = $true

            foreach ($fk in $TableInfo.ForeignKeys)
            {
                if ([TableInfo2]::IsIgnored($fk.Schema, $fk.Table, $ignoredTables) -eq $true)
                {
                    foreach ($fkColumn in $fk.FkColumns)
                    {
                        if ($fkColumn.Name -eq $columnName)
                        {
                            $include = $false
                            break
                        }
                    }
                }
            }

            if ($include)
            {
                $select += Get-ColumnValue -ColumnName $columnName -DataType $column.DataType -Prefix "$Prefix" -Conversion $Conversion -OnlyXml $OnlyXml -MaxLength $MaxLength
            }
            else
            {
                $select += " NULL "
            }

            if ($AddAs)
            {
                $select += " as [$columnName]"
            }

            $j += 1
            $null = $result.Add($select)
        }
    }

    if ($Array)
    {
        return $result
    }
    else
    {
        return [string]::join(', ', $result)
    }
}
