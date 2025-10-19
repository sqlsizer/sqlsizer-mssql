# Enhanced types for the refactored Find-Subset algorithm

enum TraversalState
{
    # Record should be included in subset (was Color.Green)
    Include = 1
    
    # Record should be excluded from subset (was Color.Red)  
    Exclude = 2
    
    # Record needs evaluation - reachable but inclusion undecided (was Color.Yellow)
    Pending = 3
    
    # Only process incoming FKs (was Color.Blue)
    InboundOnly = 4
}

enum TraversalDirection
{
    Outgoing = 1  # Follow FKs from current table to referenced tables
    Incoming = 2  # Follow FKs from tables that reference current table
}

class TraversalOperation
{
    [int]$Id
    [int]$TableId
    [string]$TableSchema
    [string]$TableName
    [TraversalState]$State
    [int]$Depth
    [long]$RecordsToProcess
    [long]$RecordsProcessed
    [int]$Iteration
    [bool]$IsCompleted
    [int]$SourceTableId
    [int]$ForeignKeyId
    [DateTime]$CreatedDate
    [DateTime]$ProcessedDate
    
    [bool] IsFullyProcessed()
    {
        return $this.RecordsProcessed -ge $this.RecordsToProcess
    }
    
    [long] RemainingRecords()
    {
        return $this.RecordsToProcess - $this.RecordsProcessed
    }
}

class TraversalStatistics
{
    [long]$TotalOperations
    [long]$CompletedOperations
    [long]$TotalRecordsProcessed
    [long]$TotalRecordsRemaining
    [int]$CurrentIteration
    [int]$MaxDepthReached
    [TimeSpan]$ElapsedTime
    
    [double] PercentComplete()
    {
        $total = $this.TotalRecordsProcessed + $this.TotalRecordsRemaining
        if ($total -eq 0) { return 100.0 }
        return [Math]::Round(100.0 * $this.TotalRecordsProcessed / $total, 2)
    }
    
    [string] ToString()
    {
        return "Iteration $($this.CurrentIteration): $($this.PercentComplete())% complete ($($this.CompletedOperations)/$($this.TotalOperations) ops, depth $($this.MaxDepthReached))"
    }
}

#region TraversalStateMap - Pure Refactored Classes (No Color References)

<#
.SYNOPSIS
    Pure refactored configuration classes that use TraversalState exclusively.
.DESCRIPTION
    These classes are designed for the refactored algorithm and do NOT reference
    the legacy Color enum at all. They provide a clean interface using only
    TraversalState semantics.
#>

class TraversalStateMap
{
    <#
    .SYNOPSIS
        Configuration map for customizing traversal states and constraints.
    .DESCRIPTION
        Pure refactored replacement for ColorMap that uses TraversalState exclusively.
        No Color enum references at all - designed for the refactored algorithm.
    .EXAMPLE
        $stateMap = New-Object TraversalStateMap
        $item = New-Object TraversalStateItem
        $item.SchemaName = "Sales"
        $item.TableName = "Orders"
        $item.ForcedState = [TraversalState]::Include
        $item.Condition = New-Object StateCondition
        $item.Condition.MaxDepth = 3
        $stateMap.Items = @($item)
    #>
    [TraversalStateItem[]]$Items
    
    TraversalStateMap()
    {
        $this.Items = @()
    }
    
    [TraversalStateItem] GetItemForTable([string]$schema, [string]$table)
    {
        foreach ($item in $this.Items)
        {
            if ($item.SchemaName -eq $schema -and $item.TableName -eq $table)
            {
                return $item
            }
        }
        return $null
    }
}

class TraversalStateItem
{
    <#
    .SYNOPSIS
        Configuration item for a specific table's traversal behavior.
    .DESCRIPTION
        Specifies state overrides and constraints for a table.
        Pure refactored version with no Color enum references.
    #>
    [string]$SchemaName
    [string]$TableName
    [TraversalState]$ForcedState = [TraversalState]::Include
    [StateCondition]$Condition
    
    TraversalStateItem()
    {
        $this.SchemaName = ""
        $this.TableName = ""
        $this.Condition = $null
    }
    
    TraversalStateItem([string]$schema, [string]$table)
    {
        $this.SchemaName = $schema
        $this.TableName = $table
        $this.Condition = $null
    }
    
    TraversalStateItem([string]$schema, [string]$table, [TraversalState]$state)
    {
        $this.SchemaName = $schema
        $this.TableName = $table
        $this.ForcedState = $state
        $this.Condition = $null
    }
}

class StateCondition
{
    <#
    .SYNOPSIS
        Traversal constraints for depth and record limits.
    .DESCRIPTION
        Pure refactored version of Condition that works with TraversalStateMap.
    #>
    [int]$Top = -1                      # Max records to process (-1 = unlimited)
    [string]$SourceSchemaName = ""      # Filter by source table schema
    [string]$SourceTableName = ""       # Filter by source table name
    [int]$MaxDepth = -1                 # Max traversal depth from this table (-1 = unlimited)
    [string]$FkName = ""                # Filter by specific FK name
    
    StateCondition()
    {
    }
    
    StateCondition([int]$maxDepth)
    {
        $this.MaxDepth = $maxDepth
    }
    
    StateCondition([int]$maxDepth, [int]$top)
    {
        $this.MaxDepth = $maxDepth
        $this.Top = $top
    }
    
    [bool] HasTopLimit()
    {
        return $this.Top -ne -1
    }
    
    [bool] HasDepthLimit()
    {
        return $this.MaxDepth -ne -1
    }
}

#endregion

#region Modern Traversal Configuration Classes

<#
.SYNOPSIS
    Modern replacement for ColorMap with clear, descriptive names.
.DESCRIPTION
    TraversalConfiguration replaces the legacy ColorMap class with better semantics:
    - ColorMap -> TraversalConfiguration
    - ColorItem -> TraversalRule
    - ForcedColor -> StateOverride
    - Condition -> TraversalConstraints
    
    Provides both modern classes and backwards compatibility with ColorMap.
#>

class TraversalConfiguration
{
    <#
    .SYNOPSIS
        Configuration for customizing graph traversal behavior.
    .DESCRIPTION
        Allows overriding traversal states and constraints per table or FK.
        Replaces the legacy ColorMap class with clearer naming.
    .EXAMPLE
        $config = New-Object TraversalConfiguration
        $rule = New-Object TraversalRule
        $rule.SchemaName = "Sales"
        $rule.TableName = "Orders"
        $rule.StateOverride = New-Object StateOverride
        $rule.StateOverride.State = [TraversalState]::Include
        $rule.Constraints = New-Object TraversalConstraints
        $rule.Constraints.MaxDepth = 3
        $config.Rules = @($rule)
    #>
    [TraversalRule[]]$Rules
    
    TraversalConfiguration()
    {
        $this.Rules = @()
    }
    
    [TraversalRule] GetItemForTable([string]$schema, [string]$table)
    {
        foreach ($rule in $this.Rules)
        {
            if ($rule.SchemaName -eq $schema -and $rule.TableName -eq $table)
            {
                return $rule
            }
        }
        return $null
    }
}

class TraversalRule
{
    <#
    .SYNOPSIS
        Rule defining traversal behavior for a specific table.
    .DESCRIPTION
        Specifies state overrides and constraints for a particular table.
        Replaces the legacy ColorItem class.
        
        Provides both modern property names (StateOverride, Constraints) and
        convenience properties (ForcedState, Condition) for refactored code.
    #>
    [string]$SchemaName
    [string]$TableName
    [StateOverride]$StateOverride
    [TraversalConstraints]$Constraints
    
    # Convenience properties for backward compatibility
    hidden [TraversalState]$_forcedState = [TraversalState]::Include
    hidden [TraversalConstraints]$_condition = $null
    
    TraversalRule()
    {
        $this.SchemaName = ""
        $this.TableName = ""
        $this.StateOverride = $null
        $this.Constraints = $null
    }
    
    TraversalRule([string]$schema, [string]$table)
    {
        $this.SchemaName = $schema
        $this.TableName = $table
        $this.StateOverride = $null
        $this.Constraints = $null
    }
    
    # Convenience property: ForcedState (returns StateOverride.State or default)
    [TraversalState] GetForcedState()
    {
        if ($null -ne $this.StateOverride)
        {
            return $this.StateOverride.State
        }
        return [TraversalState]::Include
    }
    
    # Convenience property: Condition (alias for Constraints)
    [TraversalConstraints] GetCondition()
    {
        return $this.Constraints
    }
}

class StateOverride
{
    <#
    .SYNOPSIS
        Specifies a forced traversal state for a table.
    .DESCRIPTION
        Overrides the default state transition logic for a specific table.
        Replaces the legacy ForcedColor class.
    #>
    [TraversalState]$State
    
    StateOverride()
    {
    }
    
    StateOverride([TraversalState]$state)
    {
        $this.State = $state
    }
}

class TraversalConstraints
{
    <#
    .SYNOPSIS
        Constraints limiting traversal depth or record count.
    .DESCRIPTION
        Defines limits on how far to traverse from a table or how many records to process.
        Replaces the legacy Condition class with a clearer name.
    #>
    [int]$Top = -1                      # Max records to process (-1 = unlimited)
    [string]$SourceSchemaName = ""      # Filter by source table schema
    [string]$SourceTableName = ""       # Filter by source table name
    [int]$MaxDepth = -1                 # Max traversal depth from this table (-1 = unlimited)
    [string]$ForeignKeyName = ""        # Filter by specific FK name
    
    TraversalConstraints()
    {
    }
    
    [bool] HasTopLimit()
    {
        return $this.Top -ne -1
    }
    
    [bool] HasDepthLimit()
    {
        return $this.MaxDepth -ne -1
    }
    
    [bool] HasSourceFilter()
    {
        return $this.SourceSchemaName -ne "" -and $this.SourceTableName -ne ""
    }
    
    [bool] HasForeignKeyFilter()
    {
        return $this.ForeignKeyName -ne ""
    }
}

#endregion