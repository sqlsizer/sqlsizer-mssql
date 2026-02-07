function Get-SqlSizerInfo
{
    [cmdletbinding()]
    param
    (
        [Parameter(Mandatory = $true)]
        [string]$Database,

        [Parameter(Mandatory = $true)]
        [SqlConnectionInfo]$ConnectionInfo
    )

    $sql = "SELECT [Id],[Schema],[TableName] FROM [SqlSizer].[Tables]"
    $tablesRows = Invoke-SqlcmdEx -Sql $sql -Database $Database -ConnectionInfo $ConnectionInfo

    $sql = "SELECT
        f.[Id]
        ,[FkTableId]
        ,[TableId]
        ,[Name]
		,ft.[Schema]
		,ft.[TableName]
        FROM [SqlSizer].[ForeignKeys] f
	INNER JOIN [SqlSizer].[Tables] ft ON f.FkTableId = ft.Id"
    $fkRows = Invoke-SqlcmdEx -Sql $sql -Database $Database -ConnectionInfo $ConnectionInfo

    $tables = $tablesRows | ForEach-Object {
        [pscustomobject] @{
            Id         = $_.Id
            SchemaName = $_.Schema
            TableName  = $_.TableName
        }
    }

    $fks = $fkRows  | ForEach-Object {
        [pscustomobject] @{
            Id           = $_.Id
            Name         = $_.Name
            FkSchemaName = $_.Schema
            FkTableName  = $_.TableName
        }
    }

    $result = [pscustomobject]@{
        Tables      = $tables
        ForeignKeys = $fks
    }

    return $result
}
