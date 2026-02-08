function Install-SqlSizerResultViews
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
        $tableSelect = Get-TableSelect -TableInfo $table -Conversion $false -IgnoredTables $IgnoredTables -Prefix "t." -AddAs $true -SkipGenerated $false -MaxLength $null
        $join = GetResultViewsTableJoin -TableInfo $table -Structure $structure

        if ($null -eq $join)
        {
            continue
        }

        $sql = "CREATE VIEW SqlSizer_$($SessionId).Result_$($table.SchemaName)_$($table.TableName) AS SELECT $tableSelect, sqlsizer_state from $($table.SchemaName).$($table.TableName) t INNER JOIN $join"
        $null = Invoke-SqlcmdEx -Sql $sql -Database $Database -ConnectionInfo $ConnectionInfo -Statistics $false
    }
}

function GetResultViewsTableJoin
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

    $select = [System.Collections.Generic.List[string]]@()
    $join = [System.Collections.Generic.List[string]]@()

    $i = 0
    foreach ($column in $primaryKey)
    {
        $null = $select.Add("p.Key$i")
        $null = $join.Add("t.$column = rr.Key$i")
        $i = $i + 1
    }

    $sql = " (SELECT $([string]::Join(',', $select)), [State] as sqlsizer_state
               FROM $($processing) p) rr ON $([string]::Join(' and ', $join))"

    return $sql
}

