function Copy-DataFromSubset
{
    [cmdletbinding()]
    param
    (
        [Parameter(Mandatory = $true)]
        [string]$SessionId,

        [Parameter(Mandatory = $true)]
        [string]$Source,

        [Parameter(Mandatory = $true)]
        [string]$Destination,

        [Parameter(Mandatory = $true)]
        [DatabaseInfo]$DatabaseInfo,

        [Parameter(Mandatory = $false)]
        [TableInfo2[]]$IgnoredTables,

        [Parameter(Mandatory = $true)]
        [SqlConnectionInfo]$ConnectionInfo
    )

    $i = 0
    $subsetTables = Get-SubsetTables -Database $Source -Connection $ConnectionInfo -DatabaseInfo $DatabaseInfo -SessionId $SessionId

    foreach ($table in $subsetTables)
    {
        $i += 1

        $tableInfo = $DatabaseInfo.Tables | Where-Object { ($_.SchemaName -eq $table.SchemaName) -and ($_.TableName -eq $table.TableName) }
        Write-Progress -Activity "Copying data" -PercentComplete (100 * ($i / ($subsetTables.Count))) -CurrentOperation "Table $($table.SchemaName).$($table.TableName)"

        if ($tableInfo.IsHistoric -eq $true)
        {
            continue
        }

        $isIdentity = $tableInfo.IsIdentity
        $schema = $tableInfo.SchemaName
        $tableName = $tableInfo.TableName
        $tableColumns = Get-TableSelect -TableInfo $tableInfo -Conversion $false -IgnoredTables $IgnoredTables -Prefix $null -AddAs $false -SkipGenerated $true
        $tableSelect = Get-TableSelect -TableInfo $tableInfo -Conversion $true -IgnoredTables $IgnoredTables -Prefix $null -AddAs $true -SkipGenerated $true

        $sql = "INSERT INTO " + $schema + ".[" + $tableName + "] ($tableColumns) SELECT DISTINCT $tableSelect FROM " + $Source + ".[SqlSizer_$SessionId].Result_" + $schema + "_" + $tableName
        if ($isIdentity)
        {
            $sql = "SET IDENTITY_INSERT " + $schema + ".[" + $tableName + "] ON " + $sql + " SET IDENTITY_INSERT " + $schema + ".[" + $tableName + "] OFF"
        }
        $null = Invoke-SqlcmdEx -Sql $sql -Database $Destination -ConnectionInfo $ConnectionInfo
    }

    Write-Progress -Activity "Copying data" -Completed
}
