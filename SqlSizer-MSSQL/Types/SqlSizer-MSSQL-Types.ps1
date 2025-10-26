enum Color
{
    Red = 1
    Green = 2
    Yellow = 3
    Blue = 4
    Purple = 5
}

enum ForeignKeyRule
{
    NoAction = 1
    Cascade = 2
    SetNull = 3
    SetDefault = 4
}
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

class ColorMap
{
    [ColorItem[]]$Items
}

class ColorItem
{
    [string]$SchemaName
    [string]$TableName
    [ForcedColor]$ForcedColor
    [Condition]$Condition
}

class ForcedColor
{
    [Color]$Color
}

class Condition
{
    [int]$Top = -1
    [string]$SourceSchemaName = ""
    [string]$SourceTableName = ""
    [int]$MaxDepth = -1
    [string]$FkName = ""
}

class Query
{
    [Color]$Color
    [string]$Schema
    [string]$Table
    [string[]]$KeyColumns
    [string]$Where
    [int]$Top
    [string]$OrderBy
}

class Query2
{
    [TraversalState]$State
    [string]$Schema
    [string]$Table
    [string[]]$KeyColumns
    [string]$Where
    [int]$Top
    [string]$OrderBy
}

class DatabaseInfo
{
    [System.Collections.Generic.List[string]]$Schemas
    [System.Collections.Generic.List[TableInfo]]$Tables
    [System.Collections.Generic.List[ViewInfo]]$Views
    [System.Collections.Generic.List[StoredProcedureInfo]]$StoredProcedures
    
    [int]$PrimaryKeyMaxSize
    [string]$DatabaseSize
}

class StoredProcedureInfo
{
    [string]$Schema
    [string]$Name
    [string]$Definition
}

class TableInfo2
{
    [string]$SchemaName
    [string]$TableName

    static [bool] IsIgnored([string] $schemaName, [string] $tableName, [TableInfo2[]] $ignoredTables)
    {
        $result = $false

        foreach ($ignoredTable in $ignoredTables)
        {
            if (($ignoredTable.SchemaName -eq $schemaName) -and ($ignoredTable.TableName -eq $tableName))
            {
                $result = $true
                break
            }
        }

        return $result
    }

    [string] ToString()
    {
        return "$($this.SchemaName).$($this.TableName)"
    }
}

class TableInfo2WithColor
{
    [string]$SchemaName
    [string]$TableName
    [Color]$Color
}

class SubsettingTableResult
{
    [string]$SchemaName
    [string]$TableName
    [bool]$CanBeDeleted
    [long]$RowCount
    [int]$PrimaryKeySize
}

class SubsettingProcess
{
    [long]$ToProcess
    [long]$Processed
}

class TableStatistics
{
    [long]$Rows
    [long]$ReservedKB
    [long]$DataKB
    [long]$IndexSize
    [long]$UnusedKB

    [string] ToString()
    {
        return "$($this.Rows) rows  => [$($this.DataKB) used of $($this.ReservedKB) reserved KB, $($this.IndexSize) index KB]"
    }
}

class DatabaseStructureInfo
{
    [TableStructureInfo[]]$Tables
    [TableFk[]]$Fks
}

class TableStructureInfo
{
    [string]$SchemaName
    [string]$TableName
    [ColumnInfo[]]$PrimaryKey
}

class ViewInfo
{
    [string]$SchemaName
    [string]$ViewName
    [string]$Definition
}

class TableInfo
{
    [int]$Id
    [string]$SchemaName
    [string]$TableName
    [bool]$IsIdentity
    [bool]$IsHistoric
    [bool]$HasHistory
    [string]$HistoryOwner
    [string]$HistoryOwnerSchema

    [System.Collections.Generic.List[ColumnInfo]]$PrimaryKey
    [System.Collections.Generic.List[ColumnInfo]]$Columns

    [System.Collections.Generic.List[Tablefk]]$ForeignKeys
    [System.Collections.Generic.List[TableInfo]]$IsReferencedBy

    [System.Collections.Generic.List[ViewInfo]]$Views

    [System.Collections.Generic.List[string]]$Triggers

    [TableStatistics]$Statistics

    [System.Collections.Generic.List[TableIndex]]$Indexes

    [string] ToString()
    {
        return "$($this.SchemaName).$($this.TableName)"
    }
}

class TableIndex
{
    [string]$Name
    [System.Collections.Generic.List[string]]$Columns
}

class ColumnInfo
{
    [string]$Name
    [string]$DataType
    [string]$Length
    [bool]$IsNullable
    [bool]$IsComputed
    [bool]$IsGenerated
    [string]$ComputedDefinition
    [bool]$IsPresent
    [string] ToString()
    {
        return $this.Name;
    }
}

class TableFk
{
    [string]$Name
    [string]$FkSchema
    [string]$FkTable

    [string]$Schema
    [string]$Table

    [ForeignKeyRule]$DeleteRule
    [ForeignKeyRule]$UpdateRule

    [System.Collections.Generic.List[ColumnInfo]]$FkColumns
    [System.Collections.Generic.List[ColumnInfo]]$Columns
}

class SqlConnectionStatistics
{
    [long]$LogicalReads
}

class SqlConnectionInfo
{
    [string]$Server
    [System.Management.Automation.PSCredential]$Credential
    [string]$AccessToken = $null
    [bool]$EncryptConnection = $false
    [SqlConnectionStatistics]$Statistics
    [bool]$IsSynapse = $false
}

class TableFile
{
    [string]$FileId
    [SubsettingTableResult]$TableContent
}

class Structure
{
    [DatabaseInfo] $DatabaseInfo
    [System.Collections.Generic.Dictionary[String, ColumnInfo[]]] $Signatures
    [System.Collections.Generic.Dictionary[TableInfo, String]] $Tables

    Structure(
        [DatabaseInfo]$DatabaseInfo
    )
    {
        $this.DatabaseInfo = $DatabaseInfo
        $this.Signatures = New-Object "System.Collections.Generic.Dictionary[[string], ColumnInfo[]]"
        $this.Tables = New-Object "System.Collections.Generic.Dictionary[[TableInfo], [string]]"

        foreach ($table in $this.DatabaseInfo.Tables)
        {
            if ($table.PrimaryKey.Count -eq 0)
            {
                continue
            }

            if ($table.SchemaName.StartsWith("SqlSizer"))
            {
                continue
            }

            $signature = $this.GetTablePrimaryKeySignature($table)
            $this.Tables[$table] = $signature

            if ($this.Signatures.ContainsKey($signature) -eq $false)
            {
                $null = $this.Signatures.Add($signature, $table.PrimaryKey)
            }
        }
    }

    [string] GetProcessingName([string] $Signature, [string] $SessionId)
    {
        return "SqlSizer_$SessionId." + $Signature
    }

    [string] GetSliceName([string] $Signature, [string] $SessionId)
    {
        return "SqlSizer_$SessionId.Slice" + $Signature
    }

    [string] GetTablePrimaryKeySignature([TableInfo]$Table)
    {
        $result = $Table.SchemaName + "_" + $Table.TableName
        return $result
    }
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

