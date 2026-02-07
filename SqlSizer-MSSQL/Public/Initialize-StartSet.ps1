<#
.SYNOPSIS
    Initializes the starting set of rows for subset extraction using Query2 objects with TraversalState.

.DESCRIPTION
    Executes queries to identify and mark the initial set of rows according to their specified TraversalState.
    Respects the Query2.State property, allowing you to define starting sets with 
    different traversal behaviors:
    
    - TraversalState.Pending: Records need evaluation (for forward subset finding)
    - TraversalState.Include: Records explicitly included in subset
    - TraversalState.InboundOnly: Records for removal traversal (only incoming FKs)
    
    These rows serve as the "seed" data that forms the foundation of the subset. Related records 
    will be discovered through foreign key traversal during subsequent Find-Subset or 
    Find-RemovalSubset execution.

.PARAMETER Queries
    Array of Query2 objects defining the starting set selection criteria (Schema, Table, 
    KeyColumns, WHERE clause, TOP, ORDER BY, State). At least one query is required.

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
    # Forward traversal (subset finding)
    $query = New-Object -TypeName Query2
    $query.State = [TraversalState]::Pending
    $query.Schema = "Person"
    $query.Table = "Person"
    $query.KeyColumns = @('BusinessEntityID')
    $query.Where = "[`$table].FirstName = 'John'"
    $query.Top = 10
    $query.OrderBy = "[`$table].LastName ASC"
    
    $result = Initialize-StartSet -Queries @($query) -Database $database -DatabaseInfo $info -ConnectionInfo $connection -SessionId $sessionId
    Write-Host "Initialized $($result.TotalRowsInserted) rows for forward traversal"

.EXAMPLE
    # Removal traversal (data removal)
    $query = New-Object -TypeName Query2
    $query.State = [TraversalState]::InboundOnly
    $query.Schema = "Person"
    $query.Table = "Person"
    $query.KeyColumns = @('BusinessEntityID')
    $query.Where = "[`$table].FirstName = 'Rob'"
    
    $result = Initialize-StartSet -Queries @($query) -Database $database -DatabaseInfo $info -ConnectionInfo $connection -SessionId $sessionId
    Write-Host "Initialized $($result.TotalRowsInserted) rows for removal"

.NOTES
    - Query2.State property is RESPECTED - rows are marked with the specified TraversalState
    - Use TraversalState.Pending for forward subset finding (Find-Subset)
    - Use TraversalState.InboundOnly for removal operations (Find-RemovalSubset)
    - Each query must specify Schema, Table, KeyColumns, and State
    - Tables must have a primary key to be used for subsetting
#>
function Initialize-StartSet
{
    [cmdletbinding()]
    [OutputType([PSCustomObject])]
    param
    (
        [Parameter(Mandatory = $true)]
        [Query2[]]$Queries,

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
        
        # Validate State is set
        if ($null -eq $query.State)
        {
            throw "Query2 must specify a State property for table $($query.Schema).$($query.Table)"
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
        
        # Build TOP clause if specified
        $topClause = ""
        if ($query.Top -ne 0)
        {
            $topClause = " TOP $($query.Top) "
        }
        
        # Build ORDER BY clause if specified
        $orderByClause = ""
        if ($null -ne $query.OrderBy)
        {
            # Basic SQL injection protection
            if ($query.OrderBy -match '[;]|--|\bDROP\b|\bDELETE\b|\bEXEC\b|\bUPDATE\b')
            {
                throw "OrderBy clause contains potentially dangerous SQL for table $($query.Schema).$($query.Table)"
            }
            $orderByClause = " ORDER BY $($query.OrderBy)"
        }
        
        # Validate WHERE clause if specified
        if ($null -ne $query.Where)
        {
            # Basic SQL injection protection (allow -- in column names like [--Comment] but not as comment starter)
            if ($query.Where -match '[;]|--(?!\s*\[)|\bDROP\b|\bDELETE\b|\bEXEC\b|\bUPDATE\b')
            {
                throw "Where clause contains potentially dangerous SQL for table $($query.Schema).$($query.Table)"
            }
        }
        
        # Get processing table name for this session
        $processingTable = $Structure.GetProcessingName($signature, $SessionId)
        
        # Build INSERT statement to populate processing table with initial subset rows
        # Processing table schema: KeyColumns..., State, ParentTable, ParentIteration, ChildTable, Iteration
        $sql = "INSERT INTO $processingTable SELECT $topClause"

        # Add key columns (using -join for efficiency)
        $keyColumns = $query.KeyColumns -join ', '
        $sql += "$keyColumns, "

        # Add state and metadata columns
        # State: Use the TraversalState specified in Query2.State property
        # ParentTable: NULL (no parent for starting set)
        # ParentIteration: 0 (starting iteration)
        # ChildTable: NULL (no child yet)
        # Iteration: $StartIteration (current iteration)
        $sql += "$([int]$query.State) as [State], NULL as [ParentTable], 0 as [ParentIteration], NULL as [ChildTable], $StartIteration as [Iteration]"
        $sql += " FROM $($query.Schema).$($query.Table) as $tableAlias"

        # Add WHERE clause if specified
        if ($null -ne $query.Where)
        {
            $sql += " WHERE $($query.Where)"
        }

        $sql += $orderByClause

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
