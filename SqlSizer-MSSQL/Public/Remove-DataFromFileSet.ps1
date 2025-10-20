function Remove-DataFromFileSet
{
    [cmdletbinding()]
    param
    (
        [Parameter(Mandatory = $true)]
        [string]$Database,

        [Parameter(Mandatory = $true)]
        [TableFile[]]$Files,

        [Parameter(Mandatory = $true)]
        [DatabaseInfo]$DatabaseInfo,

        [Parameter(Mandatory = $true)]
        [SqlConnectionInfo]$ConnectionInfo
    )

    foreach ($file in $Files)
    {
        $tableInfo = $DatabaseInfo.Tables | Where-Object { ($_.SchemaName -eq $file.TableContent.SchemaName) -and ($_.TableName -eq $file.TableContent.TableName) }
        $where = @()
        foreach ($column in $tableInfo.PrimaryKey)
        {
            $where += "t.$($column.Name) = o.$($column.Name)"
        }

        $columns = @()
        foreach ($column in $tableInfo.Columns)
        {
            if ($column.IsComputed)
            {
                continue
            }

            if ($column.DataType -in @('geography', 'hierarchyid', 'xml'))
            {
                $type = 'varchar(max)'
            }
            else
            {
                $type = $column.DataType

                if ($type -in @('nvarchar', 'varchar'))
                {
                    $type += "(max)"
                }
            }

            $columns += "[" + $column.Name + "] " + $type
        }

        $sql = "DECLARE @json NVARCHAR(MAX); SELECT @json = STRING_AGG([Content], '') FROM SqlSizer.Files WHERE [FileId] = '$($file.FileId)'
                DELETE t
                FROM OpenJson(@json) with ($([string]::join(', ', $columns)))  as o
                INNER JOIN [$($tableInfo.SchemaName)].[$($tableInfo.TableName)] t ON $([string]::join(' and ', $where))"
        $null = Invoke-SqlcmdEx -Sql $sql -Database $Database -ConnectionInfo $ConnectionInfo
    }
}

