function Install-SqlSizerCore
{
    [cmdletbinding()]
    param
    (
        [Parameter(Mandatory = $true)]
        [string]$Database,

        [Parameter(Mandatory = $true)]
        [DatabaseInfo]$DatabaseInfo,

        [Parameter(Mandatory = $true)]
        [SqlConnectionInfo]$ConnectionInfo
    )

    $schemaExists = Test-SchemaExists -SchemaName "SqlSizer" -Database $Database -ConnectionInfo $ConnectionInfo
    if ($schemaExists -eq $false)
    {
        $tmp = "CREATE SCHEMA SqlSizer"
        $null = Invoke-SqlcmdEx -Sql $tmp -Database $Database -ConnectionInfo $ConnectionInfo -Statistics $false
    }

    $tmp = "IF OBJECT_ID('SqlSizer.Operations') IS NOT NULL
        Drop Table SqlSizer.Operations"
    $null = Invoke-SqlcmdEx -Sql $tmp -Database $Database -ConnectionInfo $ConnectionInfo

    $tmp = "IF OBJECT_ID('SqlSizer.Tables') IS NOT NULL
        Drop Table SqlSizer.Tables"
    $null = Invoke-SqlcmdEx -Sql $tmp -Database $Database -ConnectionInfo $ConnectionInfo

    $tmp = "IF OBJECT_ID('SqlSizer.ForeignKeys') IS NOT NULL
        Drop Table SqlSizer.ForeignKeys"
    $null = Invoke-SqlcmdEx -Sql $tmp -Database $Database -ConnectionInfo $ConnectionInfo

    $pk = "PRIMARY KEY"
    $tmp = "IF OBJECT_ID('SqlSizer.Settings') IS NULL
            BEGIN
                CREATE TABLE SqlSizer.Settings(Id int identity(1,1) $pk, Name varchar(128), Value varchar(256))
                INSERT INTO SqlSizer.Settings(Name, Value) VALUES('Version', '$($currentSqlSizerVersion)')
            END
            ELSE
            BEGIN
                UPDATE SqlSizer.Settings SET Value = '$($currentSqlSizerVersion)' WHERE Name = 'Version'
            END"
    $null = Invoke-SqlcmdEx -Sql $tmp -Database $Database -ConnectionInfo $ConnectionInfo -Statistics $false

    $tmp = "CREATE TABLE SqlSizer.Files(Id int identity(1,1) $pk, FileId uniqueidentifier, [Index] int, [Content] nvarchar(max))"
    $null = Invoke-SqlcmdEx -Sql $tmp -Database $Database -ConnectionInfo $ConnectionInfo -Statistics $false

    $tmp = "CREATE TABLE SqlSizer.Tables(Id int identity(1,1) $pk, [Schema] varchar(128), [TableName] varchar(128))"
    $null = Invoke-SqlcmdEx -Sql $tmp -Database $Database -ConnectionInfo $ConnectionInfo -Statistics $false

    $tmp = "IF OBJECT_ID('SqlSizer.Sessions') IS NULL
                CREATE TABLE SqlSizer.Sessions(Id int identity(1,1) $pk, [SessionId] varchar(256))"
    $null = Invoke-SqlcmdEx -Sql $tmp -Database $Database -ConnectionInfo $ConnectionInfo -Statistics $false

    $sql = "CREATE NONCLUSTERED INDEX [Index] ON SqlSizer.Tables ([Schema] ASC, [TableName] ASC)"
    $null = Invoke-SqlcmdEx -Sql $sql -Database $Database -ConnectionInfo $ConnectionInfo -Statistics $false

    $tmp = "CREATE TABLE SqlSizer.ForeignKeys(Id int identity(1,1) $pk, [FkTableId] int, [TableId] int, [Name] varchar(256))"
    $null = Invoke-SqlcmdEx -Sql $tmp -Database $Database -ConnectionInfo $ConnectionInfo -Statistics $false

    foreach ($table in $DatabaseInfo.Tables)
    {
        $tmp = "INSERT INTO SqlSizer.Tables VALUES('$($table.SchemaName)', '$($table.TableName)')"
        $null = Invoke-SqlcmdEx -Sql $tmp -Database $Database -ConnectionInfo $ConnectionInfo
    }

    foreach ($table in $DatabaseInfo.Tables)
    {
        foreach ($fk in $table.ForeignKeys)
        {
            $tmp = "SELECT [Id] FROM SqlSizer.Tables WHERE [Schema] = '$($fk.FkSchema)' AND TableName = '$($fk.FkTable)'"
            $result = Invoke-SqlcmdEx -Sql $tmp -Database $Database -ConnectionInfo $ConnectionInfo

            $tmp = "SELECT [Id] FROM SqlSizer.Tables WHERE [Schema] = '$($fk.Schema)' AND TableName = '$($fk.Table)'"
            $result2 = Invoke-SqlcmdEx -Sql $tmp -Database $Database -ConnectionInfo $ConnectionInfo

            $tmp = "INSERT INTO SqlSizer.ForeignKeys VALUES($($result.Id), $($result2.Id), '$($fk.Name)')"
            $null = Invoke-SqlcmdEx -Sql $tmp -Database $Database -ConnectionInfo $ConnectionInfo
        }
    }

    $tmp = "CREATE TABLE SqlSizer.Operations(Id INT identity(1,1) $pk, [Table] SMALLINT, [State] INT, [ToProcess] INT NOT NULL, [Processed] INT NULL, [Status] INT NULL, [Source] INT, [Fk] INT, [Depth] INT, [Created] DATETIME NOT NULL, [ProcessedDate] DATETIME NULL, [SessionId] VARCHAR(256) NOT NULL, [FoundIteration] INT NOT NULL, [ProcessedIteration] INT NULL)"
    $null = Invoke-SqlcmdEx -Sql $tmp -Database $Database -ConnectionInfo $ConnectionInfo -Statistics $false

    $tmp = "CREATE NONCLUSTERED INDEX [Index] ON SqlSizer.Operations ([Table] ASC, [State] ASC, [Source] ASC, [Depth] ASC)"
    $null = Invoke-SqlcmdEx -Sql $tmp -Database $Database -ConnectionInfo $ConnectionInfo -Statistics $false

    $schemaExists = Test-SchemaExists -Database $Database -SchemaName "SqlSizerHistory" -ConnectionInfo $ConnectionInfo

    if ($schemaExists -eq $false)
    {
        $tmp = "CREATE SCHEMA SqlSizerHistory"
        $null = Invoke-SqlcmdEx -Sql $tmp -Database $Database -ConnectionInfo $ConnectionInfo -Statistics $false
    }

    if ((Test-TableExists -Database $Database -SchemaName "SqlSizerHistory" -TableName "Subset" -ConnectionInfo $ConnectionInfo) -eq $false)
    {
        $sql = "CREATE TABLE SqlSizerHistory.Subset ([Id] int identity(1,1) $pk, [Guid] [uniqueidentifier] NOT NULL, [Name] varchar(256), [Created] datetime default(GETDATE()))"
        $null = Invoke-SqlcmdEx -Sql $sql -Database $Database -ConnectionInfo $ConnectionInfo -Statistics $false
    }

    if ((Test-TableExists -Database $Database -SchemaName "SqlSizerHistory" -TableName "SubsetTable" -ConnectionInfo $ConnectionInfo) -eq $false)
    {
        $sql = "CREATE TABLE SqlSizerHistory.SubsetTable ([Id] int identity(1,1) $pk, [SchemaName] varchar(256), [TableName] varchar(256), [PrimaryKeySize] int NOT NULL, [RowCount] int NOT NULL,  [SubsetId] int NOT NULL)"
        $null = Invoke-SqlcmdEx -Sql $sql -Database $Database -ConnectionInfo $ConnectionInfo -Statistics $false

        $sql = "ALTER TABLE SqlSizerHistory.SubsetTable ADD CONSTRAINT SubsetTable_SubsetId FOREIGN KEY (SubsetId) REFERENCES SqlSizerHistory.Subset([Id]) ON DELETE CASCADE"
        $null = Invoke-SqlcmdEx -Sql $sql -Database $Database -ConnectionInfo $ConnectionInfo -Statistics $false
    }
}
