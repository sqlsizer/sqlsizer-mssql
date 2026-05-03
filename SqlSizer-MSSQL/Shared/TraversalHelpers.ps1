<#
.SYNOPSIS
    Helper functions for graph traversal operations in Find-Subset.
    
.DESCRIPTION
    This module contains pure, testable helper functions extracted from Find-Subset.
    These functions handle state transitions, constraints, and traversal logic.
#>

function Get-DefaultTraversalState
{
    [CmdletBinding()]
    [OutputType([TraversalState])]
    param
    (
        [Parameter(Mandatory = $true)]
        [TraversalDirection]$Direction,

        [Parameter(Mandatory = $true)]
        [TraversalState]$CurrentState,

        [Parameter(Mandatory = $false)]
        [bool]$FullSearch = $false
    )

    if ($Direction -eq [TraversalDirection]::Outgoing)
    {
        if ($CurrentState -eq [TraversalState]::Include)
        {
            return [TraversalState]::Include
        }
        elseif ($CurrentState -eq [TraversalState]::IncludeFull)
        {
            return [TraversalState]::Include
        }
        elseif ($CurrentState -eq [TraversalState]::Pending)
        {
            return [TraversalState]::Pending
        }
        else
        {
            return [TraversalState]::Exclude
        }
    }

    if ($CurrentState -eq [TraversalState]::Include)
    {
        if ($FullSearch)
        {
            return [TraversalState]::Include
        }
        return [TraversalState]::Exclude
    }
    elseif ($CurrentState -eq [TraversalState]::IncludeFull)
    {
        return [TraversalState]::Include
    }
    elseif ($CurrentState -eq [TraversalState]::InboundOnly)
    {
        return [TraversalState]::InboundOnly
    }

    return [TraversalState]::Exclude
}

function New-TraversalConstraintsResult
{
    [CmdletBinding()]
    [OutputType([hashtable])]
    param
    (
        [Parameter(Mandatory = $false)]
        [TraversalRule]$Rule,

        [Parameter(Mandatory = $false)]
        [string[]]$PriorFilters = @()
    )

    $result = @{
        MaxDepth         = $null
        Top              = $null
        SourceSchemaName = $null
        SourceTableName  = $null
        ForeignKeyName   = $null
        Filter           = $null
        PriorFilters     = @($PriorFilters)
    }

    if ($null -eq $Rule)
    {
        return $result
    }

    if ($null -ne $Rule.Constraints)
    {
        if ($Rule.Constraints.MaxDepth -ne -1)
        {
            $result.MaxDepth = $Rule.Constraints.MaxDepth
        }
        if ($Rule.Constraints.Top -ne -1)
        {
            $result.Top = $Rule.Constraints.Top
        }
        if ($Rule.Constraints.SourceSchemaName -ne "")
        {
            $result.SourceSchemaName = $Rule.Constraints.SourceSchemaName
        }
        if ($Rule.Constraints.SourceTableName -ne "")
        {
            $result.SourceTableName = $Rule.Constraints.SourceTableName
        }
        if ($Rule.Constraints.ForeignKeyName -ne "")
        {
            $result.ForeignKeyName = $Rule.Constraints.ForeignKeyName
        }
    }

    if (-not [string]::IsNullOrWhiteSpace($Rule.Filter))
    {
        $result.Filter = $Rule.Filter
    }

    return $result
}

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
        - Incoming FKs: Find dependents only for full-closure/removal policies
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

    $newState = Get-DefaultTraversalState -Direction $Direction -CurrentState $CurrentState -FullSearch $FullSearch

    Write-Verbose "Traversal configuration override check for FK: $($Fk.Name)"
    # Apply TraversalConfiguration overrides if specified
    if ($null -ne $TraversalConfiguration)
    {
        $targetSchema = if ($Direction -eq [TraversalDirection]::Outgoing) { $Fk.Schema } else { $Fk.FkSchema }
        $targetTable = if ($Direction -eq [TraversalDirection]::Outgoing) { $Fk.Table } else { $Fk.FkTable }
        
        $item = $TraversalConfiguration.GetItemForTable($targetSchema, $targetTable)
        Write-Verbose "Retrieved rule for $targetSchema . $targetTable : $($null -ne $item)"
        if ($null -ne $item -and $null -ne $item.StateOverride)
        {
            # Use the forced state from StateOverride
            $newState = $item.StateOverride.State
        }
    }
    return $newState
}

function Get-TraversalRuleBranches
{
    <#
    .SYNOPSIS
        Builds ordered traversal rule branches for a target table relationship.
    .DESCRIPTION
        Rules are evaluated in TraversalConfiguration order. Each branch carries
        row-level filter predicates plus the prior predicates that must not match
        to preserve first-match semantics.
    #>
    [CmdletBinding()]
    [OutputType([hashtable[]])]
    param
    (
        [Parameter(Mandatory = $true)]
        [TraversalDirection]$Direction,

        [Parameter(Mandatory = $true)]
        [TraversalState]$CurrentState,

        [Parameter(Mandatory = $true)]
        [TableFk]$Fk,

        [Parameter(Mandatory = $true)]
        [string]$SourceSchemaName,

        [Parameter(Mandatory = $true)]
        [string]$SourceTableName,

        [Parameter(Mandatory = $true)]
        [string]$ForeignKeyName,

        [Parameter(Mandatory = $false)]
        [TraversalConfiguration]$TraversalConfiguration,

        [Parameter(Mandatory = $false)]
        [bool]$FullSearch = $false
    )

    $defaultState = Get-DefaultTraversalState -Direction $Direction -CurrentState $CurrentState -FullSearch $FullSearch
    $branches = [System.Collections.Generic.List[hashtable]]::new()

    if ($null -eq $TraversalConfiguration)
    {
        $branches.Add(@{
            NewState    = $defaultState
            Constraints = (New-TraversalConstraintsResult)
            Rule        = $null
        })
        return ,$branches.ToArray()
    }

    $target = Get-TargetTableInfo -Fk $Fk -Direction $Direction
    $rules = @($TraversalConfiguration.GetItemsForTable($target.Schema, $target.Table))
    if ($rules.Count -eq 0)
    {
        $branches.Add(@{
            NewState    = $defaultState
            Constraints = (New-TraversalConstraintsResult)
            Rule        = $null
        })
        return ,$branches.ToArray()
    }

    $priorFilters = [System.Collections.Generic.List[string]]::new()
    $hasFallbackRule = $false
    $matchedAnyRule = $false

    foreach ($rule in $rules)
    {
        $constraints = New-TraversalConstraintsResult -Rule $rule -PriorFilters @($priorFilters.ToArray())
        if (-not (Test-TraversalConstraintsMatch `
                    -Constraints $constraints `
                    -SourceSchemaName $SourceSchemaName `
                    -SourceTableName $SourceTableName `
                    -ForeignKeyName $ForeignKeyName))
        {
            continue
        }

        $matchedAnyRule = $true
        $newState = $defaultState
        if ($null -ne $rule.StateOverride)
        {
            $newState = $rule.StateOverride.State
        }

        $branches.Add(@{
            NewState    = $newState
            Constraints = $constraints
            Rule        = $rule
        })

        if ([string]::IsNullOrWhiteSpace($rule.Filter))
        {
            $hasFallbackRule = $true
            break
        }

        $priorFilters.Add($rule.Filter)
    }

    if ($matchedAnyRule -and -not $hasFallbackRule)
    {
        $branches.Add(@{
            NewState    = $defaultState
            Constraints = (New-TraversalConstraintsResult -PriorFilters @($priorFilters.ToArray()))
            Rule        = $null
        })
    }

    return ,$branches.ToArray()
}

function Get-TraversalConstraints
{
    <#
    .SYNOPSIS
        Gets traversal constraints from TraversalConfiguration.
    .DESCRIPTION
        Pure function that retrieves constraints for FK traversal.
        Returns a hashtable with MaxDepth, Top, relationship filters, and row filters.
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

    $result = New-TraversalConstraintsResult

    if ($null -ne $TraversalConfiguration)
    {
        # Lookup constraints for the TARGET table
        $targetSchema = if ($Direction -eq [TraversalDirection]::Outgoing) { $Fk.Schema } else { $Fk.FkSchema }
        $targetTable = if ($Direction -eq [TraversalDirection]::Outgoing) { $Fk.Table } else { $Fk.FkTable }
        
        $item = $TraversalConfiguration.GetItemForTable($targetSchema, $targetTable)
        
        if ($null -ne $item -and $null -ne $item.Constraints)
        {
            $result = New-TraversalConstraintsResult -Rule $item
        }
        elseif ($null -ne $item)
        {
            $result = New-TraversalConstraintsResult -Rule $item
        }
    }

    return $result
}

function Test-TraversalConstraintsMatch
{
    <#
    .SYNOPSIS
        Determines whether a relationship satisfies source and FK filters.
    .DESCRIPTION
        Source table and FK-name constraints are applied before SQL generation
        so skipped relationships do not produce empty traversal batches.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param
    (
        [Parameter(Mandatory = $false)]
        [hashtable]$Constraints,

        [Parameter(Mandatory = $true)]
        [string]$SourceSchemaName,

        [Parameter(Mandatory = $true)]
        [string]$SourceTableName,

        [Parameter(Mandatory = $true)]
        [string]$ForeignKeyName
    )

    if ($null -eq $Constraints)
    {
        return $true
    }

    if (($null -ne $Constraints.SourceSchemaName) -and ($Constraints.SourceSchemaName -ne "") -and ($Constraints.SourceSchemaName -ne $SourceSchemaName))
    {
        return $false
    }

    if (($null -ne $Constraints.SourceTableName) -and ($Constraints.SourceTableName -ne "") -and ($Constraints.SourceTableName -ne $SourceTableName))
    {
        return $false
    }

    if (($null -ne $Constraints.ForeignKeyName) -and ($Constraints.ForeignKeyName -ne "") -and ($Constraints.ForeignKeyName -ne $ForeignKeyName))
    {
        return $false
    }

    return $true
}

function Test-ShouldTraverseDirection
{
    <#
    .SYNOPSIS
        Determines if we should traverse in a given direction for a state.
    .DESCRIPTION
        Pure function that returns boolean indicating whether traversal
        should proceed based on state, direction, and FullSearch mode.
        
        When FullSearch=false, incoming FK traversal is disabled for Include state.
        This prevents including rows that reference the subset but aren't required
        for referential integrity.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param
    (
        [Parameter(Mandatory = $true)]
        [TraversalState]$State,
        
        [Parameter(Mandatory = $true)]
        [TraversalDirection]$Direction,
        
        [Parameter(Mandatory = $false)]
        [bool]$FullSearch = $false
    )

    if ($Direction -eq [TraversalDirection]::Outgoing)
    {
        # Traverse outgoing FKs for Include, IncludeFull, and Pending
        return ($State -eq [TraversalState]::Include) -or 
               ($State -eq [TraversalState]::IncludeFull) -or
               ($State -eq [TraversalState]::Pending)
    }
    else # Incoming
    {
        # Traverse incoming FKs for Include (only when FullSearch=true), IncludeFull (always), and InboundOnly
        if ($State -eq [TraversalState]::Include)
        {
            return $FullSearch
        }
        if ($State -eq [TraversalState]::IncludeFull)
        {
            return $true
        }
        return ($State -eq [TraversalState]::InboundOnly)
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

function Assert-ValidTraversalRuleFilter
{
    [CmdletBinding()]
    param
    (
        [Parameter(Mandatory = $false)]
        [string]$Filter
    )

    if ([string]::IsNullOrWhiteSpace($Filter))
    {
        return
    }

    if ($Filter -match '[;]|--(?!\s*\[)|\bDROP\b|\bDELETE\b|\bEXEC\b|\bUPDATE\b')
    {
        throw "TraversalRule Filter contains potentially dangerous SQL: $Filter"
    }
}

function ConvertTo-TraversalRuleFilterSql
{
    [CmdletBinding()]
    [OutputType([string])]
    param
    (
        [Parameter(Mandatory = $true)]
        [string]$Filter,

        [Parameter(Mandatory = $false)]
        [string]$TargetAlias = 'tgt'
    )

    Assert-ValidTraversalRuleFilter -Filter $Filter
    return ($Filter.Trim() -replace '\[\$table\]', $TargetAlias)
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
        [long]$FkId,
        
        [Parameter(Mandatory = $true)]
        [bool]$FullSearch
    )

    $conditions = @()
    
    # MaxDepth constraint
    if ($null -ne $Constraints -and $null -ne $Constraints.MaxDepth)
    {
        $conditions += "src.Depth < $($Constraints.MaxDepth)"
    }

    if ($null -ne $Constraints)
    {
        foreach ($priorFilter in @($Constraints.PriorFilters))
        {
            if ([string]::IsNullOrWhiteSpace($priorFilter))
            {
                continue
            }

            $priorFilterSql = ConvertTo-TraversalRuleFilterSql -Filter $priorFilter -TargetAlias 'tgt'
            $conditions += "NOT EXISTS (SELECT 1 WHERE $priorFilterSql)"
        }

        if (-not [string]::IsNullOrWhiteSpace($Constraints.Filter))
        {
            $filterSql = ConvertTo-TraversalRuleFilterSql -Filter $Constraints.Filter -TargetAlias 'tgt'
            $conditions += "($filterSql)"
        }
    }

    return ,$conditions
}

function Get-IncludedTraversalStateValues
{
    <#
    .SYNOPSIS
        Returns the traversal states that represent rows belonging to an output closure.
    .DESCRIPTION
        Discovery/bookkeeping states should not leak into subset outputs. Include and
        IncludeFull belong to normal subset closures; InboundOnly belongs to removal
        closures. Pending and Exclude are intentionally omitted.
    #>
    [CmdletBinding()]
    [OutputType([int[]])]
    param ()

    return @(
        [int][TraversalState]::Include,
        [int][TraversalState]::InboundOnly,
        [int][TraversalState]::IncludeFull
    )
}

function Get-IncludedTraversalStateSqlList
{
    <#
    .SYNOPSIS
        Returns a SQL-ready list of output traversal state values.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param ()

    return [string]::Join(', ', (Get-IncludedTraversalStateValues))
}

Export-ModuleMember -Function @(
    'Get-DefaultTraversalState',
    'Get-TraversalRuleBranches',
    'Get-NewTraversalState',
    'Get-TraversalConstraints',
    'Test-TraversalConstraintsMatch',
    'Test-ShouldTraverseDirection',
    'Get-TopClause',
    'Get-ForeignKeyRelationships',
    'Get-TargetTableInfo',
    'Test-ShouldSkipTable',
    'Get-JoinConditions',
    'Assert-ValidTraversalRuleFilter',
    'ConvertTo-TraversalRuleFilterSql',
    'Get-AdditionalWhereConditions',
    'Get-IncludedTraversalStateValues',
    'Get-IncludedTraversalStateSqlList'
)
