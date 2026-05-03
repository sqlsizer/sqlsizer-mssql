function Copy-FileToDatabase
{
    [cmdletbinding()]
    [outputtype([System.Boolean])]
    param
    (
        [Parameter(Mandatory = $true)]
        [string]$Database,

        [Parameter(Mandatory = $true)]
        [string]$FilePath,

        [Parameter(Mandatory = $true)]
        [SqlConnectionInfo]$ConnectionInfo
    )

    $schemaExists = Test-SchemaExists -SchemaName "SqlSizer" -Database $Database -ConnectionInfo $ConnectionInfo
    if ($schemaExists -eq $false)
    {
        $tmp = "CREATE SCHEMA SqlSizer"
        Invoke-SqlcmdEx -Sql $tmp -Database $Database -ConnectionInfo $ConnectionInfo -Statistics $false
    }

    $tableExists = Test-TableExists -SchemaName "SqlSizer" -TableName "Files" -Database $Database -ConnectionInfo $ConnectionInfo
    if ($tableExists -eq $false)
    {
        $tmp = "CREATE TABLE SqlSizer.Files(Id bigint primary key identity(1,1), FileId uniqueidentifier, [Index] int, [Content] nvarchar(max))"
        Invoke-SqlcmdEx -Sql $tmp -Database $Database -ConnectionInfo $ConnectionInfo
    }

    $indexSql = "IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_SqlSizer_Files_FileId_Index' AND object_id = OBJECT_ID('SqlSizer.Files')) CREATE INDEX IX_SqlSizer_Files_FileId_Index ON SqlSizer.Files(FileId, [Index])"
    $null = Invoke-SqlcmdEx -Sql $indexSql -Database $Database -ConnectionInfo $ConnectionInfo -Statistics $false

    $id = New-Guid
    $fileContent = [System.IO.File]::ReadAllText($FilePath)

    $chunkSize = 3000
    $chunks = [Math]::Floor($fileContent.Length / $chunkSize)

    for ($i = 0; $i -lt $chunks; $i = $i + 1)
    {
        Write-Progress -Activity "Copying file $FilePath to database" -PercentComplete (100 * ($i / ($chunks)))

        $chunk = $fileContent.Substring($i * $chunkSize, $chunkSize)
        $chunk = $chunk.Replace("'", "''") # improve it

        $sql = "INSERT INTO SqlSizer.Files([FileId], [Index], [Content]) VALUES('$id', $i, N'$chunk')"
        $null = Invoke-SqlcmdEx -Sql $sql -Database $Database -ConnectionInfo $ConnectionInfo
    }

    if ($chunks * $chunkSize -ne $fileContent.Length)
    {
        $chunk = $fileContent.Substring($chunks * $chunkSize)
        $chunk = $chunk.Replace("'", "''") # improve it

        $sql = "INSERT INTO SqlSizer.Files([FileId], [Index], [Content]) VALUES('$id', $i, N'$chunk')"
        $null = Invoke-SqlcmdEx -Sql $sql -Database $Database -ConnectionInfo $ConnectionInfo
    }

    Write-Progress -Activity "Copying file $FilePath to database" -Completed

    return $id
}
