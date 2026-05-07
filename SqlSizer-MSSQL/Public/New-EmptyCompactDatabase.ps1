function New-EmptyCompactDatabase
{
    [outputtype([System.Boolean])]
    [cmdletbinding()]
    param
    (
        [Parameter(Mandatory = $true)]
        [string]$Database,

        [Parameter(Mandatory = $true)]
        [string]$NewDatabase,

        [Parameter(Mandatory = $true)]
        [DatabaseInfo]$DatabaseInfo,

        [Parameter(Mandatory = $false)]
        [bool]$DeferNonClusteredIndexes = $true,

        [Parameter(Mandatory = $false)]
        [bool]$IncludeTriggers = $false,

        [Parameter(Mandatory = $false)]
        [bool]$ValidateSchema = $true,

        [Parameter(Mandatory = $false)]
        [bool]$CompressAfterLoad = $false,

        [Parameter(Mandatory = $true)]
        [SqlConnectionInfo]$ConnectionInfo
    )

    if ((Test-DatabaseOnline -Database $NewDatabase -ConnectionInfo $ConnectionInfo))
    {
        return $false
    }

    $newDatabaseSql = ConvertTo-SqlIdentifier $NewDatabase
    $sql = "CREATE DATABASE $newDatabaseSql"
    Invoke-SqlcmdEx -Sql $sql -Database $Database -ConnectionInfo $ConnectionInfo -Silent $false -Statistics $false

    Copy-UserTypes -SourceDatabase $Database -TargetDatabase $NewDatabase -ConnectionInfo $ConnectionInfo
    Copy-XmlSchemaCollections -SourceDatabase $Database -TargetDatabase $NewDatabase -ConnectionInfo $ConnectionInfo
    Copy-Sequences -SourceDatabase $Database -TargetDatabase $NewDatabase -ConnectionInfo $ConnectionInfo
    Copy-Functions -SourceDatabase $Database -TargetDatabase $NewDatabase -ConnectionInfo $ConnectionInfo

    New-CompactDatabaseTables -SourceDatabase $Database -TargetDatabase $NewDatabase -DatabaseInfo $DatabaseInfo -ConnectionInfo $ConnectionInfo
    New-CompactDatabaseKeyConstraints -SourceDatabase $Database -TargetDatabase $NewDatabase -DatabaseInfo $DatabaseInfo -ConnectionInfo $ConnectionInfo
    New-CompactDatabaseCheckConstraints -SourceDatabase $Database -TargetDatabase $NewDatabase -DatabaseInfo $DatabaseInfo -ConnectionInfo $ConnectionInfo
    New-CompactDatabaseForeignKeys -TargetDatabase $NewDatabase -DatabaseInfo $DatabaseInfo -ConnectionInfo $ConnectionInfo
    New-CompactDatabaseIndexes -SourceDatabase $Database -TargetDatabase $NewDatabase -DatabaseInfo $DatabaseInfo -ConnectionInfo $ConnectionInfo -DeferNonClusteredIndexes $DeferNonClusteredIndexes

    Copy-StoredProcedures -SourceDatabase $Database -TargetDatabase $NewDatabase -ConnectionInfo $ConnectionInfo

    if ($IncludeTriggers)
    {
        Copy-CompactDatabaseTriggers -SourceDatabase $Database -TargetDatabase $NewDatabase -DatabaseInfo $DatabaseInfo -ConnectionInfo $ConnectionInfo
    }

    if ($ValidateSchema)
    {
        Test-CompactDatabaseSchema -Database $NewDatabase -DatabaseInfo $DatabaseInfo -ConnectionInfo $ConnectionInfo
    }

    if ($CompressAfterLoad)
    {
        Compress-Database -Database $NewDatabase -ConnectionInfo $ConnectionInfo
    }

    return $true
}

function Copy-XmlSchemaCollections
{
    [cmdletbinding()]
    param
    (
        [Parameter(Mandatory = $true)]
        [string]$SourceDatabase,

        [Parameter(Mandatory = $true)]
        [string]$TargetDatabase,

        [Parameter(Mandatory = $true)]
        [SqlConnectionInfo]$ConnectionInfo
    )

    $sql = @"
SELECT
    s.name AS SchemaName,
    xsc.name AS CollectionName,
    CONVERT(nvarchar(max), XML_SCHEMA_NAMESPACE(s.name, xsc.name)) AS Definition
FROM sys.xml_schema_collections xsc
INNER JOIN sys.schemas s ON xsc.schema_id = s.schema_id
WHERE xsc.name <> N'sys'
ORDER BY s.name, xsc.name;
"@

    $rows = @(Invoke-SqlcmdEx -Sql $sql -Database $SourceDatabase -ConnectionInfo $ConnectionInfo -Statistics $false)
    foreach ($row in $rows)
    {
        if ([string]::IsNullOrWhiteSpace($row.Definition))
        {
            continue
        }

        $schemaSql = ConvertTo-SqlIdentifier $row.SchemaName
        $collectionSql = "$(ConvertTo-SqlIdentifier $row.SchemaName).$(ConvertTo-SqlIdentifier $row.CollectionName)"
        $schemaLiteral = ConvertTo-SqlStringLiteral $row.SchemaName
        $collectionLiteral = ConvertTo-SqlStringLiteral $row.CollectionName
        $definitionLiteral = ConvertTo-SqlStringLiteral $row.Definition

        $createSql = @"
IF SCHEMA_ID($schemaLiteral) IS NULL
    EXEC(N'CREATE SCHEMA $schemaSql');

IF NOT EXISTS (
    SELECT 1
    FROM sys.xml_schema_collections xsc
    INNER JOIN sys.schemas s ON xsc.schema_id = s.schema_id
    WHERE s.name = $schemaLiteral
        AND xsc.name = $collectionLiteral
)
BEGIN
    CREATE XML SCHEMA COLLECTION $collectionSql AS N$definitionLiteral;
END;
"@
        $result = Invoke-SqlcmdEx -Sql $createSql -Database $TargetDatabase -ConnectionInfo $ConnectionInfo -Statistics $false -Silent $true
        if ($result -eq $false)
        {
            Write-Warning "Skipped XML schema collection [$($row.SchemaName)].[$($row.CollectionName)] in [$TargetDatabase]: it may reference an unavailable schema or collation."
        }
    }
}

function New-CompactDatabaseTables
{
    [cmdletbinding()]
    param
    (
        [Parameter(Mandatory = $true)]
        [string]$SourceDatabase,

        [Parameter(Mandatory = $true)]
        [string]$TargetDatabase,

        [Parameter(Mandatory = $true)]
        [DatabaseInfo]$DatabaseInfo,

        [Parameter(Mandatory = $true)]
        [SqlConnectionInfo]$ConnectionInfo
    )

    $columnRows = @(Get-CompactDatabaseColumnRows -Database $SourceDatabase -ConnectionInfo $ConnectionInfo)
    $columnsByTable = @{}
    foreach ($row in $columnRows)
    {
        $key = Get-CompactDatabaseTableKey -SchemaName $row.SchemaName -TableName $row.TableName
        if (-not $columnsByTable.ContainsKey($key))
        {
            $columnsByTable[$key] = [System.Collections.Generic.List[object]]::new()
        }

        $columnsByTable[$key].Add($row)
    }

    $i = 0
    foreach ($table in $DatabaseInfo.Tables)
    {
        $i += 1
        Write-Progress -Activity "Creating compact schema" -PercentComplete (100 * ($i / $DatabaseInfo.Tables.Count)) -CurrentOperation "Table $($table.SchemaName).$($table.TableName)"

        $key = Get-CompactDatabaseTableKey -SchemaName $table.SchemaName -TableName $table.TableName
        if (-not $columnsByTable.ContainsKey($key))
        {
            continue
        }

        $schemaSql = ConvertTo-SqlIdentifier $table.SchemaName
        $schemaLiteral = ConvertTo-SqlStringLiteral $table.SchemaName
        $createSchemaSql = "IF SCHEMA_ID($schemaLiteral) IS NULL EXEC(N'CREATE SCHEMA $schemaSql')"
        $null = Invoke-SqlcmdEx -Sql $createSchemaSql -Database $TargetDatabase -ConnectionInfo $ConnectionInfo -Statistics $false

        $columnDefinitions = [System.Collections.Generic.List[string]]::new()
        foreach ($column in ($columnsByTable[$key] | Sort-Object ColumnId))
        {
            $columnDefinitions.Add((Get-CompactDatabaseColumnDefinition -ColumnRow $column))
        }

        $tableSql = "$(ConvertTo-SqlIdentifier $table.SchemaName).$(ConvertTo-SqlIdentifier $table.TableName)"
        $sql = "CREATE TABLE $tableSql (`n    $([string]::Join(",`n    ", $columnDefinitions))`n)"
        $null = Invoke-SqlcmdEx -Sql $sql -Database $TargetDatabase -ConnectionInfo $ConnectionInfo -Statistics $false
    }

    Write-Progress -Activity "Creating compact schema" -Completed
}

function Get-CompactDatabaseColumnRows
{
    [cmdletbinding()]
    param
    (
        [Parameter(Mandatory = $true)]
        [string]$Database,

        [Parameter(Mandatory = $true)]
        [SqlConnectionInfo]$ConnectionInfo
    )

    $sql = @"
SELECT
    s.name AS SchemaName,
    t.name AS TableName,
    c.column_id AS ColumnId,
    c.name AS ColumnName,
    ty.name AS TypeName,
    SCHEMA_NAME(ty.schema_id) AS TypeSchemaName,
    ty.is_user_defined AS IsUserDefined,
    c.max_length AS MaxLength,
    c.[precision] AS [Precision],
    c.scale AS Scale,
    c.is_nullable AS IsNullable,
    c.is_identity AS IsIdentity,
    c.is_computed AS IsComputed,
    c.collation_name AS CollationName,
    c.is_rowguidcol AS IsRowGuidColumn,
    c.is_sparse AS IsSparse,
    c.xml_collection_id AS XmlCollectionId,
    c.is_xml_document AS IsXmlDocument,
    xsc.name AS XmlCollectionName,
    SCHEMA_NAME(xsc.schema_id) AS XmlCollectionSchemaName,
    ic.seed_value AS IdentitySeed,
    ic.increment_value AS IdentityIncrement,
    cc.definition AS ComputedDefinition,
    cc.is_persisted AS IsPersisted,
    dc.name AS DefaultName,
    dc.definition AS DefaultDefinition
FROM sys.tables t
INNER JOIN sys.schemas s ON t.schema_id = s.schema_id
INNER JOIN sys.columns c ON t.object_id = c.object_id
INNER JOIN sys.types ty ON c.user_type_id = ty.user_type_id
LEFT JOIN sys.identity_columns ic ON c.object_id = ic.object_id AND c.column_id = ic.column_id
LEFT JOIN sys.computed_columns cc ON c.object_id = cc.object_id AND c.column_id = cc.column_id
LEFT JOIN sys.default_constraints dc ON c.default_object_id = dc.object_id
LEFT JOIN sys.xml_schema_collections xsc ON c.xml_collection_id = xsc.xml_collection_id
WHERE t.is_ms_shipped = 0
ORDER BY s.name, t.name, c.column_id;
"@

    return Invoke-SqlcmdEx -Sql $sql -Database $Database -ConnectionInfo $ConnectionInfo -Statistics $false
}

function Get-CompactDatabaseColumnDefinition
{
    [cmdletbinding()]
    param
    (
        [Parameter(Mandatory = $true)]
        [object]$ColumnRow
    )

    $columnNameSql = ConvertTo-SqlIdentifier $ColumnRow.ColumnName
    if ([bool]$ColumnRow.IsComputed)
    {
        $persisted = if ([bool]$ColumnRow.IsPersisted) { " PERSISTED" } else { "" }
        return "$columnNameSql AS $($ColumnRow.ComputedDefinition)$persisted"
    }

    $typeSql = Get-CompactDatabaseColumnTypeSql -ColumnRow $ColumnRow
    $parts = [System.Collections.Generic.List[string]]::new()
    $parts.Add($columnNameSql)
    $parts.Add($typeSql)

    if ((-not [bool]$ColumnRow.IsUserDefined) -and (-not [string]::IsNullOrWhiteSpace($ColumnRow.CollationName)))
    {
        $parts.Add("COLLATE $($ColumnRow.CollationName)")
    }

    if ([bool]$ColumnRow.IsSparse)
    {
        $parts.Add("SPARSE")
    }

    if ([bool]$ColumnRow.IsIdentity)
    {
        $seed = if ($null -eq $ColumnRow.IdentitySeed) { 1 } else { $ColumnRow.IdentitySeed }
        $increment = if ($null -eq $ColumnRow.IdentityIncrement) { 1 } else { $ColumnRow.IdentityIncrement }
        $parts.Add("IDENTITY($seed,$increment)")
    }

    if ([bool]$ColumnRow.IsRowGuidColumn)
    {
        $parts.Add("ROWGUIDCOL")
    }

    $parts.Add($(if ([bool]$ColumnRow.IsNullable) { "NULL" } else { "NOT NULL" }))

    if (-not [string]::IsNullOrWhiteSpace($ColumnRow.DefaultDefinition))
    {
        if (-not [string]::IsNullOrWhiteSpace($ColumnRow.DefaultName))
        {
            $parts.Add("CONSTRAINT $(ConvertTo-SqlIdentifier $ColumnRow.DefaultName)")
        }
        $parts.Add("DEFAULT $($ColumnRow.DefaultDefinition)")
    }

    return [string]::Join(' ', $parts)
}

function Get-CompactDatabaseColumnTypeSql
{
    [cmdletbinding()]
    param
    (
        [Parameter(Mandatory = $true)]
        [object]$ColumnRow
    )

    $typeName = [string]$ColumnRow.TypeName
    if ($typeName -eq 'xml')
    {
        if (($null -ne $ColumnRow.XmlCollectionId) -and ([int]$ColumnRow.XmlCollectionId -ne 0))
        {
            $xmlKind = if ([bool]$ColumnRow.IsXmlDocument) { 'DOCUMENT' } else { 'CONTENT' }
            return "xml($xmlKind $(ConvertTo-SqlIdentifier $ColumnRow.XmlCollectionSchemaName).$(ConvertTo-SqlIdentifier $ColumnRow.XmlCollectionName))"
        }

        return 'xml'
    }

    if ([bool]$ColumnRow.IsUserDefined -and $ColumnRow.TypeSchemaName -ne 'sys')
    {
        return "$(ConvertTo-SqlIdentifier $ColumnRow.TypeSchemaName).$(ConvertTo-SqlIdentifier $typeName)"
    }

    if ($typeName -in @('varchar', 'char', 'varbinary', 'binary'))
    {
        $length = if ([int]$ColumnRow.MaxLength -eq -1) { 'max' } else { [string]([int]$ColumnRow.MaxLength) }
        return "$typeName($length)"
    }

    if ($typeName -in @('nvarchar', 'nchar'))
    {
        $length = if ([int]$ColumnRow.MaxLength -eq -1) { 'max' } else { [string]([int]$ColumnRow.MaxLength / 2) }
        return "$typeName($length)"
    }

    if ($typeName -in @('decimal', 'numeric'))
    {
        return "$typeName($($ColumnRow.Precision),$($ColumnRow.Scale))"
    }

    if ($typeName -in @('datetime2', 'datetimeoffset', 'time'))
    {
        return "$typeName($($ColumnRow.Scale))"
    }

    return $typeName
}

function New-CompactDatabaseKeyConstraints
{
    [cmdletbinding()]
    param
    (
        [Parameter(Mandatory = $true)]
        [string]$SourceDatabase,

        [Parameter(Mandatory = $true)]
        [string]$TargetDatabase,

        [Parameter(Mandatory = $true)]
        [DatabaseInfo]$DatabaseInfo,

        [Parameter(Mandatory = $true)]
        [SqlConnectionInfo]$ConnectionInfo
    )

    $rows = @(Get-CompactDatabaseKeyConstraintRows -Database $SourceDatabase -ConnectionInfo $ConnectionInfo)
    $tableKeys = Get-CompactDatabaseAllowedTableKeys -DatabaseInfo $DatabaseInfo
    foreach ($group in ($rows | Group-Object ConstraintName, SchemaName, TableName, ConstraintType, IndexType -AsHashTable -AsString).GetEnumerator())
    {
        $items = @($group.Value)
        if ($items.Count -eq 0)
        {
            continue
        }

        $first = $items[0]
        $tableKey = Get-CompactDatabaseTableKey -SchemaName $first.SchemaName -TableName $first.TableName
        if (-not $tableKeys.ContainsKey($tableKey))
        {
            continue
        }

        $columns = foreach ($item in ($items | Sort-Object KeyOrdinal))
        {
            "$(ConvertTo-SqlIdentifier $item.ColumnName) $(if ([bool]$item.IsDescendingKey) { 'DESC' } else { 'ASC' })"
        }

        $constraintType = if ($first.ConstraintType -eq 'PK') { 'PRIMARY KEY' } else { 'UNIQUE' }
        $indexType = if ($first.IndexType -eq 1) { 'CLUSTERED' } else { 'NONCLUSTERED' }
        $sql = "ALTER TABLE $(ConvertTo-SqlIdentifier $first.SchemaName).$(ConvertTo-SqlIdentifier $first.TableName) ADD CONSTRAINT $(ConvertTo-SqlIdentifier $first.ConstraintName) $constraintType $indexType ($([string]::Join(', ', $columns)))"
        $null = Invoke-SqlcmdEx -Sql $sql -Database $TargetDatabase -ConnectionInfo $ConnectionInfo -Statistics $false
    }
}

function Get-CompactDatabaseKeyConstraintRows
{
    [cmdletbinding()]
    param
    (
        [Parameter(Mandatory = $true)]
        [string]$Database,

        [Parameter(Mandatory = $true)]
        [SqlConnectionInfo]$ConnectionInfo
    )

    $sql = @"
SELECT
    kc.name AS ConstraintName,
    kc.type AS ConstraintType,
    s.name AS SchemaName,
    t.name AS TableName,
    i.type AS IndexType,
    ic.key_ordinal AS KeyOrdinal,
    ic.is_descending_key AS IsDescendingKey,
    c.name AS ColumnName
FROM sys.key_constraints kc
INNER JOIN sys.tables t ON kc.parent_object_id = t.object_id
INNER JOIN sys.schemas s ON t.schema_id = s.schema_id
INNER JOIN sys.indexes i ON kc.parent_object_id = i.object_id AND kc.unique_index_id = i.index_id
INNER JOIN sys.index_columns ic ON i.object_id = ic.object_id AND i.index_id = ic.index_id AND ic.key_ordinal > 0
INNER JOIN sys.columns c ON ic.object_id = c.object_id AND ic.column_id = c.column_id
WHERE kc.type IN ('PK', 'UQ')
ORDER BY s.name, t.name, kc.name, ic.key_ordinal;
"@

    return Invoke-SqlcmdEx -Sql $sql -Database $Database -ConnectionInfo $ConnectionInfo -Statistics $false
}

function New-CompactDatabaseCheckConstraints
{
    [cmdletbinding()]
    param
    (
        [Parameter(Mandatory = $true)]
        [string]$SourceDatabase,

        [Parameter(Mandatory = $true)]
        [string]$TargetDatabase,

        [Parameter(Mandatory = $true)]
        [DatabaseInfo]$DatabaseInfo,

        [Parameter(Mandatory = $true)]
        [SqlConnectionInfo]$ConnectionInfo
    )

    $rows = @(Get-CompactDatabaseCheckConstraintRows -Database $SourceDatabase -ConnectionInfo $ConnectionInfo)
    $tableKeys = Get-CompactDatabaseAllowedTableKeys -DatabaseInfo $DatabaseInfo
    foreach ($row in $rows)
    {
        $tableKey = Get-CompactDatabaseTableKey -SchemaName $row.SchemaName -TableName $row.TableName
        if (-not $tableKeys.ContainsKey($tableKey))
        {
            continue
        }

        $sql = "ALTER TABLE $(ConvertTo-SqlIdentifier $row.SchemaName).$(ConvertTo-SqlIdentifier $row.TableName) WITH NOCHECK ADD CONSTRAINT $(ConvertTo-SqlIdentifier $row.ConstraintName) CHECK $($row.Definition)"
        $null = Invoke-SqlcmdEx -Sql $sql -Database $TargetDatabase -ConnectionInfo $ConnectionInfo -Statistics $false

        if ([bool]$row.IsDisabled)
        {
            $disableSql = "ALTER TABLE $(ConvertTo-SqlIdentifier $row.SchemaName).$(ConvertTo-SqlIdentifier $row.TableName) NOCHECK CONSTRAINT $(ConvertTo-SqlIdentifier $row.ConstraintName)"
            $null = Invoke-SqlcmdEx -Sql $disableSql -Database $TargetDatabase -ConnectionInfo $ConnectionInfo -Statistics $false
        }
    }
}

function Get-CompactDatabaseCheckConstraintRows
{
    [cmdletbinding()]
    param
    (
        [Parameter(Mandatory = $true)]
        [string]$Database,

        [Parameter(Mandatory = $true)]
        [SqlConnectionInfo]$ConnectionInfo
    )

    $sql = @"
SELECT
    s.name AS SchemaName,
    t.name AS TableName,
    cc.name AS ConstraintName,
    cc.definition AS Definition,
    cc.is_disabled AS IsDisabled
FROM sys.check_constraints cc
INNER JOIN sys.tables t ON cc.parent_object_id = t.object_id
INNER JOIN sys.schemas s ON t.schema_id = s.schema_id
ORDER BY s.name, t.name, cc.name;
"@

    return Invoke-SqlcmdEx -Sql $sql -Database $Database -ConnectionInfo $ConnectionInfo -Statistics $false
}

function New-CompactDatabaseForeignKeys
{
    [cmdletbinding()]
    param
    (
        [Parameter(Mandatory = $true)]
        [string]$TargetDatabase,

        [Parameter(Mandatory = $true)]
        [DatabaseInfo]$DatabaseInfo,

        [Parameter(Mandatory = $true)]
        [SqlConnectionInfo]$ConnectionInfo
    )

    $tableKeys = Get-CompactDatabaseAllowedTableKeys -DatabaseInfo $DatabaseInfo
    foreach ($table in $DatabaseInfo.Tables)
    {
        $tableKey = Get-CompactDatabaseTableKey -SchemaName $table.SchemaName -TableName $table.TableName
        if (-not $tableKeys.ContainsKey($tableKey))
        {
            continue
        }

        foreach ($fk in $table.ForeignKeys)
        {
            $referencedKey = Get-CompactDatabaseTableKey -SchemaName $fk.Schema -TableName $fk.Table
            if (-not $tableKeys.ContainsKey($referencedKey))
            {
                continue
            }

            $fkColumns = foreach ($column in $fk.FkColumns) { ConvertTo-SqlIdentifier $column.Name }
            $referencedColumns = foreach ($column in $fk.Columns) { ConvertTo-SqlIdentifier $column.Name }
            $rules = Get-CompactDatabaseForeignKeyRuleSql -ForeignKey $fk
            $tableSql = "$(ConvertTo-SqlIdentifier $table.SchemaName).$(ConvertTo-SqlIdentifier $table.TableName)"
            $referencedTableSql = "$(ConvertTo-SqlIdentifier $fk.Schema).$(ConvertTo-SqlIdentifier $fk.Table)"
            $constraintSql = ConvertTo-SqlIdentifier $fk.Name

            $sql = "ALTER TABLE $tableSql WITH NOCHECK ADD CONSTRAINT $constraintSql FOREIGN KEY ($([string]::Join(', ', $fkColumns))) REFERENCES $referencedTableSql ($([string]::Join(', ', $referencedColumns)))$rules"
            $null = Invoke-SqlcmdEx -Sql $sql -Database $TargetDatabase -ConnectionInfo $ConnectionInfo -Silent $false -Statistics $false

            $disableSql = "ALTER TABLE $tableSql NOCHECK CONSTRAINT $constraintSql"
            $null = Invoke-SqlcmdEx -Sql $disableSql -Database $TargetDatabase -ConnectionInfo $ConnectionInfo -Silent $false -Statistics $false
        }
    }
}

function Get-CompactDatabaseForeignKeyRuleSql
{
    [cmdletbinding()]
    param
    (
        [Parameter(Mandatory = $true)]
        [TableFk]$ForeignKey
    )

    $rules = ""
    if ($ForeignKey.DeleteRule -eq [ForeignKeyRule]::Cascade) { $rules += " ON DELETE CASCADE" }
    if ($ForeignKey.DeleteRule -eq [ForeignKeyRule]::SetNull) { $rules += " ON DELETE SET NULL" }
    if ($ForeignKey.DeleteRule -eq [ForeignKeyRule]::SetDefault) { $rules += " ON DELETE SET DEFAULT" }
    if ($ForeignKey.UpdateRule -eq [ForeignKeyRule]::Cascade) { $rules += " ON UPDATE CASCADE" }
    if ($ForeignKey.UpdateRule -eq [ForeignKeyRule]::SetNull) { $rules += " ON UPDATE SET NULL" }
    if ($ForeignKey.UpdateRule -eq [ForeignKeyRule]::SetDefault) { $rules += " ON UPDATE SET DEFAULT" }
    return $rules
}

function New-CompactDatabaseIndexes
{
    [cmdletbinding()]
    param
    (
        [Parameter(Mandatory = $true)]
        [string]$SourceDatabase,

        [Parameter(Mandatory = $true)]
        [string]$TargetDatabase,

        [Parameter(Mandatory = $true)]
        [DatabaseInfo]$DatabaseInfo,

        [Parameter(Mandatory = $true)]
        [SqlConnectionInfo]$ConnectionInfo,

        [Parameter(Mandatory = $true)]
        [bool]$DeferNonClusteredIndexes
    )

    $indexRows = @(Get-CompactDatabaseIndexRows -Database $SourceDatabase -ConnectionInfo $ConnectionInfo)
    $tableKeys = Get-CompactDatabaseAllowedTableKeys -DatabaseInfo $DatabaseInfo
    $scripts = [System.Collections.Generic.List[object]]::new()

    foreach ($group in ($indexRows | Group-Object SchemaName, TableName, IndexName, IndexType, IsUnique, HasFilter, FilterDefinition -AsHashTable -AsString).GetEnumerator())
    {
        $items = @($group.Value)
        if ($items.Count -eq 0)
        {
            continue
        }

        $first = $items[0]
        $tableKey = Get-CompactDatabaseTableKey -SchemaName $first.SchemaName -TableName $first.TableName
        if (-not $tableKeys.ContainsKey($tableKey))
        {
            continue
        }

        $keyColumns = foreach ($item in ($items | Where-Object { -not [bool]$_.IsIncludedColumn } | Sort-Object KeyOrdinal, IndexColumnId))
        {
            "$(ConvertTo-SqlIdentifier $item.ColumnName) $(if ([bool]$item.IsDescendingKey) { 'DESC' } else { 'ASC' })"
        }

        if (@($keyColumns).Count -eq 0)
        {
            continue
        }

        $includeColumns = foreach ($item in ($items | Where-Object { [bool]$_.IsIncludedColumn } | Sort-Object IndexColumnId))
        {
            ConvertTo-SqlIdentifier $item.ColumnName
        }

        $unique = if ([bool]$first.IsUnique) { "UNIQUE " } else { "" }
        $indexType = if ($first.IndexType -eq 1) { "CLUSTERED" } else { "NONCLUSTERED" }
        $include = if (@($includeColumns).Count -gt 0) { " INCLUDE ($([string]::Join(', ', $includeColumns)))" } else { "" }
        $filter = if ([bool]$first.HasFilter -and -not [string]::IsNullOrWhiteSpace($first.FilterDefinition)) { " WHERE $($first.FilterDefinition)" } else { "" }
        $tableSql = "$(ConvertTo-SqlIdentifier $first.SchemaName).$(ConvertTo-SqlIdentifier $first.TableName)"
        $tableLiteral = ConvertTo-SqlStringLiteral $tableSql
        $indexLiteral = ConvertTo-SqlStringLiteral $first.IndexName
        $createIndexSql = "CREATE $unique$indexType INDEX $(ConvertTo-SqlIdentifier $first.IndexName) ON $tableSql ($([string]::Join(', ', $keyColumns)))$include$filter"
        $script = "IF INDEXPROPERTY(OBJECT_ID($tableLiteral), $indexLiteral, 'IndexId') IS NULL $createIndexSql"
        $scripts.Add([pscustomobject]@{
            SchemaName = $first.SchemaName
            TableName = $first.TableName
            IndexName = $first.IndexName
            IndexType = $indexType
            CreateSql = $script
        })
    }

    if ($DeferNonClusteredIndexes)
    {
        Initialize-CompactDatabaseDeferredIndexTable -Database $TargetDatabase -ConnectionInfo $ConnectionInfo
        foreach ($script in $scripts)
        {
            if ($script.IndexType -ne 'NONCLUSTERED')
            {
                $null = Invoke-SqlcmdEx -Sql $script.CreateSql -Database $TargetDatabase -ConnectionInfo $ConnectionInfo -Statistics $false
                continue
            }

            $insertSql = "INSERT INTO SqlSizer.DeferredIndexes(SchemaName, TableName, IndexName, CreateSql) VALUES($(ConvertTo-SqlStringLiteral $script.SchemaName), $(ConvertTo-SqlStringLiteral $script.TableName), $(ConvertTo-SqlStringLiteral $script.IndexName), N$(ConvertTo-SqlStringLiteral $script.CreateSql))"
            $null = Invoke-SqlcmdEx -Sql $insertSql -Database $TargetDatabase -ConnectionInfo $ConnectionInfo -Statistics $false
        }
    }
    else
    {
        foreach ($script in $scripts)
        {
            $null = Invoke-SqlcmdEx -Sql $script.CreateSql -Database $TargetDatabase -ConnectionInfo $ConnectionInfo -Statistics $false
        }
    }
}

function Get-CompactDatabaseIndexRows
{
    [cmdletbinding()]
    param
    (
        [Parameter(Mandatory = $true)]
        [string]$Database,

        [Parameter(Mandatory = $true)]
        [SqlConnectionInfo]$ConnectionInfo
    )

    $sql = @"
SELECT
    s.name AS SchemaName,
    t.name AS TableName,
    i.name AS IndexName,
    i.type AS IndexType,
    i.is_unique AS IsUnique,
    i.has_filter AS HasFilter,
    i.filter_definition AS FilterDefinition,
    ic.key_ordinal AS KeyOrdinal,
    ic.index_column_id AS IndexColumnId,
    ic.is_descending_key AS IsDescendingKey,
    ic.is_included_column AS IsIncludedColumn,
    c.name AS ColumnName
FROM sys.indexes i
INNER JOIN sys.tables t ON i.object_id = t.object_id
INNER JOIN sys.schemas s ON t.schema_id = s.schema_id
INNER JOIN sys.index_columns ic ON i.object_id = ic.object_id AND i.index_id = ic.index_id
INNER JOIN sys.columns c ON ic.object_id = c.object_id AND ic.column_id = c.column_id
WHERE i.is_hypothetical = 0
    AND i.is_primary_key = 0
    AND i.is_unique_constraint = 0
    AND i.type IN (1, 2)
ORDER BY s.name, t.name, i.name, ic.key_ordinal, ic.index_column_id;
"@

    return Invoke-SqlcmdEx -Sql $sql -Database $Database -ConnectionInfo $ConnectionInfo -Statistics $false
}

function Initialize-CompactDatabaseDeferredIndexTable
{
    [cmdletbinding()]
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

IF OBJECT_ID(N'SqlSizer.DeferredIndexes', N'U') IS NULL
BEGIN
    CREATE TABLE SqlSizer.DeferredIndexes
    (
        Id bigint IDENTITY(1,1) NOT NULL CONSTRAINT PK_SqlSizer_DeferredIndexes PRIMARY KEY,
        SchemaName sysname NOT NULL,
        TableName sysname NOT NULL,
        IndexName sysname NOT NULL,
        CreateSql nvarchar(max) NOT NULL,
        Created bit NOT NULL CONSTRAINT DF_SqlSizer_DeferredIndexes_Created DEFAULT (0),
        CreatedAt datetime2(7) NULL
    );
END;
"@

    $null = Invoke-SqlcmdEx -Sql $sql -Database $Database -ConnectionInfo $ConnectionInfo -Statistics $false
}

function Copy-CompactDatabaseTriggers
{
    [cmdletbinding()]
    param
    (
        [Parameter(Mandatory = $true)]
        [string]$SourceDatabase,

        [Parameter(Mandatory = $true)]
        [string]$TargetDatabase,

        [Parameter(Mandatory = $true)]
        [DatabaseInfo]$DatabaseInfo,

        [Parameter(Mandatory = $true)]
        [SqlConnectionInfo]$ConnectionInfo
    )

    $tableKeys = Get-CompactDatabaseAllowedTableKeys -DatabaseInfo $DatabaseInfo
    $sql = @"
SELECT
    s.name AS SchemaName,
    t.name AS TableName,
    tr.name AS TriggerName,
    OBJECT_DEFINITION(tr.object_id) AS Definition,
    tr.is_disabled AS IsDisabled
FROM sys.triggers tr
INNER JOIN sys.tables t ON tr.parent_id = t.object_id
INNER JOIN sys.schemas s ON t.schema_id = s.schema_id
WHERE tr.is_ms_shipped = 0
ORDER BY s.name, t.name, tr.name;
"@

    $rows = @(Invoke-SqlcmdEx -Sql $sql -Database $SourceDatabase -ConnectionInfo $ConnectionInfo -Statistics $false)
    foreach ($row in $rows)
    {
        $tableKey = Get-CompactDatabaseTableKey -SchemaName $row.SchemaName -TableName $row.TableName
        if (-not $tableKeys.ContainsKey($tableKey) -or [string]::IsNullOrWhiteSpace($row.Definition))
        {
            continue
        }

        $definition = $row.Definition.Replace("'", "''")
        $triggerResult = Invoke-SqlcmdEx -Sql "EXEC(N'$definition')" -Database $TargetDatabase -ConnectionInfo $ConnectionInfo -Statistics $false -Silent $true
        if ($triggerResult -eq $false)
        {
            Write-Warning "Skipped trigger [$($row.TriggerName)] on [$($row.SchemaName)].[$($row.TableName)] in [$TargetDatabase]: it may reference features (e.g., full-text search, CLR) not configured in the target database."
        }

        if ([bool]$row.IsDisabled)
        {
            $disableSql = "DISABLE TRIGGER $(ConvertTo-SqlIdentifier $row.TriggerName) ON $(ConvertTo-SqlIdentifier $row.SchemaName).$(ConvertTo-SqlIdentifier $row.TableName)"
            $null = Invoke-SqlcmdEx -Sql $disableSql -Database $TargetDatabase -ConnectionInfo $ConnectionInfo -Statistics $false
        }
    }
}

function Test-CompactDatabaseSchema
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

    foreach ($table in $DatabaseInfo.Tables)
    {
        $exists = Test-TableExists -Database $Database -SchemaName $table.SchemaName -TableName $table.TableName -ConnectionInfo $ConnectionInfo
        if (-not $exists)
        {
            throw "Compact database validation failed. Missing table $($table.SchemaName).$($table.TableName) in $Database."
        }
    }
}

function Get-CompactDatabaseAllowedTableKeys
{
    [cmdletbinding()]
    param
    (
        [Parameter(Mandatory = $true)]
        [DatabaseInfo]$DatabaseInfo
    )

    $result = @{}
    foreach ($table in $DatabaseInfo.Tables)
    {
        $result[(Get-CompactDatabaseTableKey -SchemaName $table.SchemaName -TableName $table.TableName)] = $true
    }

    return $result
}

function Get-CompactDatabaseTableKey
{
    [cmdletbinding()]
    param
    (
        [Parameter(Mandatory = $true)]
        [string]$SchemaName,

        [Parameter(Mandatory = $true)]
        [string]$TableName
    )

    return "$SchemaName, $TableName"
}
