function Import-SubsetFromFileSet
{
    [cmdletbinding()]
    param
    (
        [Parameter(Mandatory = $true)]
        [string]$SourceDatabase,

        [Parameter(Mandatory = $true)]
        [string]$TargetDatabase,

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

        $tableSelect = Get-TableSelect -TableInfo $tableInfo -Conversion $false -Prefix $null -AddAs $false -SkipGenerated $true
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

        $identity_on = ""
        $identity_off = ""

        if ($tableInfo.IsIdentity)
        {
            $identity_on = "SET IDENTITY_INSERT " + $TargetDatabase + "." + $tableInfo.SchemaName + ".[" + $tableInfo.TableName + "] ON "
            $identity_off = "SET IDENTITY_INSERT " + $TargetDatabase + "." + $tableInfo.SchemaName + ".[" + $tableInfo.TableName + "] OFF "
        }


        $prefix = ''
        if ($TargetDatabase -ne $SourceDatabase)
        {
            $prefix = $SourceDatabase + "."
        }

        $sql = "DECLARE @json NVARCHAR(MAX); SELECT @json = STRING_AGG([Content], '') FROM $($prefix)SqlSizer.Files WHERE [FileId] = '$($file.FileId)'
                $identity_on

                INSERT INTO [$($tableInfo.SchemaName)].[$($tableInfo.TableName)] ($tableSelect)
                SELECT $tableSelect
                FROM OpenJson(@json) with ($([string]::join(', ', $columns)))

                $identity_off"
        $null = Invoke-SqlcmdEx -Sql $sql -Database $TargetDatabase -ConnectionInfo $ConnectionInfo
    }
}
