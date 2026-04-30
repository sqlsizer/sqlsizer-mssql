<#
.SYNOPSIS
    Initializes the starting set of rows for subset extraction using SqlSizerQuery objects with TraversalState.

.DESCRIPTION
    Executes queries to identify and mark the initial set of rows according to their specified TraversalState.
    Respects the SqlSizerQuery.State property, allowing you to define starting sets with 
    different traversal behaviors:
    
    - TraversalState.Include: Records explicitly included in the subset closure
    - TraversalState.IncludeFull: Seed records that also pull incoming FK dependents
    - TraversalState.InboundOnly: Records for removal traversal (only incoming FKs)
    - TraversalState.Pending: Compatibility/bookkeeping records, not output unless promoted
    
    These rows serve as the "seed" data that forms the foundation of the subset. Related records 
    will be discovered through foreign key traversal during subsequent Find-Subset or 
    Find-RemovalSubset execution.

.PARAMETER Queries
    Array of SqlSizerQuery objects defining the starting set selection criteria (Schema, Table, 
    KeyColumns, WHERE clause, TOP, ORDER BY, State). KeyColumns must match the table primary key;
    generated seed SQL emits those keys in metadata primary-key order. At least one query is required.

.PARAMETER Database
    Target database name where the subset will be created.

.PARAMETER StartIteration
    Initial iteration number for tracking traversal progress (default: 0).

.PARAMETER DatabaseInfo
    Metadata about the database schema (tables, columns, relationships).

.PARAMETER ConnectionInfo
    SQL Server connection information.

.PARAMETER SessionId
    Unique identifier for this subsetting session.

.OUTPUTS
    PSCustomObject with properties:
    - QueriesProcessed: Number of queries executed
    - TotalRowsInserted: Total number of rows added to the starting set
    - SessionId: The session identifier
    - StartIteration: The iteration number used

.EXAMPLE
    # Subset closure traversal
    $query = New-Object -TypeName SqlSizerQuery
    $query.State = [TraversalState]::Include
    $query.Schema = "Person"
    $query.Table = "Person"
    $query.KeyColumns = @('BusinessEntityID')
    $query.Where = "[`$table].FirstName = 'John'"
    $query.Top = 10
    $query.OrderBy = "[`$table].LastName ASC"
    
    $result = Initialize-StartSet -Queries @($query) -Database $database -DatabaseInfo $info -ConnectionInfo $connection -SessionId $sessionId
    Write-Host "Initialized $($result.TotalRowsInserted) rows for subset closure traversal"

.EXAMPLE
    # Removal traversal (data removal)
    $query = New-Object -TypeName SqlSizerQuery
    $query.State = [TraversalState]::InboundOnly
    $query.Schema = "Person"
    $query.Table = "Person"
    $query.KeyColumns = @('BusinessEntityID')
    $query.Where = "[`$table].FirstName = 'Rob'"
    
    $result = Initialize-StartSet -Queries @($query) -Database $database -DatabaseInfo $info -ConnectionInfo $connection -SessionId $sessionId
    Write-Host "Initialized $($result.TotalRowsInserted) rows for removal"

.NOTES
    - SqlSizerQuery.State property is RESPECTED - rows are marked with the specified TraversalState
    - Use TraversalState.Include for normal subset finding (Find-Subset)
    - Use TraversalState.IncludeFull when seed rows should also traverse incoming foreign keys
    - Use TraversalState.InboundOnly for removal operations (Find-RemovalSubset)
    - Each query must specify Schema, Table, primary-key KeyColumns, and State
    - When Top is greater than 0 and OrderBy is omitted, rows are ordered by the table primary key
    - Tables must have a primary key to be used for subsetting
#>
function Get-StartSetNormalizedColumnName
{
    param
    (
        [Parameter(Mandatory = $true)]
        [string]$ColumnName
    )

    $name = $ColumnName.Trim()
    if ([string]::IsNullOrWhiteSpace($name))
    {
        return $name
    }

    $segments = $name -split '\.'
    $name = $segments[$segments.Count - 1].Trim()

    if ($name.StartsWith('[') -and $name.EndsWith(']'))
    {
        $name = $name.Substring(1, $name.Length - 2).Replace(']]', ']')
    }

    return $name
}

function Resolve-StartSetPrimaryKeyColumns
{
    param
    (
        [Parameter(Mandatory = $true)]
        [SqlSizerQuery]$Query,

        [Parameter(Mandatory = $true)]
        [TableInfo]$Table
    )

    $primaryKeyColumns = @($Table.PrimaryKey)
    $primaryKeyNames = @($primaryKeyColumns | ForEach-Object { $_.Name })
    $expected = [string]::Join(', ', ($primaryKeyNames | ForEach-Object { ConvertTo-SqlIdentifier $_ }))
    $provided = @($Query.KeyColumns | ForEach-Object { Get-StartSetNormalizedColumnName $_ })
    $providedText = [string]::Join(', ', ($provided | ForEach-Object { ConvertTo-SqlIdentifier $_ }))

    if ($provided.Count -ne $primaryKeyColumns.Count)
    {
        throw "KeyColumns for $($Query.Schema).$($Query.Table) must exactly match primary key columns in any order. Expected: $expected. Provided: $providedText."
    }

    $primaryKeyLookup = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($name in $primaryKeyNames)
    {
        $null = $primaryKeyLookup.Add($name)
    }

    $providedLookup = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($name in $provided)
    {
        if (-not $primaryKeyLookup.Contains($name))
        {
            throw "KeyColumns for $($Query.Schema).$($Query.Table) must exactly match primary key columns in any order. Expected: $expected. Provided: $providedText."
        }

        if (-not $providedLookup.Add($name))
        {
            throw "KeyColumns for $($Query.Schema).$($Query.Table) contains duplicate column '$name'. Expected primary key columns: $expected."
        }
    }

    foreach ($name in $primaryKeyNames)
    {
        if (-not $providedLookup.Contains($name))
        {
            throw "KeyColumns for $($Query.Schema).$($Query.Table) must exactly match primary key columns in any order. Expected: $expected. Provided: $providedText."
        }
    }

    return ,$primaryKeyColumns
}

function Get-StartSetColumnReference
{
    param
    (
        [Parameter(Mandatory = $true)]
        [string]$ColumnName,

        [Parameter(Mandatory = $true)]
        [string]$TableAlias
    )

    return "$TableAlias.$(ConvertTo-SqlIdentifier $ColumnName)"
}

function Test-StartSetSqlFragmentReferencesColumn
{
    param
    (
        [Parameter(Mandatory = $false)]
        [string]$SqlFragment,

        [Parameter(Mandatory = $true)]
        [string]$ColumnName
    )

    if ([string]::IsNullOrWhiteSpace($SqlFragment))
    {
        return $false
    }

    $plainColumn = [regex]::Escape($ColumnName)
    $bracketedColumn = '\[' + [regex]::Escape($ColumnName.Replace(']', ']]')) + '\]'
    $identifierPrefix = '(?:(?:\[[^\]]+\]|[A-Za-z_][A-Za-z0-9_]*)\.)*'
    $pattern = "(?i)(?<![A-Za-z0-9_])$identifierPrefix(?:$bracketedColumn|$plainColumn)(?![A-Za-z0-9_])"

    return $SqlFragment -match $pattern
}

function Get-StartSetPrimaryKeyOrderByTerms
{
    param
    (
        [Parameter(Mandatory = $true)]
        [ColumnInfo[]]$PrimaryKeyColumns,

        [Parameter(Mandatory = $true)]
        [string]$TableAlias,

        [Parameter(Mandatory = $false)]
        [string]$ExistingOrderBy
    )

    $terms = [System.Collections.Generic.List[string]]::new()
    foreach ($column in $PrimaryKeyColumns)
    {
        if (Test-StartSetSqlFragmentReferencesColumn -SqlFragment $ExistingOrderBy -ColumnName $column.Name)
        {
            continue
        }

        $terms.Add("$(Get-StartSetColumnReference -ColumnName $column.Name -TableAlias $TableAlias) ASC")
    }

    return ,$terms.ToArray()
}

function Get-StartSetKnownIndexedColumnNames
{
    param
    (
        [Parameter(Mandatory = $true)]
        [TableInfo]$Table
    )

    $names = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($column in $Table.PrimaryKey)
    {
        $null = $names.Add($column.Name)
    }

    if ($null -eq $Table.Indexes)
    {
        $result = foreach ($name in $names) { $name }
        return ,$result
    }

    foreach ($index in $Table.Indexes)
    {
        foreach ($columnName in $index.Columns)
        {
            $null = $names.Add($columnName)
        }
    }

    $result = foreach ($name in $names) { $name }
    return ,$result
}

function Write-StartSetWhereIndexWarning
{
    param
    (
        [Parameter(Mandatory = $true)]
        [SqlSizerQuery]$Query,

        [Parameter(Mandatory = $true)]
        [TableInfo]$Table
    )

    if ([string]::IsNullOrWhiteSpace($Query.Where))
    {
        return
    }

    foreach ($columnName in (Get-StartSetKnownIndexedColumnNames -Table $Table))
    {
        if (Test-StartSetSqlFragmentReferencesColumn -SqlFragment $Query.Where -ColumnName $columnName)
        {
            return
        }
    }

    Write-Warning "WHERE clause for $($Query.Schema).$($Query.Table) does not appear to reference a primary key or indexed column; SQL Server may scan the source table."
}

function New-StartSetInsertSql
{
    param
    (
        [Parameter(Mandatory = $true)]
        [SqlSizerQuery]$Query,

        [Parameter(Mandatory = $true)]
        [TableInfo]$Table,

        [Parameter(Mandatory = $true)]
        [string]$ProcessingTable,

        [Parameter(Mandatory = $true)]
        [int]$StartIteration,

        [Parameter(Mandatory = $false)]
        [string]$TableAlias = '[$table]'
    )

    if ($Query.Top -lt 0)
    {
        throw "Top must be greater than or equal to 0 for table $($Query.Schema).$($Query.Table)"
    }

    $primaryKeyColumns = Resolve-StartSetPrimaryKeyColumns -Query $Query -Table $Table

    $topClause = ""
    if ($Query.Top -gt 0)
    {
        $topClause = " TOP $($Query.Top) "
    }

    $orderByClause = ""
    if (-not [string]::IsNullOrWhiteSpace($Query.OrderBy))
    {
        if ($Query.OrderBy -match '[;]|--|\bDROP\b|\bDELETE\b|\bEXEC\b|\bUPDATE\b')
        {
            throw "OrderBy clause contains potentially dangerous SQL for table $($Query.Schema).$($Query.Table)"
        }

        if ($Query.Top -gt 0)
        {
            $primaryKeyOrderByTerms = Get-StartSetPrimaryKeyOrderByTerms -PrimaryKeyColumns $primaryKeyColumns -TableAlias $TableAlias -ExistingOrderBy $Query.OrderBy
            if ($primaryKeyOrderByTerms.Count -gt 0)
            {
                $orderByClause = " ORDER BY $($Query.OrderBy), $([string]::Join(', ', $primaryKeyOrderByTerms))"
            }
            else
            {
                $orderByClause = " ORDER BY $($Query.OrderBy)"
            }
        }
        else
        {
            $orderByClause = " ORDER BY $($Query.OrderBy)"
        }
    }
    elseif ($Query.Top -gt 0)
    {
        $primaryKeyOrderByTerms = Get-StartSetPrimaryKeyOrderByTerms -PrimaryKeyColumns $primaryKeyColumns -TableAlias $TableAlias
        $orderByClause = " ORDER BY $([string]::Join(', ', $primaryKeyOrderByTerms))"
    }

    if (-not [string]::IsNullOrWhiteSpace($Query.Where))
    {
        if ($Query.Where -match '[;]|--(?!\s*\[)|\bDROP\b|\bDELETE\b|\bEXEC\b|\bUPDATE\b')
        {
            throw "Where clause contains potentially dangerous SQL for table $($Query.Schema).$($Query.Table)"
        }

        Write-StartSetWhereIndexWarning -Query $Query -Table $Table
    }

    $keyColumns = ($primaryKeyColumns | ForEach-Object { Get-StartSetColumnReference -ColumnName $_.Name -TableAlias $TableAlias }) -join ', '
    $sql = "INSERT INTO $ProcessingTable SELECT $topClause"
    $sql += "$keyColumns, "
    $sql += "$([int]$Query.State) as [State], NULL as [Source], 0 as [Depth], NULL as [Fk], $StartIteration as [Iteration]"
    $sql += " FROM $($Query.Schema).$($Query.Table) as $TableAlias"

    if (-not [string]::IsNullOrWhiteSpace($Query.Where))
    {
        $sql += " WHERE $($Query.Where)"
    }

    $sql += $orderByClause

    return $sql
}

function Initialize-StartSet
{
    [cmdletbinding()]
    [OutputType([PSCustomObject])]
    param
    (
        [Parameter(Mandatory = $true)]
        [SqlSizerQuery[]]$Queries,

        [Parameter(Mandatory = $true)]
        [string]$Database,

        [Parameter(Mandatory = $false)]
        [int]$StartIteration = 0,

        [Parameter(Mandatory = $true)]
        [DatabaseInfo]$DatabaseInfo,

        [Parameter(Mandatory = $true)]
        [SqlConnectionInfo]$ConnectionInfo,

        [Parameter(Mandatory = $true)]
        [string]$SessionId
    )

    # Input validation
    if ($null -eq $Queries -or $Queries.Count -eq 0)
    {
        throw "At least one query must be provided to initialize the start set"
    }

    # Validate each query has required properties
    foreach ($query in $Queries)
    {
        if ([string]::IsNullOrWhiteSpace($query.Schema) -or [string]::IsNullOrWhiteSpace($query.Table))
        {
            throw "Query must specify both Schema and Table properties"
        }
        
        if ($null -eq $query.KeyColumns -or $query.KeyColumns.Count -eq 0)
        {
            throw "Query must specify KeyColumns for table $($query.Schema).$($query.Table)"
        }

        if ($query.Top -lt 0)
        {
            throw "Top must be greater than or equal to 0 for table $($query.Schema).$($query.Table)"
        }
        
        # Validate State is set
        if ($null -eq $query.State)
        {
            throw "SqlSizerQuery must specify a State property for table $($query.Schema).$($query.Table)"
        }
    }

    # Table alias constant used in WHERE and ORDER BY clauses
    $tableAlias = '[$table]'
    
    # Result tracking
    $result = @{
        QueriesProcessed = 0
        TotalRowsInserted = 0
        SessionId = $SessionId
        StartIteration = $StartIteration
    }

    # Get database structure metadata
    $structure = [Structure]::new($DatabaseInfo)
    
    $queryIndex = 0
    foreach ($query in $Queries)
    {
        $queryIndex++
        $stateText = [TraversalState]$query.State
        Write-Verbose "Processing query $queryIndex of $($Queries.Count): $($query.Schema).$($query.Table) [State: $stateText]"
        
        # Locate the table in database metadata
        $table = $DatabaseInfo.Tables | Where-Object { 
            ($_.SchemaName -eq $query.Schema) -and ($_.TableName -eq $query.Table) 
        }

        if ($null -eq $table)
        {
            throw "Could not find table $($query.Schema).$($query.Table) to initialize the start set."
        }

        # Get table signature (primary key information)
        $signature = $structure.Tables[$table]

        if ($null -eq $signature)
        {
            throw "Table $($query.Schema).$($query.Table) does not have a primary key and cannot be used for subsetting."
        }

        # Get processing table name for this session
        $processingTable = $Structure.GetProcessingName($signature, $SessionId)

        # Build INSERT statement to populate processing table with initial subset rows.
        # Processing table schema: KeyColumns..., State, Source, Depth, Fk, Iteration.
        $sql = New-StartSetInsertSql `
            -Query $query `
            -Table $table `
            -ProcessingTable $processingTable `
            -StartIteration $StartIteration `
            -TableAlias $tableAlias

        # Execute the query to populate initial subset
        try
        {
            Write-Verbose "  Executing: $sql"
            
            # Use OUTPUT clause to count inserted rows
            $countSql = $sql + "; SELECT @@ROWCOUNT AS RowsInserted"
            $result_query = Invoke-SqlcmdEx -Sql $countSql -Database $Database -ConnectionInfo $ConnectionInfo
            
            $rowsInserted = if ($null -ne $result_query) { $result_query.RowsInserted } else { 0 }
            
            if ($rowsInserted -eq 0)
            {
                Write-Warning "Query returned 0 rows: $($query.Schema).$($query.Table)$(if ($query.Where) { " WHERE $($query.Where)" })"
            }
            else
            {
                Write-Verbose "  Inserted $rowsInserted rows with State=$stateText into processing table"
            }
            
            $result.TotalRowsInserted += $rowsInserted
            $result.QueriesProcessed++
        }
        catch
        {
            throw "Failed to initialize start set for table $($query.Schema).$($query.Table): $($_.Exception.Message)"
        }
    }
    
    # Return summary information
    return [PSCustomObject]$result
}
