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

        [Parameter(Mandatory = $false)]
        [int]$BatchSize = 100000,

        [Parameter(Mandatory = $false)]
        [switch]$Resume,

        [Parameter(Mandatory = $false)]
        [bool]$DisableConstraintsForLoad = $true,

        [Parameter(Mandatory = $false)]
        [bool]$ReenableConstraints = $true,

        [Parameter(Mandatory = $false)]
        [bool]$RebuildDeferredIndexes = $true,

        [Parameter(Mandatory = $true)]
        [SqlConnectionInfo]$ConnectionInfo
    )

    if ($BatchSize -lt 1)
    {
        throw "BatchSize must be greater than or equal to 1."
    }

    $i = 0
    $structure = [Structure]::new($DatabaseInfo)
    $subsetTables = @(Get-SubsetTables -Database $Source -ConnectionInfo $ConnectionInfo -DatabaseInfo $DatabaseInfo -SessionId $SessionId)
    if ((-not $DisableConstraintsForLoad) -and ($subsetTables.Count -gt 1))
    {
        $subsetTables = @(Get-CopyDataFromSubsetForeignKeySafeOrder -SubsetTables $subsetTables -DatabaseInfo $DatabaseInfo)
    }

    Initialize-CopyDataFromSubsetProgressTable -Database $Destination -ConnectionInfo $ConnectionInfo

    if ($DisableConstraintsForLoad)
    {
        Disable-ForeignKeys -Database $Destination -ConnectionInfo $ConnectionInfo -DatabaseInfo $DatabaseInfo
        Disable-AllTablesTriggers -Database $Destination -ConnectionInfo $ConnectionInfo -DatabaseInfo $DatabaseInfo
    }

    foreach ($table in $subsetTables)
    {
        $i += 1

        $tableInfo = $DatabaseInfo.Tables | Where-Object { ($_.SchemaName -eq $table.SchemaName) -and ($_.TableName -eq $table.TableName) }
        Write-Progress -Activity "Copying data" -PercentComplete (100 * ($i / ($subsetTables.Count))) -CurrentOperation "Table $($table.SchemaName).$($table.TableName)"

        if ($tableInfo.IsHistoric -eq $true)
        {
            continue
        }

        $signature = $structure.Tables[$tableInfo]

        $sql = New-CopyDataFromSubsetQuery `
            -SessionId $SessionId `
            -Source $Source `
            -TableInfo $tableInfo `
            -ProcessingTableName $signature `
            -IgnoredTables $IgnoredTables `
            -BatchSize $BatchSize `
            -Resume ([bool]$Resume)

        $sql = Add-CopyDataFromSubsetIdentityInsert -Sql $sql -TableInfo $tableInfo
        $null = Invoke-SqlcmdEx -Sql $sql -Database $Destination -ConnectionInfo $ConnectionInfo
    }

    if ($RebuildDeferredIndexes)
    {
        Invoke-CopyDataFromSubsetDeferredIndexes -Database $Destination -ConnectionInfo $ConnectionInfo
    }

    if ($ReenableConstraints -and $DisableConstraintsForLoad)
    {
        Enable-ForeignKeys -Database $Destination -ConnectionInfo $ConnectionInfo -DatabaseInfo $DatabaseInfo
        Enable-AllTablesTriggers -Database $Destination -ConnectionInfo $ConnectionInfo -DatabaseInfo $DatabaseInfo
    }

    Write-Progress -Activity "Copying data" -Completed
}

function New-CopyDataFromSubsetQuery
{
    param
    (
        [Parameter(Mandatory = $true)]
        [string]$SessionId,

        [Parameter(Mandatory = $true)]
        [string]$Source,

        [Parameter(Mandatory = $true)]
        [TableInfo]$TableInfo,

        [Parameter(Mandatory = $true)]
        [string]$ProcessingTableName,

        [Parameter(Mandatory = $false)]
        [TableInfo2[]]$IgnoredTables,

        [Parameter(Mandatory = $false)]
        [int]$BatchSize = 100000,

        [Parameter(Mandatory = $false)]
        [bool]$Resume = $false
    )

    if (($null -eq $TableInfo.PrimaryKey) -or ($TableInfo.PrimaryKey.Count -eq 0))
    {
        throw "Cannot copy subset data for $($TableInfo.SchemaName).$($TableInfo.TableName) because it has no primary key."
    }

    if ([string]::IsNullOrWhiteSpace($ProcessingTableName))
    {
        throw "Cannot copy subset data for $($TableInfo.SchemaName).$($TableInfo.TableName) because no processing table was found."
    }

    $targetTableSql = Get-CopyDataFromSubsetTargetTableSql -TableInfo $TableInfo
    $sourceTableSql = Get-CopyDataFromSubsetSourceTableSql -Source $Source -TableInfo $TableInfo
    $processingTableSql = Get-CopyDataFromSubsetProcessingTableSql -Source $Source -SessionId $SessionId -ProcessingTableName $ProcessingTableName
    $insertColumns = Get-CopyDataFromSubsetInsertColumnList -TableInfo $TableInfo
    $sourceColumns = Get-CopyDataFromSubsetSourceColumnList -TableInfo $TableInfo -IgnoredTables $IgnoredTables
    $keyColumns = Get-CopyDataFromSubsetKeyColumnList -TableInfo $TableInfo
    $joinCondition = Get-CopyDataFromSubsetKeyJoinCondition -TableInfo $TableInfo
    $keyOrderBy = Get-CopyDataFromSubsetKeyOrderByList -TableInfo $TableInfo
    $targetExistsCondition = Get-CopyDataFromSubsetTargetExistsCondition -TableInfo $TableInfo
    $lastKeyJsonSelect = Get-CopyDataFromSubsetLastKeyJsonSelect -TableInfo $TableInfo
    $schemaLiteral = ConvertTo-SqlStringLiteral $TableInfo.SchemaName
    $tableLiteral = ConvertTo-SqlStringLiteral $TableInfo.TableName
    $sessionLiteral = ConvertTo-SqlStringLiteral $SessionId
    $includedStates = Get-IncludedTraversalStateSqlList
    $resumeBit = if ($Resume) { 1 } else { 0 }

    return @"
DECLARE @BatchSize bigint = $BatchSize;
DECLARE @Resume bit = $resumeBit;
DECLARE @CopiedRows bigint = 0;
DECLARE @TotalRows bigint = 0;
DECLARE @RowsThisBatch bigint = 0;
DECLARE @BatchStart bigint = 0;
DECLARE @BatchEnd bigint = 0;
DECLARE @LastKeyJson nvarchar(max) = NULL;

IF OBJECT_ID('tempdb..#SqlSizerSubsetKeys') IS NOT NULL
    DROP TABLE #SqlSizerSubsetKeys;

;WITH DistinctSubsetKeys AS (
    SELECT DISTINCT $keyColumns
    FROM $processingTableSql
    WHERE [State] IN ($includedStates)
)
SELECT
    ROW_NUMBER() OVER (ORDER BY $keyOrderBy) AS SqlSizer_CopyRowNumber,
    $keyColumns
INTO #SqlSizerSubsetKeys
FROM DistinctSubsetKeys;

CREATE UNIQUE CLUSTERED INDEX IX_SqlSizerSubsetKeys_RowNumber
ON #SqlSizerSubsetKeys (SqlSizer_CopyRowNumber);

SELECT @TotalRows = COUNT_BIG(*) FROM #SqlSizerSubsetKeys;

IF @Resume = 1
BEGIN
    SELECT @CopiedRows = ISNULL(CopiedRows, 0)
    FROM SqlSizer.CopyProgress
    WHERE SessionId = $sessionLiteral
        AND SchemaName = $schemaLiteral
        AND TableName = $tableLiteral;
END

IF @Resume = 0 OR @CopiedRows IS NULL
BEGIN
    SET @CopiedRows = 0;
END

MERGE SqlSizer.CopyProgress AS target
USING (
    SELECT $sessionLiteral AS SessionId,
           $schemaLiteral AS SchemaName,
           $tableLiteral AS TableName
) AS source
ON target.SessionId = source.SessionId
    AND target.SchemaName = source.SchemaName
    AND target.TableName = source.TableName
WHEN MATCHED THEN
    UPDATE SET TotalRows = @TotalRows,
               CopiedRows = @CopiedRows,
               Status = CASE WHEN @CopiedRows >= @TotalRows THEN 'Completed' ELSE 'InProgress' END,
               UpdatedAt = SYSUTCDATETIME(),
               CompletedAt = CASE WHEN @CopiedRows >= @TotalRows THEN SYSUTCDATETIME() ELSE NULL END
WHEN NOT MATCHED THEN
    INSERT (SessionId, SchemaName, TableName, TotalRows, CopiedRows, Status, StartedAt, UpdatedAt, CompletedAt)
    VALUES (source.SessionId, source.SchemaName, source.TableName, @TotalRows, @CopiedRows,
            CASE WHEN @CopiedRows >= @TotalRows THEN 'Completed' ELSE 'InProgress' END,
            SYSUTCDATETIME(), SYSUTCDATETIME(),
            CASE WHEN @CopiedRows >= @TotalRows THEN SYSUTCDATETIME() ELSE NULL END);

WHILE @CopiedRows < @TotalRows
BEGIN
    SET @BatchStart = @CopiedRows + 1;
    SET @BatchEnd = CASE WHEN @CopiedRows + @BatchSize > @TotalRows THEN @TotalRows ELSE @CopiedRows + @BatchSize END;
    SELECT @LastKeyJson = (
        SELECT $lastKeyJsonSelect
        FROM #SqlSizerSubsetKeys
        WHERE SqlSizer_CopyRowNumber = @BatchEnd
        FOR JSON PATH, WITHOUT_ARRAY_WRAPPER
    );

    ;WITH BatchKeys AS (
        SELECT $keyColumns
        FROM #SqlSizerSubsetKeys
        WHERE SqlSizer_CopyRowNumber BETWEEN @BatchStart AND @BatchEnd
    )
    INSERT INTO $targetTableSql ($insertColumns)
    SELECT $sourceColumns
    FROM $sourceTableSql src
    INNER JOIN BatchKeys subsetKeys ON $joinCondition
    WHERE @Resume = 0
        OR NOT EXISTS (
            SELECT 1
            FROM $targetTableSql existing
            WHERE $targetExistsCondition
        );

    SET @RowsThisBatch = @@ROWCOUNT;
    SET @CopiedRows = @BatchEnd;

    UPDATE SqlSizer.CopyProgress
    SET CopiedRows = @CopiedRows,
        LastBatchStart = @BatchStart,
        LastBatchEnd = @BatchEnd,
        LastKeyJson = @LastKeyJson,
        Status = CASE WHEN @CopiedRows >= @TotalRows THEN 'Completed' ELSE 'InProgress' END,
        UpdatedAt = SYSUTCDATETIME(),
        CompletedAt = CASE WHEN @CopiedRows >= @TotalRows THEN SYSUTCDATETIME() ELSE NULL END
    WHERE SessionId = $sessionLiteral
        AND SchemaName = $schemaLiteral
        AND TableName = $tableLiteral;
END

SELECT @TotalRows AS TotalRows, @CopiedRows AS CopiedRows;
"@
}

function Add-CopyDataFromSubsetIdentityInsert
{
    param
    (
        [Parameter(Mandatory = $true)]
        [string]$Sql,

        [Parameter(Mandatory = $true)]
        [TableInfo]$TableInfo
    )

    if ($TableInfo.IsIdentity -eq $false)
    {
        return $Sql
    }

    $targetTableSql = Get-CopyDataFromSubsetTargetTableSql -TableInfo $TableInfo
    return "SET IDENTITY_INSERT $targetTableSql ON; $Sql; SET IDENTITY_INSERT $targetTableSql OFF"
}

function Get-CopyDataFromSubsetTargetTableSql
{
    param
    (
        [Parameter(Mandatory = $true)]
        [TableInfo]$TableInfo
    )

    return "$(ConvertTo-SqlIdentifier $TableInfo.SchemaName).$(ConvertTo-SqlIdentifier $TableInfo.TableName)"
}

function Get-CopyDataFromSubsetSourceTableSql
{
    param
    (
        [Parameter(Mandatory = $true)]
        [string]$Source,

        [Parameter(Mandatory = $true)]
        [TableInfo]$TableInfo
    )

    return "$(ConvertTo-SqlIdentifier $Source).$(ConvertTo-SqlIdentifier $TableInfo.SchemaName).$(ConvertTo-SqlIdentifier $TableInfo.TableName)"
}

function Get-CopyDataFromSubsetProcessingTableSql
{
    param
    (
        [Parameter(Mandatory = $true)]
        [string]$Source,

        [Parameter(Mandatory = $true)]
        [string]$SessionId,

        [Parameter(Mandatory = $true)]
        [string]$ProcessingTableName
    )

    return "$(ConvertTo-SqlIdentifier $Source).$(ConvertTo-SqlIdentifier "SqlSizer_$SessionId").$(ConvertTo-SqlIdentifier $ProcessingTableName)"
}

function Get-CopyDataFromSubsetInsertColumnList
{
    param
    (
        [Parameter(Mandatory = $true)]
        [TableInfo]$TableInfo
    )

    $columns = foreach ($column in $TableInfo.Columns)
    {
        if (Test-CopyDataFromSubsetColumnSkipped -Column $column)
        {
            continue
        }

        ConvertTo-SqlIdentifier $column.Name
    }

    return [string]::Join(', ', $columns)
}

function Get-CopyDataFromSubsetSourceColumnList
{
    param
    (
        [Parameter(Mandatory = $true)]
        [TableInfo]$TableInfo,

        [Parameter(Mandatory = $false)]
        [TableInfo2[]]$IgnoredTables
    )

    $columns = foreach ($column in $TableInfo.Columns)
    {
        if (Test-CopyDataFromSubsetColumnSkipped -Column $column)
        {
            continue
        }

        if (Test-CopyDataFromSubsetIgnoredForeignKeyColumn -TableInfo $TableInfo -ColumnName $column.Name -IgnoredTables $IgnoredTables)
        {
            'NULL'
        }
        else
        {
            "src.$(ConvertTo-SqlIdentifier $column.Name)"
        }
    }

    return [string]::Join(', ', $columns)
}

function Get-CopyDataFromSubsetKeyColumnList
{
    param
    (
        [Parameter(Mandatory = $true)]
        [TableInfo]$TableInfo
    )

    $columns = for ($i = 0; $i -lt $TableInfo.PrimaryKey.Count; $i++)
    {
        ConvertTo-SqlIdentifier "Key$i"
    }

    return [string]::Join(', ', $columns)
}

function Get-CopyDataFromSubsetKeyOrderByList
{
    param
    (
        [Parameter(Mandatory = $true)]
        [TableInfo]$TableInfo
    )

    $columns = for ($i = 0; $i -lt $TableInfo.PrimaryKey.Count; $i++)
    {
        "$(ConvertTo-SqlIdentifier "Key$i") ASC"
    }

    return [string]::Join(', ', $columns)
}

function Get-CopyDataFromSubsetKeyJoinCondition
{
    param
    (
        [Parameter(Mandatory = $true)]
        [TableInfo]$TableInfo
    )

    $conditions = for ($i = 0; $i -lt $TableInfo.PrimaryKey.Count; $i++)
    {
        "src.$(ConvertTo-SqlIdentifier $TableInfo.PrimaryKey[$i].Name) = subsetKeys.$(ConvertTo-SqlIdentifier "Key$i")"
    }

    return [string]::Join(' AND ', $conditions)
}

function Get-CopyDataFromSubsetTargetExistsCondition
{
    param
    (
        [Parameter(Mandatory = $true)]
        [TableInfo]$TableInfo
    )

    $conditions = foreach ($column in $TableInfo.PrimaryKey)
    {
        "existing.$(ConvertTo-SqlIdentifier $column.Name) = src.$(ConvertTo-SqlIdentifier $column.Name)"
    }

    return [string]::Join(' AND ', $conditions)
}

function Get-CopyDataFromSubsetLastKeyJsonSelect
{
    param
    (
        [Parameter(Mandatory = $true)]
        [TableInfo]$TableInfo
    )

    $columns = for ($i = 0; $i -lt $TableInfo.PrimaryKey.Count; $i++)
    {
        "$(ConvertTo-SqlIdentifier "Key$i") AS $(ConvertTo-SqlIdentifier $TableInfo.PrimaryKey[$i].Name)"
    }

    return [string]::Join(', ', $columns)
}

function Test-CopyDataFromSubsetColumnSkipped
{
    param
    (
        [Parameter(Mandatory = $true)]
        [ColumnInfo]$Column
    )

    return ($Column.IsComputed -eq $true) -or ($Column.IsGenerated -eq $true) -or ($Column.DataType -eq "timestamp")
}

function Test-CopyDataFromSubsetIgnoredForeignKeyColumn
{
    param
    (
        [Parameter(Mandatory = $true)]
        [TableInfo]$TableInfo,

        [Parameter(Mandatory = $true)]
        [string]$ColumnName,

        [Parameter(Mandatory = $false)]
        [TableInfo2[]]$IgnoredTables
    )

    foreach ($fk in $TableInfo.ForeignKeys)
    {
        if ([TableInfo2]::IsIgnored($fk.Schema, $fk.Table, $IgnoredTables) -eq $false)
        {
            continue
        }

        foreach ($fkColumn in $fk.FkColumns)
        {
            if ($fkColumn.Name -eq $ColumnName)
            {
                return $true
            }
        }
    }

    return $false
}

function Initialize-CopyDataFromSubsetProgressTable
{
    param
    (
        [Parameter(Mandatory = $true)]
        [string]$Database,

        [Parameter(Mandatory = $true)]
        [SqlConnectionInfo]$ConnectionInfo
    )

    $sql = @"
IF SCHEMA_ID(N'SqlSizer') IS NULL
    EXEC(N'CREATE SCHEMA [SqlSizer]');

IF OBJECT_ID(N'SqlSizer.CopyProgress', N'U') IS NULL
BEGIN
    CREATE TABLE SqlSizer.CopyProgress
    (
        SessionId varchar(256) NOT NULL,
        SchemaName sysname NOT NULL,
        TableName sysname NOT NULL,
        TotalRows bigint NOT NULL CONSTRAINT DF_SqlSizer_CopyProgress_TotalRows DEFAULT (0),
        CopiedRows bigint NOT NULL CONSTRAINT DF_SqlSizer_CopyProgress_CopiedRows DEFAULT (0),
        LastBatchStart bigint NULL,
        LastBatchEnd bigint NULL,
        LastKeyJson nvarchar(max) NULL,
        Status varchar(32) NOT NULL CONSTRAINT DF_SqlSizer_CopyProgress_Status DEFAULT ('Pending'),
        StartedAt datetime2(7) NOT NULL CONSTRAINT DF_SqlSizer_CopyProgress_StartedAt DEFAULT (SYSUTCDATETIME()),
        UpdatedAt datetime2(7) NOT NULL CONSTRAINT DF_SqlSizer_CopyProgress_UpdatedAt DEFAULT (SYSUTCDATETIME()),
        CompletedAt datetime2(7) NULL,
        CONSTRAINT PK_SqlSizer_CopyProgress PRIMARY KEY CLUSTERED (SessionId, SchemaName, TableName)
    );
END;

IF COL_LENGTH(N'SqlSizer.CopyProgress', N'LastKeyJson') IS NULL
BEGIN
    ALTER TABLE SqlSizer.CopyProgress ADD LastKeyJson nvarchar(max) NULL;
END;
"@

    $null = Invoke-SqlcmdEx -Sql $sql -Database $Database -ConnectionInfo $ConnectionInfo -Statistics $false
}

function Get-CopyDataFromSubsetForeignKeySafeOrder
{
    param
    (
        [Parameter(Mandatory = $true)]
        [object[]]$SubsetTables,

        [Parameter(Mandatory = $true)]
        [DatabaseInfo]$DatabaseInfo
    )

    if ($SubsetTables.Count -le 1)
    {
        return $SubsetTables
    }

    $tablesByKey = @{}
    foreach ($table in $DatabaseInfo.Tables)
    {
        $tablesByKey[(Get-CopyDataFromSubsetTableKey -SchemaName $table.SchemaName -TableName $table.TableName)] = $table
    }

    $pendingRows = [ordered]@{}
    foreach ($table in $SubsetTables)
    {
        $key = Get-CopyDataFromSubsetTableKey -SchemaName $table.SchemaName -TableName $table.TableName
        $pendingRows[$key] = $table
    }

    $dependencies = @{}
    foreach ($key in $pendingRows.Keys)
    {
        $dependencySet = [System.Collections.Generic.HashSet[string]]::new()
        $tableInfo = $tablesByKey[$key]
        if ($null -ne $tableInfo)
        {
            foreach ($fk in $tableInfo.ForeignKeys)
            {
                $referencedKey = Get-CopyDataFromSubsetTableKey -SchemaName $fk.Schema -TableName $fk.Table
                if (($referencedKey -ne $key) -and $pendingRows.Contains($referencedKey))
                {
                    [void]$dependencySet.Add($referencedKey)
                }
            }
        }

        $dependencies[$key] = $dependencySet
    }

    $result = [System.Collections.Generic.List[object]]::new()
    while ($pendingRows.Count -gt 0)
    {
        $readyKeys = @($pendingRows.Keys | Where-Object { $dependencies[$_].Count -eq 0 } | Sort-Object)
        if ($readyKeys.Count -eq 0)
        {
            $readyKeys = @($pendingRows.Keys | Sort-Object)
        }

        foreach ($key in $readyKeys)
        {
            $result.Add($pendingRows[$key])
        }

        foreach ($key in $readyKeys)
        {
            $pendingRows.Remove($key)
        }

        foreach ($dependencySet in $dependencies.Values)
        {
            foreach ($key in $readyKeys)
            {
                [void]$dependencySet.Remove($key)
            }
        }
    }

    return @($result)
}

function Get-CopyDataFromSubsetTableKey
{
    param
    (
        [Parameter(Mandatory = $true)]
        [string]$SchemaName,

        [Parameter(Mandatory = $true)]
        [string]$TableName
    )

    return "$SchemaName, $TableName"
}

function Invoke-CopyDataFromSubsetDeferredIndexes
{
    param
    (
        [Parameter(Mandatory = $true)]
        [string]$Database,

        [Parameter(Mandatory = $true)]
        [SqlConnectionInfo]$ConnectionInfo
    )

    $sql = @"
IF OBJECT_ID(N'SqlSizer.DeferredIndexes', N'U') IS NOT NULL
    SELECT Id, CreateSql
    FROM SqlSizer.DeferredIndexes
    WHERE Created = 0
    ORDER BY Id;
"@

    $rows = @(Invoke-SqlcmdEx -Sql $sql -Database $Database -ConnectionInfo $ConnectionInfo -Statistics $false)
    foreach ($row in $rows)
    {
        if ($null -eq $row -or [string]::IsNullOrWhiteSpace($row.CreateSql))
        {
            continue
        }

        $null = Invoke-SqlcmdEx -Sql $row.CreateSql -Database $Database -ConnectionInfo $ConnectionInfo -Statistics $false
        $markSql = "UPDATE SqlSizer.DeferredIndexes SET Created = 1, CreatedAt = SYSUTCDATETIME() WHERE Id = $($row.Id)"
        $null = Invoke-SqlcmdEx -Sql $markSql -Database $Database -ConnectionInfo $ConnectionInfo -Statistics $false
    }
}
