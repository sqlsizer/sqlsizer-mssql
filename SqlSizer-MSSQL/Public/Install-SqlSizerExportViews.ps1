function Install-SqlSizerExportViews
{
    [cmdletbinding()]
    param
    (
        [Parameter(Mandatory = $true)]
        [string]$SessionId,

        [Parameter(Mandatory = $true)]
        [string]$Database,

        [Parameter(Mandatory = $true)]
        [DatabaseInfo]$DatabaseInfo,

        [Parameter(Mandatory = $true)]
        [SqlConnectionInfo]$ConnectionInfo,

        [Parameter(Mandatory = $false)]
        [TableInfo2[]]$IgnoredTables
    )

    $schemaExists = Test-SchemaExists -SchemaName "SqlSizer_$SessionId" -Database $Database -ConnectionInfo $ConnectionInfo
    if ($schemaExists -eq $false)
    {
        $tmp = "CREATE SCHEMA SqlSizer_$SessionId"
        $null = Invoke-SqlcmdEx -Sql $tmp -Database $Database -ConnectionInfo $ConnectionInfo -Statistics $false
    }

    $structure = [Structure]::new($DatabaseInfo)

    foreach ($table in $DatabaseInfo.Tables)
    {
        if ($table.SchemaName.StartsWith('SqlSizer'))
        {
            continue
        }

        $tableSelect = Get-TableSelect -TableInfo $table -Conversion $true -IgnoredTables $IgnoredTables -Prefix "t." -AddAs $true -SkipGenerated $true -MaxLength $null
        $join = GetExportViewsTableJoin -TableInfo $table -Structure $structure

        if ($null -eq $join)
        {
            continue
        }

        $sql = "CREATE VIEW SqlSizer_$($SessionId).Export_$($table.SchemaName)_$($table.TableName) AS SELECT ROW_NUMBER() OVER(ORDER BY (SELECT NULL)) AS SqlSizer_RowSequence, $tableSelect from $($table.SchemaName).$($table.TableName) t INNER JOIN $join"
        $null = Invoke-SqlcmdEx -Sql $sql -Database $Database -ConnectionInfo $ConnectionInfo -Statistics $false
    }
}

function GetExportViewsTableJoin
{
    param (
        [TableInfo]$TableInfo,
        [Structure]$Structure
    )

    $primaryKey = $TableInfo.PrimaryKey
    $signature = $Structure.Tables[$TableInfo]

    if (($null -eq $signature) -or ($signature -eq ""))
    {
        return $null
    }

    $processing = $Structure.GetProcessingName($signature, $SessionId)
    $select = @()
    $join = @()

    $i = 0
    foreach ($column in $primaryKey)
    {
        $select += "p.Key$i"
        $join += "t.$column = rr.Key$i"
        $i = $i + 1
    }

    $sql = " (SELECT DISTINCT $([string]::Join(',', $select))
             FROM $($processing) p) rr ON $([string]::Join(' and ', $join))"

    return $sql
}
