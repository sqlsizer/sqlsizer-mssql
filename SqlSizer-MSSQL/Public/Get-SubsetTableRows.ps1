function Get-SubsetTableRows
{
    [cmdletbinding()]
    param
    (
        [Parameter(Mandatory = $true)]
        [string]$SessionId,

        [Parameter(Mandatory = $true)]
        [string]$Database,

        [Parameter(Mandatory = $true)]
        [string]$SchemaName,

        [Parameter(Mandatory = $true)]
        [string]$TableName,

        [Parameter(Mandatory = $false)]
        [int]$Iteration = -1,

        [Parameter(Mandatory = $false)]
        [bool]$AllColumns = $false,

        [Parameter(Mandatory = $false)]
        [TableInfo2[]]$IgnoredTables,

        [Parameter(Mandatory = $true)]
        [DatabaseInfo]$DatabaseInfo,

        [Parameter(Mandatory = $true)]
        [SqlConnectionInfo]$ConnectionInfo
    )

    $structure = [Structure]::new($DatabaseInfo)

    foreach ($table in $DatabaseInfo.Tables)
    {
        if (($table.SchemaName -eq $SchemaName) -and ($table.TableName -eq $TableName))
        {
            $processing = $structure.GetProcessingName($structure.Tables[$table], $SessionId)

            if ($AllColumns -eq $false)
            {
                $keys = ""
                for ($i = 0; $i -lt $table.PrimaryKey.Count; $i++)
                {
                    $keys += "Key$($i) as $($table.PrimaryKey[$i].Name)"

                    if ($i -lt ($table.PrimaryKey.Count - 1))
                    {
                        $keys += ", "
                    }
                }

                $sql = "SELECT DISTINCT '$($table.SchemaName)' as SchemaName,'$($table.TableName)' as TableName, $($keys) FROM $($processing) WHERE ([Iteration] = $Iteration OR $Iteration = -1)"
                $rows = Invoke-SqlcmdEx -Sql $sql -Database $Database -ConnectionInfo $ConnectionInfo
                return $rows
            }
            else
            {
                $columns = ""

                for ($i = 0; $i -lt $table.Columns.Count; $i++)
                {
                    $include = $true
                    foreach ($fk in $table.ForeignKeys)
                    {
                        if ([TableInfo2]::IsIgnored($fk.Schema, $fk.Table, $ignoredTables) -eq $true)
                        {
                            foreach ($fkColumn in $fk.FkColumns)
                            {
                                if ($fkColumn.Name -eq $table.Columns[$i].Name)
                                {
                                    $include = $false
                                    break
                                }
                            }
                        }
                    }

                    if ($include)
                    {
                        $columns += "ISNULL(t.[$($table.Columns[$i].Name)], '') as [$($table.Columns[$i].Name)]"
                    }
                    else
                    {
                        $columns += "NULL as [$($table.Columns[$i].Name)]"
                    }

                    if ($i -lt ($table.Columns.Count - 1))
                    {
                        $columns += ", "
                    }
                }

                $cond = ""
                for ($i = 0; $i -lt $table.PrimaryKey.Count; $i++)
                {
                    $cond += "t.$($table.PrimaryKey[$i].Name) = p.Key$($i)"
                    if ($i -lt ($table.PrimaryKey.Count - 1))
                    {
                        $cond += " and "
                    }
                }
                $sql = "SELECT '$($table.SchemaName)' as SchemaName, '$($table.TableName)' as TableName, $($columns)
                        FROM $($processing) p
                        INNER JOIN $($table.SchemaName).$($table.TableName) t ON $($cond)
                        WHERE ([Iteration] = $Iteration OR $Iteration = -1)"
                $rows = Invoke-SqlcmdEx -Sql $sql -Database $Database -ConnectionInfo $ConnectionInfo
                return $rows
            }
        }
    }

    return $null
}
