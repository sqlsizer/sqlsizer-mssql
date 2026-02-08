<#
.SYNOPSIS
    Helper functions for Find-Subset integration tests.
    
.DESCRIPTION
    Provides utilities for session management, subset validation, and test assertions.
#>

function New-TestSession {
    <#
    .SYNOPSIS
        Creates a new SqlSizer session for testing.
    
    .OUTPUTS
        Session ID string.
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$Database,
        
        [Parameter(Mandatory = $true)]
        [SqlConnectionInfo]$ConnectionInfo,
        
        [Parameter(Mandatory = $true)]
        [DatabaseInfo]$DatabaseInfo
    )
    
    $sessionId = Start-SqlSizerSession `
        -Database $Database `
        -ConnectionInfo $ConnectionInfo `
        -DatabaseInfo $DatabaseInfo
    
    return $sessionId
}

function Remove-TestSession {
    <#
    .SYNOPSIS
        Cleans up a test session.
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$SessionId,
        
        [Parameter(Mandatory = $true)]
        [string]$Database,
        
        [Parameter(Mandatory = $true)]
        [DatabaseInfo]$DatabaseInfo,
        
        [Parameter(Mandatory = $true)]
        [SqlConnectionInfo]$ConnectionInfo
    )
    
    try {
        Clear-SqlSizerSession `
            -SessionId $SessionId `
            -Database $Database `
            -DatabaseInfo $DatabaseInfo `
            -ConnectionInfo $ConnectionInfo
    }
    catch {
        Write-Warning "Failed to clear session $SessionId : $_"
    }
}

function Get-SubsetSummary {
    <#
    .SYNOPSIS
        Returns a hashtable summarizing subset tables and row counts.
    
    .OUTPUTS
        Hashtable with keys "SchemaName.TableName" and values as row counts.
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$SessionId,
        
        [Parameter(Mandatory = $true)]
        [string]$Database,
        
        [Parameter(Mandatory = $true)]
        [SqlConnectionInfo]$ConnectionInfo,
        
        [Parameter(Mandatory = $true)]
        [DatabaseInfo]$DatabaseInfo
    )
    
    $tables = Get-SubsetTables `
        -Database $Database `
        -ConnectionInfo $ConnectionInfo `
        -DatabaseInfo $DatabaseInfo `
        -SessionId $SessionId
    
    $summary = @{}
    foreach ($table in $tables) {
        $key = "$($table.SchemaName).$($table.TableName)"
        $summary[$key] = $table.RowCount
    }
    
    return $summary
}

function Get-TotalSubsetRows {
    <#
    .SYNOPSIS
        Returns total row count across all subset tables.
    #>
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$SubsetSummary
    )
    
    return ($SubsetSummary.Values | Measure-Object -Sum).Sum
}

function Assert-SubsetContains {
    <#
    .SYNOPSIS
        Asserts that the subset contains a specific table with optional row count.
    #>
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$SubsetSummary,
        
        [Parameter(Mandatory = $true)]
        [string]$Schema,
        
        [Parameter(Mandatory = $true)]
        [string]$Table,
        
        [Parameter(Mandatory = $false)]
        [int]$ExpectedRows = -1,
        
        [Parameter(Mandatory = $false)]
        [int]$MinRows = -1,
        
        [Parameter(Mandatory = $false)]
        [int]$MaxRows = -1
    )
    
    $key = "$Schema.$Table"
    
    if (-not $SubsetSummary.ContainsKey($key)) {
        throw "Subset does not contain table $key. Tables present: $($SubsetSummary.Keys -join ', ')"
    }
    
    $actualRows = $SubsetSummary[$key]
    
    if ($ExpectedRows -ge 0 -and $actualRows -ne $ExpectedRows) {
        throw "Table $key has $actualRows rows, expected exactly $ExpectedRows"
    }
    
    if ($MinRows -ge 0 -and $actualRows -lt $MinRows) {
        throw "Table $key has $actualRows rows, expected at least $MinRows"
    }
    
    if ($MaxRows -ge 0 -and $actualRows -gt $MaxRows) {
        throw "Table $key has $actualRows rows, expected at most $MaxRows"
    }
}

function Assert-SubsetExcludes {
    <#
    .SYNOPSIS
        Asserts that the subset does NOT contain a specific table (or has 0 rows).
    #>
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$SubsetSummary,
        
        [Parameter(Mandatory = $true)]
        [string]$Schema,
        
        [Parameter(Mandatory = $true)]
        [string]$Table
    )
    
    $key = "$Schema.$Table"
    
    if ($SubsetSummary.ContainsKey($key) -and $SubsetSummary[$key] -gt 0) {
        throw "Subset should NOT contain table $key, but it has $($SubsetSummary[$key]) rows"
    }
}

function Assert-SubsetRowCount {
    <#
    .SYNOPSIS
        Asserts total row count across all subset tables.
    #>
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$SubsetSummary,
        
        [Parameter(Mandatory = $false)]
        [int]$ExpectedTotal = -1,
        
        [Parameter(Mandatory = $false)]
        [int]$MinTotal = -1,
        
        [Parameter(Mandatory = $false)]
        [int]$MaxTotal = -1
    )
    
    $total = Get-TotalSubsetRows -SubsetSummary $SubsetSummary
    
    if ($ExpectedTotal -ge 0 -and $total -ne $ExpectedTotal) {
        throw "Total subset rows is $total, expected exactly $ExpectedTotal"
    }
    
    if ($MinTotal -ge 0 -and $total -lt $MinTotal) {
        throw "Total subset rows is $total, expected at least $MinTotal"
    }
    
    if ($MaxTotal -ge 0 -and $total -gt $MaxTotal) {
        throw "Total subset rows is $total, expected at most $MaxTotal"
    }
}

function New-TestQuery {
    <#
    .SYNOPSIS
        Creates a Query2 object for initializing start sets.
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$Schema,
        
        [Parameter(Mandatory = $true)]
        [string]$Table,
        
        [Parameter(Mandatory = $true)]
        [string[]]$KeyColumns,
        
        [Parameter(Mandatory = $false)]
        [TraversalState]$State = [TraversalState]::Include,
        
        [Parameter(Mandatory = $false)]
        [string]$Where = '',
        
        [Parameter(Mandatory = $false)]
        [int]$Top = 0
    )
    
    $query = New-Object Query2
    $query.State = $State
    $query.Schema = $Schema
    $query.Table = $Table
    $query.KeyColumns = $KeyColumns
    $query.Where = $Where
    $query.Top = $Top
    
    return $query
}

function Invoke-FindSubsetTest {
    <#
    .SYNOPSIS
        Executes a complete Find-Subset test cycle.
    
    .DESCRIPTION
        Creates session, initializes start set, runs Find-Subset, and returns summary.
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$Database,
        
        [Parameter(Mandatory = $true)]
        [SqlConnectionInfo]$ConnectionInfo,
        
        [Parameter(Mandatory = $true)]
        [DatabaseInfo]$DatabaseInfo,
        
        [Parameter(Mandatory = $true)]
        [Query2[]]$Queries,
        
        [Parameter(Mandatory = $false)]
        [bool]$FullSearch = $false,
        
        [Parameter(Mandatory = $false)]
        [bool]$UseDfs = $false,
        
        [Parameter(Mandatory = $false)]
        [TableInfo2[]]$IgnoredTables = $null,
        
        [Parameter(Mandatory = $false)]
        [TraversalConfiguration]$TraversalConfiguration = $null,
        
        [Parameter(Mandatory = $false)]
        [int]$MaxBatchSize = -1
    )
    
    # Create session
    $sessionId = New-TestSession `
        -Database $Database `
        -ConnectionInfo $ConnectionInfo `
        -DatabaseInfo $DatabaseInfo
    
    try {
        # Initialize start set
        $null = Initialize-StartSet `
            -Database $Database `
            -ConnectionInfo $ConnectionInfo `
            -Queries $Queries `
            -DatabaseInfo $DatabaseInfo `
            -SessionId $sessionId
        
        # Build Find-Subset parameters
        $findParams = @{
            Database       = $Database
            ConnectionInfo = $ConnectionInfo
            DatabaseInfo   = $DatabaseInfo
            SessionId      = $sessionId
            FullSearch     = $FullSearch
            UseDfs         = $UseDfs
        }
        
        if ($null -ne $IgnoredTables) {
            $findParams['IgnoredTables'] = $IgnoredTables
        }
        
        if ($null -ne $TraversalConfiguration) {
            $findParams['TraversalConfiguration'] = $TraversalConfiguration
        }
        
        if ($MaxBatchSize -gt 0) {
            $findParams['MaxBatchSize'] = $MaxBatchSize
        }
        
        # Run Find-Subset
        $result = Find-Subset @findParams
        
        # Get summary
        $summary = Get-SubsetSummary `
            -SessionId $sessionId `
            -Database $Database `
            -ConnectionInfo $ConnectionInfo `
            -DatabaseInfo $DatabaseInfo
        
        return [pscustomobject]@{
            SessionId = $sessionId
            Result    = $result
            Summary   = $summary
            Success   = $true
        }
    }
    catch {
        return [pscustomobject]@{
            SessionId = $sessionId
            Result    = $null
            Summary   = @{}
            Success   = $false
            Error     = $_
        }
    }
}

function Test-DatabaseExists {
    <#
    .SYNOPSIS
        Checks if a database exists.
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$Database,
        
        [Parameter(Mandatory = $true)]
        [SqlConnectionInfo]$ConnectionInfo
    )
    
    $query = "SELECT DB_ID('$Database') AS DbId"
    $result = Invoke-SqlcmdEx -Sql $query -Database 'master' -ConnectionInfo $ConnectionInfo
    return $null -ne $result.DbId
}

function Clear-AllSessions {
    <#
    .SYNOPSIS
        Clears all SqlSizer sessions from the test database.
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$Database,
        
        [Parameter(Mandatory = $true)]
        [SqlConnectionInfo]$ConnectionInfo,

        [Parameter(Mandatory = $true)]
        [DatabaseInfo]$DatabaseInfo
    )
    
    try {
        Clear-SqlSizerSessions -Database $Database -DatabaseInfo $DatabaseInfo -ConnectionInfo $ConnectionInfo
    }
    catch {
        Write-Warning "Failed to clear sessions: $_"
    }
}

function Get-TestTableInfo {
    <#
    .SYNOPSIS
        Creates a TableInfo2 object for specifying ignored tables.
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$Schema,
        
        [Parameter(Mandatory = $true)]
        [string]$Table
    )
    
    $tableInfo = New-Object TableInfo2
    $tableInfo.SchemaName = $Schema
    $tableInfo.TableName = $Table
    return $tableInfo
}

function New-TraversalConfig {
    <#
    .SYNOPSIS
        Creates a TraversalConfiguration with rules.
    #>
    param(
        [Parameter(Mandatory = $true)]
        [TraversalRule[]]$Rules
    )
    
    $config = New-Object TraversalConfiguration
    $config.Rules = $Rules
    return $config
}

function New-TraversalRuleWithMaxDepth {
    <#
    .SYNOPSIS
        Creates a TraversalRule with MaxDepth constraint.
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$Schema,
        
        [Parameter(Mandatory = $true)]
        [string]$Table,
        
        [Parameter(Mandatory = $true)]
        [int]$MaxDepth
    )
    
    $rule = New-Object TraversalRule -ArgumentList $Schema, $Table
    $rule.Constraints = New-Object TraversalConstraints
    $rule.Constraints.MaxDepth = $MaxDepth
    return $rule
}

function New-TraversalRuleWithTop {
    <#
    .SYNOPSIS
        Creates a TraversalRule with Top constraint.
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$Schema,
        
        [Parameter(Mandatory = $true)]
        [string]$Table,
        
        [Parameter(Mandatory = $true)]
        [int]$Top
    )
    
    $rule = New-Object TraversalRule -ArgumentList $Schema, $Table
    $rule.Constraints = New-Object TraversalConstraints
    $rule.Constraints.Top = $Top
    return $rule
}

function New-TraversalRuleWithStateOverride {
    <#
    .SYNOPSIS
        Creates a TraversalRule with state override.
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$Schema,
        
        [Parameter(Mandatory = $true)]
        [string]$Table,
        
        [Parameter(Mandatory = $true)]
        [TraversalState]$State
    )
    
    $rule = New-Object TraversalRule -ArgumentList $Schema, $Table
    $rule.StateOverride = New-Object StateOverride -ArgumentList $State
    return $rule
}
