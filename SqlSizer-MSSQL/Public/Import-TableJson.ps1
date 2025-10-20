function Import-TableJson
{
    [cmdletbinding()]
    param
    (
        [Parameter(Mandatory = $true)]
        [string]$Database,

        [Parameter(Mandatory = $true)]
        [string]$SchemaName,

        [Parameter(Mandatory = $true)]
        [string]$TableName,

        [Parameter(Mandatory = $true)]
        [string]$Json,

        [Parameter(Mandatory = $true)]
        [DatabaseInfo]$DatabaseInfo,

        [Parameter(Mandatory = $true)]
        [SqlConnectionInfo]$ConnectionInfo
    )

    $tableInfo = $DatabaseInfo.Tables | Where-Object { ($_.SchemaName -eq $SchemaName) -and ($_.TableName -eq $TableName) }

    if ($null -eq $tableInfo)
    {
        throw "Table $SchemaName.$TableName was not found in database info."
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

    $tableSelect = Get-TableSelect -TableInfo $tableInfo -Conversion $false -Prefix $null -AddAs $false -SkipGenerated $true

    $sql = "DECLARE @json NVARCHAR(MAX); SET @json = N'" + $Json + "'
            $identity_on

            INSERT INTO [$($tableInfo.SchemaName)].[$($tableInfo.TableName)] ($tableSelect)
            SELECT $tableSelect
            FROM OpenJson(@json) with ($([string]::join(', ', $columns)))

            $identity_off"

    $null = Invoke-SqlcmdEx -Sql $sql -Database $Database -ConnectionInfo $ConnectionInfo
}
