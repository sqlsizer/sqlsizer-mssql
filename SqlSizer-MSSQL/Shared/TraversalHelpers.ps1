<#
.SYNOPSIS
    Helper functions for graph traversal operations in Find-Subset.
    
.DESCRIPTION
    This module contains pure, testable helper functions extracted from Find-Subset.
    These functions handle state transitions, constraints, and traversal logic.
#>

function Get-NewTraversalState
{
    <#
    .SYNOPSIS
        Determines the new state when traversing a relationship.
    .DESCRIPTION
        Pure function that calculates state transitions based on direction,
        current state, and optional configuration overrides.
        
        This function implements the core state transition logic for graph traversal:
        - Outgoing FKs: Follow references (Include/Pending propagate, Exclude stops)
        - Incoming FKs: Find dependents (Include -> Pending in non-full search)
        - Configuration overrides can force specific states per table
    .PARAMETER Direction
        The traversal direction (Outgoing = following FKs, Incoming = finding dependents)
    .PARAMETER CurrentState
        The current state of the source record
    .PARAMETER Fk
        The foreign key relationship being traversed
    .PARAMETER TraversalConfiguration
        Optional configuration to override default state transitions
    .PARAMETER FullSearch
        If true, Include state propagates on incoming FKs (full graph traversal)
    .OUTPUTS
        TraversalState - The state to assign to records found via this relationship
    .EXAMPLE
        $newState = Get-NewTraversalState `
            -Direction ([TraversalDirection]::Outgoing) `
            -CurrentState ([TraversalState]::Include) `
            -Fk $foreignKey `
            -FullSearch $false
    #>
    [CmdletBinding()]
    [OutputType([TraversalState])]
    param
    (
        [Parameter(Mandatory = $true)]
        [TraversalDirection]$Direction,
        
        [Parameter(Mandatory = $true)]
        [TraversalState]$CurrentState,
        
        [Parameter(Mandatory = $true)]
        [TableFk]$Fk,
        
        [Parameter(Mandatory = $false)]
        [TraversalConfiguration]$TraversalConfiguration,
        
        [Parameter(Mandatory = $false)]
        [bool]$FullSearch = $false
    )

    try
    {
        # Validate inputs
        if ($null -eq $Fk)
        {
            throw [System.ArgumentNullException]::new("Fk", "Foreign key cannot be null")
        }
        
        $null = Assert-ValidTraversalState $CurrentState
        $null = Assert-ValidTraversalDirection $Direction
    }
    catch
    {
        Write-Error "Failed to validate inputs for Get-NewTraversalState: $_"
        throw
    }

    $newState = $CurrentState

    # Default state transitions
    if ($Direction -eq [TraversalDirection]::Outgoing)
    {
        # When traversing outgoing FKs (dependencies):
        # Include -> Include (include referenced data)
        # Exclude -> DO NOT TRAVERSE (exclusion is local, not propagated)
        # Pending -> Pending (propagate uncertainty to dependencies)
        if ($CurrentState -eq [TraversalState]::Include) {
            $newState = [TraversalState]::Include
        }
        elseif ($CurrentState -eq [TraversalState]::Pending) {
            $newState = [TraversalState]::Pending
        }
        else {
            # Exclude state: do not propagate
            $newState = [TraversalState]::Exclude
        }
    }
    elseif ($Direction -eq [TraversalDirection]::Incoming)
    {
        if ($CurrentState -eq [TraversalState]::Include)
        {
            if ($FullSearch) { 
                $newState = [TraversalState]::Include 
            } else { 
                $newState = [TraversalState]::Pending 
            }
        }
        # Pending and Exclude do not traverse incoming
    }

    Write-Verbose "Traversal configuration override check for FK: $($Fk.Name)"
    # Apply TraversalConfiguration overrides if specified
    if ($null -ne $TraversalConfiguration)
    {
        $targetSchema = if ($Direction -eq [TraversalDirection]::Outgoing) { $Fk.Schema } else { $Fk.FkSchema }
        $targetTable = if ($Direction -eq [TraversalDirection]::Outgoing) { $Fk.Table } else { $Fk.FkTable }
        
        $item = $TraversalConfiguration.GetItemForTable($targetSchema, $targetTable)
        Write-Verbose "Retrieved rule for $targetSchema.$targetTable: $($null -ne $item)"
        if ($null -ne $item -and $null -ne $item.StateOverride)
        {
            # Use the forced state from StateOverride
            $newState = $item.StateOverride.State
        }
    }
    return $newState
}

function Get-TraversalConstraints
{
    <#
    .SYNOPSIS
        Gets traversal constraints (MaxDepth, Top) from TraversalConfiguration.
    .DESCRIPTION
        Pure function that retrieves constraints for FK traversal.
        Returns a hashtable with MaxDepth and Top properties.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param
    (
        [Parameter(Mandatory = $true)]
        [TableFk]$Fk,
        
        [Parameter(Mandatory = $true)]
        [TraversalDirection]$Direction,
        
        [Parameter(Mandatory = $false)]
        [TraversalConfiguration]$TraversalConfiguration
    )

    $result = @{
        MaxDepth = $null
        Top      = $null
    }

    if ($null -ne $TraversalConfiguration)
    {
        # Lookup constraints for the TARGET table
        $targetSchema = if ($Direction -eq [TraversalDirection]::Outgoing) { $Fk.Schema } else { $Fk.FkSchema }
        $targetTable = if ($Direction -eq [TraversalDirection]::Outgoing) { $Fk.Table } else { $Fk.FkTable }
        
        $item = $TraversalConfiguration.GetItemForTable($targetSchema, $targetTable)
        
        if ($null -ne $item -and $null -ne $item.Constraints)
        {
            if ($item.Constraints.MaxDepth -ne -1)
            {
                $result.MaxDepth = $item.Constraints.MaxDepth
            }
            if ($item.Constraints.Top -ne -1)
            {
                $result.Top = $item.Constraints.Top
            }
        }
    }

    return $result
}

function Test-ShouldTraverseDirection
{
    <#
    .SYNOPSIS
        Determines if we should traverse in a given direction for a state.
    .DESCRIPTION
        Pure function that returns boolean indicating whether traversal
        should proceed based on state and direction.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param
    (
        [Parameter(Mandatory = $true)]
        [TraversalState]$State,
        
        [Parameter(Mandatory = $true)]
        [TraversalDirection]$Direction
    )

    if ($Direction -eq [TraversalDirection]::Outgoing)
    {
        # Traverse outgoing FKs for Include and Pending
        return ($State -eq [TraversalState]::Include) -or 
               ($State -eq [TraversalState]::Pending)
    }
    else # Incoming
    {
        # Traverse incoming FKs for Include and InboundOnly
        return ($State -eq [TraversalState]::Include) -or 
               ($State -eq [TraversalState]::InboundOnly)
    }
}

function Get-TopClause
{
    <#
    .SYNOPSIS
        Determines the TOP clause for a query based on global and local constraints.
    .DESCRIPTION
        Pure function that calculates TOP clause priority:
        1. MaxBatchSize (global limit) - overrides everything
        2. Constraints.Top (table-specific limit)
        3. No limit
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param
    (
        [Parameter(Mandatory = $true)]
        [int]$MaxBatchSize,
        
        [Parameter(Mandatory = $false)]
        [hashtable]$Constraints
    )

    if ($MaxBatchSize -ne -1)
    {
        return "TOP ($MaxBatchSize)"
    }
    elseif ($null -ne $Constraints -and $null -ne $Constraints.Top)
    {
        return "TOP ($($Constraints.Top))"
    }
    else
    {
        return ""
    }
}

function Get-ForeignKeyRelationships
{
    <#
    .SYNOPSIS
        Gets the appropriate FK relationships based on traversal direction.
    .DESCRIPTION
        Pure function that returns the correct FK collection for a table
        based on whether we're traversing outgoing or incoming relationships.
    #>
    [CmdletBinding()]
    [OutputType([object[]])]
    param
    (
        [Parameter(Mandatory = $true)]
        [TableInfo]$Table,
        
        [Parameter(Mandatory = $true)]
        [TraversalDirection]$Direction
    )

    if ($Direction -eq [TraversalDirection]::Outgoing)
    {
        return $Table.ForeignKeys
    }
    else
    {
        return $Table.IsReferencedBy
    }
}

function Get-TargetTableInfo
{
    <#
    .SYNOPSIS
        Extracts target table schema and name from FK based on direction.
    .DESCRIPTION
        Pure function that returns target table information based on
        traversal direction and FK structure.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param
    (
        [Parameter(Mandatory = $true)]
        [TableFk]$Fk,
        
        [Parameter(Mandatory = $true)]
        [TraversalDirection]$Direction
    )

    if ($Direction -eq [TraversalDirection]::Outgoing)
    {
        return @{
            Schema = $Fk.Schema
            Table  = $Fk.Table
        }
    }
    else
    {
        return @{
            Schema = $Fk.FkSchema
            Table  = $Fk.FkTable
        }
    }
}

function Test-ShouldSkipTable
{
    <#
    .SYNOPSIS
        Determines if a table should be skipped during traversal.
    .DESCRIPTION
        Pure function that checks if a table is in the ignored list
        or has no primary key.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param
    (
        [Parameter(Mandatory = $true)]
        [string]$Schema,
        
        [Parameter(Mandatory = $true)]
        [string]$Table,
        
        [Parameter(Mandatory = $false)]
        [TableInfo2[]]$IgnoredTables,
        
        [Parameter(Mandatory = $false)]
        [TableInfo]$TableInfo
    )

    # Check if in ignored list
    if ([TableInfo2]::IsIgnored($Schema, $Table, $IgnoredTables))
    {
        return $true
    }

    # Check if table info is missing or has no PK
    if ($null -eq $TableInfo -or $TableInfo.PrimaryKey.Count -eq 0)
    {
        return $true
    }

    return $false
}

function Get-JoinConditions
{
    <#
    .SYNOPSIS
        Builds JOIN conditions for FK traversal.
    .DESCRIPTION
        Pure function that generates SQL JOIN conditions based on
        direction and FK column mappings.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param
    (
        [Parameter(Mandatory = $true)]
        [TableFk]$Fk,
        
        [Parameter(Mandatory = $true)]
        [TraversalDirection]$Direction,
        
        [Parameter(Mandatory = $true)]
        [string]$SourceAlias = "src",
        
        [Parameter(Mandatory = $true)]
        [string]$TargetAlias = "tgt"
    )

    if ($Direction -eq [TraversalDirection]::Outgoing)
    {
        $joinConditions = for ($i = 0; $i -lt $Fk.FkColumns.Count; $i++) {
            "$SourceAlias.Key$i = $TargetAlias.$($Fk.FkColumns[$i].Name)"
        }
    }
    else # Incoming
    {
        $joinConditions = for ($i = 0; $i -lt $Fk.FkColumns.Count; $i++) {
            "$SourceAlias.Key$i = $TargetAlias.$($Fk.FkColumns[$i].Name)"
        }
    }

    return ($joinConditions -join " AND ")
}

function Get-AdditionalWhereConditions
{
    <#
    .SYNOPSIS
        Builds additional WHERE clause conditions for traversal queries.
    .DESCRIPTION
        Pure function that generates array of WHERE conditions based on
        constraints and search mode.
    #>
    [CmdletBinding()]
    [OutputType([string[]])]
    param
    (
        [Parameter(Mandatory = $false)]
        [hashtable]$Constraints,
        
        [Parameter(Mandatory = $true)]
        [int]$FkId,
        
        [Parameter(Mandatory = $true)]
        [bool]$FullSearch
    )

    $conditions = @()
    
    # MaxDepth constraint
    if ($null -ne $Constraints -and $null -ne $Constraints.MaxDepth)
    {
        $conditions += "src.Depth < $($Constraints.MaxDepth)"
    }

    # Prevent cycles in non-full search
    if (-not $FullSearch)
    {
        $conditions += "((src.Fk <> $FkId) OR (src.Fk IS NULL))"
    }

    return $conditions
}

Export-ModuleMember -Function @(
    'Get-NewTraversalState',
    'Get-TraversalConstraints',
    'Test-ShouldTraverseDirection',
    'Get-TopClause',
    'Get-ForeignKeyRelationships',
    'Get-TargetTableInfo',
    'Test-ShouldSkipTable',
    'Get-JoinConditions',
    'Get-AdditionalWhereConditions'
)
