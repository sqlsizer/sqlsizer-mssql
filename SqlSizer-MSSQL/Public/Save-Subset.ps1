function Save-Subset
{
    [cmdletbinding()]
    param
    (
        [Parameter(Mandatory = $true)]
        [string]$SessionId,

        [Parameter(Mandatory = $true)]
        [string]$SubsetName,

        [Parameter(Mandatory = $true)]
        [string]$Database,

        [Parameter(Mandatory = $true)]
        [DatabaseInfo]$DatabaseInfo,

        [Parameter(Mandatory = $true)]
        [SqlConnectionInfo]$ConnectionInfo
    )

    $guid = (New-Guid).ToString()

    $sql = "INSERT INTO SqlSizerHistory.Subset([Guid], [Name]) VALUES('$guid', '$SubsetName') SELECT SCOPE_IDENTITY() as Id"
    $result = Invoke-SqlcmdEx -Sql $sql -Database $Database -ConnectionInfo $ConnectionInfo
    $subsetId = $result.Id

    $tables = Get-SubsetTables -Database $Database -DatabaseInfo $DatabaseInfo -ConnectionInfo $ConnectionInfo -SessionId $SessionId
    foreach ($table in $tables)
    {
        $sql = "INSERT INTO SqlSizerHistory.SubsetTable([SchemaName], [TableName], [PrimaryKeySize], [RowCount], [SubsetId]) VALUES('$($table.SchemaName)', '$($table.TableName)', $($table.PrimaryKeySize), $($table.RowCount), $subsetId)  SELECT SCOPE_IDENTITY() as TableId"
        $result = Invoke-SqlcmdEx -Sql $sql -Database $Database -ConnectionInfo $ConnectionInfo
        $tableId = $result.TableId

        $exists = Test-TableExists -Database $Database -SchemaName "SqlSizerHistory" -TableName "SubsetTableRow_$($table.PrimaryKeySize)" -ConnectionInfo $ConnectionInfo

        if ($exists -eq $false)
        {
            $keys = @()
            for ($i = 0; $i -lt $table.PrimaryKeySize; $i++)
            {
                $keys += "Key${i} varchar(max) not null"
            }

            $keysStr = [string]::Join(',', $keys)

            $sql = "CREATE TABLE SqlSizerHistory.SubsetTableRow_$($table.PrimaryKeySize) ([Id] int primary key identity(1,1), $keysStr, [Hash] varbinary(8000), [TableId] int NOT NULL)"
            $null = Invoke-SqlcmdEx -Sql $sql -Database $Database -ConnectionInfo $ConnectionInfo

            $sql = "ALTER TABLE SqlSizerHistory.SubsetTableRow_$($table.PrimaryKeySize) ADD CONSTRAINT SubsetTableRow_$($table.PrimaryKeySize)_TableId FOREIGN KEY (TableId) REFERENCES SqlSizerHistory.SubsetTable([Id]) ON DELETE CASCADE"
            $null = Invoke-SqlcmdEx -Sql $sql -Database $Database -ConnectionInfo $ConnectionInfo
        }

        $tableInfo = $DatabaseInfo.Tables | Where-Object { ($_.SchemaName -eq $table.SchemaName) -and ($_.TableName -eq $table.TableName) }
        $keys = @()
        $columns = @()
        $i = 0;
        for ($i = 0; $i -lt $tableInfo.PrimaryKey.Count; $i++)
        {
            $keys += "Key$i"
            $columns += $tableInfo.PrimaryKey[$i].Name
        }

        $sql = "INSERT INTO SqlSizerHistory.SubsetTableRow_$($table.PrimaryKeySize)($([string]::Join(',', $keys)), TableId, [Hash])
        SELECT $([string]::Join(',', $columns)), $tableId, row_sha2_512
        FROM [SqlSizer_$SessionId].Secure_$($tableInfo.SchemaName)_$($tableInfo.TableName)"

        $null = Invoke-SqlcmdEx -Sql $sql -Database $Database -ConnectionInfo $ConnectionInfo
    }

    return $guid
}

