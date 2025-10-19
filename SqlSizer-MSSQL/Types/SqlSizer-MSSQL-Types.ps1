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

# SIG # Begin signature block
# MIIoigYJKoZIhvcNAQcCoIIoezCCKHcCAQExDzANBglghkgBZQMEAgEFADB5Bgor
# BgEEAYI3AgEEoGswaTA0BgorBgEEAYI3AgEeMCYCAwEAAAQQH8w7YFlLCE63JNLG
# KX7zUQIBAAIBAAIBAAIBAAIBADAxMA0GCWCGSAFlAwQCAQUABCDXLIWS10LvEb1T
# 0p58JGEMaW0hYjtbL53BTaD9F5CAQqCCIL4wggXJMIIEsaADAgECAhAbtY8lKt8j
# AEkoya49fu0nMA0GCSqGSIb3DQEBDAUAMH4xCzAJBgNVBAYTAlBMMSIwIAYDVQQK
# ExlVbml6ZXRvIFRlY2hub2xvZ2llcyBTLkEuMScwJQYDVQQLEx5DZXJ0dW0gQ2Vy
# dGlmaWNhdGlvbiBBdXRob3JpdHkxIjAgBgNVBAMTGUNlcnR1bSBUcnVzdGVkIE5l
# dHdvcmsgQ0EwHhcNMjEwNTMxMDY0MzA2WhcNMjkwOTE3MDY0MzA2WjCBgDELMAkG
# A1UEBhMCUEwxIjAgBgNVBAoTGVVuaXpldG8gVGVjaG5vbG9naWVzIFMuQS4xJzAl
# BgNVBAsTHkNlcnR1bSBDZXJ0aWZpY2F0aW9uIEF1dGhvcml0eTEkMCIGA1UEAxMb
# Q2VydHVtIFRydXN0ZWQgTmV0d29yayBDQSAyMIICIjANBgkqhkiG9w0BAQEFAAOC
# Ag8AMIICCgKCAgEAvfl4+ObVgAxknYYblmRnPyI6HnUBfe/7XGeMycxca6mR5rlC
# 5SBLm9qbe7mZXdmbgEvXhEArJ9PoujC7Pgkap0mV7ytAJMKXx6fumyXvqAoAl4Va
# qp3cKcniNQfrcE1K1sGzVrihQTib0fsxf4/gX+GxPw+OFklg1waNGPmqJhCrKtPQ
# 0WeNG0a+RzDVLnLRxWPa52N5RH5LYySJhi40PylMUosqp8DikSiJucBb+R3Z5yet
# /5oCl8HGUJKbAiy9qbk0WQq/hEr/3/6zn+vZnuCYI+yma3cWKtvMrTscpIfcRnNe
# GWJoRVfkkIJCu0LW8GHgwaM9ZqNd9BjuiMmNF0UpmTJ1AjHuKSbIawLmtWJFfzcV
# WiNoidQ+3k4nsPBADLxNF8tNorMe0AZa3faTz1d1mfX6hhpneLO/lv403L3nUlbl
# s+V1e9dBkQXcXWnjlQ1DufyDljmVe2yAWk8TcsbXfSl6RLpSpCrVQUYJIP4ioLZb
# MI28iQzV13D4h1L92u+sUS4Hs07+0AnacO+Y+lbmbdu1V0vc5SwlFcieLnhO+Nqc
# noYsylfzGuXIkosagpZ6w7xQEmnYDlpGizrrJvojybawgb5CAKT41v4wLsfSRvbl
# jnX98sy50IdbzAYQYLuDNbdeZ95H7JlI8aShFf6tjGKOOVVPORa5sWOd/7cCAwEA
# AaOCAT4wggE6MA8GA1UdEwEB/wQFMAMBAf8wHQYDVR0OBBYEFLahVDkCw6A/joq8
# +tT4HKbROg79MB8GA1UdIwQYMBaAFAh2zcsH/yT2xc3tu5C84oQ3RnX3MA4GA1Ud
# DwEB/wQEAwIBBjAvBgNVHR8EKDAmMCSgIqAghh5odHRwOi8vY3JsLmNlcnR1bS5w
# bC9jdG5jYS5jcmwwawYIKwYBBQUHAQEEXzBdMCgGCCsGAQUFBzABhhxodHRwOi8v
# c3ViY2Eub2NzcC1jZXJ0dW0uY29tMDEGCCsGAQUFBzAChiVodHRwOi8vcmVwb3Np
# dG9yeS5jZXJ0dW0ucGwvY3RuY2EuY2VyMDkGA1UdIAQyMDAwLgYEVR0gADAmMCQG
# CCsGAQUFBwIBFhhodHRwOi8vd3d3LmNlcnR1bS5wbC9DUFMwDQYJKoZIhvcNAQEM
# BQADggEBAFHCoVgWIhCL/IYx1MIy01z4S6Ivaj5N+KsIHu3V6PrnCA3st8YeDrJ1
# BXqxC/rXdGoABh+kzqrya33YEcARCNQOTWHFOqj6seHjmOriY/1B9ZN9DbxdkjuR
# mmW60F9MvkyNaAMQFtXx0ASKhTP5N+dbLiZpQjy6zbzUeulNndrnQ/tjUoCFBMQl
# lVXwfqefAcVbKPjgzoZwpic7Ofs4LphTZSJ1Ldf23SIikZbr3WjtP6MZl9M7JYjs
# NhI9qX7OAo0FmpKnJ25FspxihjcNpDOO16hO0EoXQ0zF8ads0h5YbBRRfopUofbv
# n3l6XYGaFpAP4bvxSgD5+d2+7arszgowggaUMIIEfKADAgECAhAr1K5wudBjWyrp
# hMjWdKowMA0GCSqGSIb3DQEBDAUAMFYxCzAJBgNVBAYTAlBMMSEwHwYDVQQKExhB
# c3NlY28gRGF0YSBTeXN0ZW1zIFMuQS4xJDAiBgNVBAMTG0NlcnR1bSBUaW1lc3Rh
# bXBpbmcgMjAyMSBDQTAeFw0yMjA3MjgwODU2MjZaFw0zMzA3MjcwODU2MjZaMFAx
# CzAJBgNVBAYTAlBMMSEwHwYDVQQKDBhBc3NlY28gRGF0YSBTeXN0ZW1zIFMuQS4x
# HjAcBgNVBAMMFUNlcnR1bSBUaW1lc3RhbXAgMjAyMjCCAiIwDQYJKoZIhvcNAQEB
# BQADggIPADCCAgoCggIBAMrFXu0fCUbwRMtqXliGb6KwhLCeP4vySHEqQBI78xFc
# jqQae26x7v21UvkWS+X0oTh61yTcdoZaQAg5hNcBqWbGn7b8OOEXkGwUvGZ65MWK
# l2lXBjisc6d1GWVI5fXkP9+ddLVX4G/pP7eIdAtI5Fh4rGC/x9/vNan9C8C4I56N
# 525HwiKzqPSz6Z5N2XYM0+bT4VdYsZxyPRwLkjhcqdzg2tCB2+YP6ld+uBOkcfCr
# hFCeeTB4Y/ZalrZXaCGFIlBWjIyXb9UGspAaoDvP2LCSSRcnvrP49qIIGD7TqHbD
# oYumubWDgx8/YE7M5Bfd7F14mQOqnr7ImCFS5Ty/nfSO7XVSQ6TrlIYX8rLA4BSj
# nOu0WoYZTLOWyaekWPraAAhvzJQ3mXt6ruGa6VEljyzDTUfgEmSDpnxP6OFSOOc4
# xBOXbkV8OO4ivGf0pIff+IOsysOwvuSSHfF1FxSerNZb3VcUneyQaT+omC+kaGTP
# pvsyly53V/MUKuHVhgRIrGiWIJgN9Tr73oZXHk6mbuzkXiHhao/1AQrQ35q+mtGK
# vnXtf62dsJFztYf/XceELTw/KJd1YL7hlQ9zGR/fFE+fx9pvLd2yZ3Y1PCtpaNzq
# 6i7JZ2mRldC1XwikBtjoQ6GT2T3kyRn0lAU8Y4/TdN/4pptwouFk+75JsdToPQ6B
# AgMBAAGjggFiMIIBXjAMBgNVHRMBAf8EAjAAMB0GA1UdDgQWBBQjwTzMUzMZVo7Y
# 4/POPPyoc0dW6jAfBgNVHSMEGDAWgBS+VAIvv0Bsc0POrAklTp5DRBru4DAOBgNV
# HQ8BAf8EBAMCB4AwFgYDVR0lAQH/BAwwCgYIKwYBBQUHAwgwMwYDVR0fBCwwKjAo
# oCagJIYiaHR0cDovL2NybC5jZXJ0dW0ucGwvY3RzY2EyMDIxLmNybDBvBggrBgEF
# BQcBAQRjMGEwKAYIKwYBBQUHMAGGHGh0dHA6Ly9zdWJjYS5vY3NwLWNlcnR1bS5j
# b20wNQYIKwYBBQUHMAKGKWh0dHA6Ly9yZXBvc2l0b3J5LmNlcnR1bS5wbC9jdHNj
# YTIwMjEuY2VyMEAGA1UdIAQ5MDcwNQYLKoRoAYb2dwIFAQswJjAkBggrBgEFBQcC
# ARYYaHR0cDovL3d3dy5jZXJ0dW0ucGwvQ1BTMA0GCSqGSIb3DQEBDAUAA4ICAQBr
# xvc9Iz4vV5D57BeApm1pfVgBjTKWgflb1htxJA9HSvXneq/j/+5kohu/1p0j6IJM
# YTpSbT7oHAtg59m0wM0HnmrjcN43qMNo5Ts/gX/SBmY0qMzdlO6m1D9egn7U49Eg
# GO+IZFAnmMH1hLx+pse6dgtThZ4aqr+zRfRNoTFNSUxyOSo6cmVKfRbZgTiLEcMe
# hGJTeM5CQs1AmDpF+hqyq0X6Mv0BMtHU2wPoVlI3xrRQ167lM64/gl8dCYzMPF8l
# 8W89ds2Rfro9Y1p5dI0L8x60opb1f8n5Hf4ayW9Kc7rgUdlnfJc4cYdvV0JxWYpS
# ZPN5LJM54xSKrveXnYq1NNIuovqJOM9mixVMJ2TTWPkfQ2pl0H/ZokxxXB4qEKAy
# Sa6bfcijoQiOaR5wKQR+0yrc7KIdqt+hOVhl5uUti9cZxA8JMiNdX6SaasglnJ9o
# lTSMJ4BRO6tCASEvJeeCzX6ZViKRDHbFQCaMZ1XdxlwR6Cqkfa2p5EN1DKQSjxI1
# p6lddQmc9PTVGWM8dpbRKtHHBoOQvfWEdigP3EI7RGZqWTonwr8AaMCgTzYbFpuZ
# ed3lG7yi0jwUJo9/ryUNFA82m9CpzLcaAKaLQ0s1uboR6zaWSt9fqUASNz9zD+8I
# iGlyUqKIAFViQMqqyHej0vK7G2gPqEy5GDdxL/DBaTCCBrkwggShoAMCAQICEQCZ
# o4AKJlU7ZavcboSms+o5MA0GCSqGSIb3DQEBDAUAMIGAMQswCQYDVQQGEwJQTDEi
# MCAGA1UEChMZVW5pemV0byBUZWNobm9sb2dpZXMgUy5BLjEnMCUGA1UECxMeQ2Vy
# dHVtIENlcnRpZmljYXRpb24gQXV0aG9yaXR5MSQwIgYDVQQDExtDZXJ0dW0gVHJ1
# c3RlZCBOZXR3b3JrIENBIDIwHhcNMjEwNTE5MDUzMjE4WhcNMzYwNTE4MDUzMjE4
# WjBWMQswCQYDVQQGEwJQTDEhMB8GA1UEChMYQXNzZWNvIERhdGEgU3lzdGVtcyBT
# LkEuMSQwIgYDVQQDExtDZXJ0dW0gQ29kZSBTaWduaW5nIDIwMjEgQ0EwggIiMA0G
# CSqGSIb3DQEBAQUAA4ICDwAwggIKAoICAQCdI88EMCM7wUYs5zNzPmNdenW6vlxN
# ur3rLfi+5OZ+U3iZIB+AspO+CC/bj+taJUbMbFP1gQBJUzDUCPx7BNLgid1TyztV
# Ln52NKgxxu8gpyTr6EjWyGzKU/gnIu+bHAse1LCitX3CaOE13rbuHbtrxF2tPU8f
# 253QgX6eO8yTbGps1Mg+yda3DcTsOYOhSYNCJiL+5wnjZ9weoGRtvFgMHtJg6i67
# 1OPXIciiHO4Lwo2p9xh/tnj+JmCQEn5QU0NxzrOiRna4kjFaA9ZcwSaG7WAxeC/x
# oZSxF1oK1UPZtKVt+yrsGKqWONoK6f5EmBOAVEK2y4ATDSkb34UD7JA32f+Rm0ws
# r5ajzftDhA5mBipVZDjHpwzv8bTKzCDUSUuUmPo1govD0RwFcTtMXcfJtm1i+P2U
# NXadPyYVKRxKQATHN3imsfBiNRdN5kiVVeqP55piqgxOkyt+HkwIA4gbmSc3hD8k
# e66t9MjlcNg73rZZlrLHsAIV/nJ0mmgSjBI/TthoGJDydekOQ2tQD2Dup/+sKQpt
# alDlui59SerVSJg8gAeV7N/ia4mrGoiez+SqV3olVfxyLFt3o/OQOnBmjhKUANoK
# LYlKmUpKEFI0PfoT8Q1W/y6s9LTI6ekbi0igEbFUIBE8KDUGfIwnisEkBw5KcBZ3
# XwnHmfznwlKo8QIDAQABo4IBVTCCAVEwDwYDVR0TAQH/BAUwAwEB/zAdBgNVHQ4E
# FgQU3XRdTADbe5+gdMqxbvc8wDLAcM0wHwYDVR0jBBgwFoAUtqFUOQLDoD+Oirz6
# 1PgcptE6Dv0wDgYDVR0PAQH/BAQDAgEGMBMGA1UdJQQMMAoGCCsGAQUFBwMDMDAG
# A1UdHwQpMCcwJaAjoCGGH2h0dHA6Ly9jcmwuY2VydHVtLnBsL2N0bmNhMi5jcmww
# bAYIKwYBBQUHAQEEYDBeMCgGCCsGAQUFBzABhhxodHRwOi8vc3ViY2Eub2NzcC1j
# ZXJ0dW0uY29tMDIGCCsGAQUFBzAChiZodHRwOi8vcmVwb3NpdG9yeS5jZXJ0dW0u
# cGwvY3RuY2EyLmNlcjA5BgNVHSAEMjAwMC4GBFUdIAAwJjAkBggrBgEFBQcCARYY
# aHR0cDovL3d3dy5jZXJ0dW0ucGwvQ1BTMA0GCSqGSIb3DQEBDAUAA4ICAQB1iFgP
# 5Y9QKJpTnxDsQ/z0O23JmoZifZdEOEmQvo/79PQg9nLF/GJe6ZiUBEyDBHMtFRK0
# mXj3Qv3gL0sYXe+PPMfwmreJHvgFGWQ7XwnfMh2YIpBrkvJnjwh8gIlNlUl4KENT
# K5DLqsYPEtRQCw7R6p4s2EtWyDDr/M58iY2UBEqfUU/ujR9NuPyKk0bEcEi62JGx
# auFYzZ/yld13fHaZskIoq2XazjaD0pQkcQiIueL0HKiohS6XgZuUtCKA7S6CHttZ
# EsObQJ1j2s0urIDdqF7xaXFVaTHKtAuMfwi0jXtF3JJphrJfc+FFILgCbX/uYBPB
# lbBIP4Ht4xxk2GmfzMn7oxPITpigQFJFWuzTMUUgdRHTxaTSKRJ/6Uh7ki/pFjf9
# sUASWgxT69QF9Ki4JF5nBIujxZ2sOU9e1HSCJwOfK07t5nnzbs1LbHuAIGJsRJiQ
# 6HX/DW1XFOlXY1rc9HufFhWU+7Uk+hFkJsfzqBz3pRO+5aI6u5abI4Qws4YaeJH7
# H7M8X/YNoaArZbV4Ql+jarKsE0+8XvC4DJB+IVcvC9Ydqahi09mjQse4fxfef0L7
# E3hho2O3bLDM6v60rIRUCi2fJT2/IRU5ohgyTch4GuYWefSBsp5NPJh4QRTP9DC3
# gc5QEKtbrTY0Ka87Web7/zScvLmvQBm8JDFpDjCCBrkwggShoAMCAQICEQDn/2nH
# OzXOS5Em2HR8aKWHMA0GCSqGSIb3DQEBDAUAMIGAMQswCQYDVQQGEwJQTDEiMCAG
# A1UEChMZVW5pemV0byBUZWNobm9sb2dpZXMgUy5BLjEnMCUGA1UECxMeQ2VydHVt
# IENlcnRpZmljYXRpb24gQXV0aG9yaXR5MSQwIgYDVQQDExtDZXJ0dW0gVHJ1c3Rl
# ZCBOZXR3b3JrIENBIDIwHhcNMjEwNTE5MDUzMjA3WhcNMzYwNTE4MDUzMjA3WjBW
# MQswCQYDVQQGEwJQTDEhMB8GA1UEChMYQXNzZWNvIERhdGEgU3lzdGVtcyBTLkEu
# MSQwIgYDVQQDExtDZXJ0dW0gVGltZXN0YW1waW5nIDIwMjEgQ0EwggIiMA0GCSqG
# SIb3DQEBAQUAA4ICDwAwggIKAoICAQDpEh8ENe25XXrFppVBvoplf0530W0lddNm
# jtv4YSh/f7eDQKFaIqc7tHj7ox+u8vIsJZlroakUeMS3i3T8aJRC+eQs4FF0Gqvk
# M6+WZO8kmzZfxmZaBYmMLs8FktgFYCzywmXeQ1fEExflee2OpbHVk665eXRHjH7M
# YZIzNnjl2m8Hy8ulB9mR8wL/W0v0pjKNT6G0sfrx1kk+3OGosFUb7yWNnVkWKU4q
# SxLv16kJ6oVJ4BSbZ4xMak6JLeB8szrK9vwGDpvGDnKCUMYL3NuviwH1x4gZG0JA
# XU3x2pOAz91JWKJSAmRy/l0s0l5bEYKolg+DMqVhlOANd8Yh5mkQWaMEvBRE/kAG
# zIqgWhwzN2OsKIVtO8mf5sPWSrvyplSABAYa13rMYnzwfg08nljZHghquCJYCa/x
# HK9acev9UD7Y+usr15d7mrszzxhF1JOr1Mpup2chNSBlyOObhlSO16rwrffVrg/S
# zaKfSndS5swRhr8bnDqNJY9TNyEYvBYpgF95K7p0g4LguR4A++Z1nFIHWVY5v0fN
# VZmgzxD9uVo/gta3onGOQj3JCxgYx0KrCXu4yc9QiVwTFLWbNdHFSjBCt5/8Q9pL
# uRhVocdCunhcHudMS1CGQ/Rn0+7P+fzMgWdRKfEOh/hjLrnQ8BdJiYrZNxvIOhM2
# aa3zEDHNwwIDAQABo4IBVTCCAVEwDwYDVR0TAQH/BAUwAwEB/zAdBgNVHQ4EFgQU
# vlQCL79AbHNDzqwJJU6eQ0Qa7uAwHwYDVR0jBBgwFoAUtqFUOQLDoD+Oirz61Pgc
# ptE6Dv0wDgYDVR0PAQH/BAQDAgEGMBMGA1UdJQQMMAoGCCsGAQUFBwMIMDAGA1Ud
# HwQpMCcwJaAjoCGGH2h0dHA6Ly9jcmwuY2VydHVtLnBsL2N0bmNhMi5jcmwwbAYI
# KwYBBQUHAQEEYDBeMCgGCCsGAQUFBzABhhxodHRwOi8vc3ViY2Eub2NzcC1jZXJ0
# dW0uY29tMDIGCCsGAQUFBzAChiZodHRwOi8vcmVwb3NpdG9yeS5jZXJ0dW0ucGwv
# Y3RuY2EyLmNlcjA5BgNVHSAEMjAwMC4GBFUdIAAwJjAkBggrBgEFBQcCARYYaHR0
# cDovL3d3dy5jZXJ0dW0ucGwvQ1BTMA0GCSqGSIb3DQEBDAUAA4ICAQC4k1l3yUwV
# /ZQHCKCneqAs8EGTnwEUJLdDpokN/dMhKjK0rR5qX8nIIHzxpQR3TAw2IRw1Uxsr
# 2PliG3bCFqSdQTUbfaTq6V3vBzEebDru9QFjqlKnxCF2h1jhLNFFplbPJiW+JSnJ
# Th1fKEqEdKdxgl9rVTvlxfEJ7exOn25MGbd/wGPwuSmMxRJVO0wnqgS7kmoJjNF9
# zqeehFSDDP8ZVkWg4EZ2tIS0M3uZmByRr+1Lkwjjt8AtW83mVnZTyTsOb+FNfwJY
# 7DS4FmWhkRbgcHRetreoTirPOr/ozyDKhT8MTSTf6Lttg6s6T/u08mDWw6HK04ZR
# DfQ9sb77QV8mKgO44WGP31vXnVKoWVJpFBjPvjL8/Zck/5wXX2iqjOaLStFOR/IQ
# ki+Ehn4zlcgVm22ZVCBPF+l8nAwUUShCtKuSU7GmZLKCmmxQMkSiWILTm8EtVD6A
# xnJhoq8EnhjEEyUoflkeRF2WhFiVQOmWTwZRr44IxWGkNJC6tTorW5rl2Zl+2e9J
# LPYf3pStAPMDoPKIjVXd6NW2+fZrNUBeDo2eOa5Fn7Brs/HLQff5Xgris5MeUbdV
# gDrF8uxO6cLPvZPo63j62SsNg55pTWk9fUIF9iPoRbb4QurjoY/woI1RAOKtYtTi
# c6aAJq3u83RIPpGXBSJKwx4KJAOZnCDCtTCCBtswggTDoAMCAQICEGKUqNjbtPSE
# Tu16moosTdUwDQYJKoZIhvcNAQELBQAwVjELMAkGA1UEBhMCUEwxITAfBgNVBAoT
# GEFzc2VjbyBEYXRhIFN5c3RlbXMgUy5BLjEkMCIGA1UEAxMbQ2VydHVtIENvZGUg
# U2lnbmluZyAyMDIxIENBMB4XDTIyMDcwNjE3NTkxOFoXDTIzMDcwNjE3NTkxN1ow
# gYAxCzAJBgNVBAYTAlBMMRIwEAYDVQQIDAlwb21vcnNraWUxHTAbBgNVBAoMFE1h
# cmNpbiBHb8WCxJliaW93c2tpMR0wGwYDVQQDDBRNYXJjaW4gR2/FgsSZYmlvd3Nr
# aTEfMB0GCSqGSIb3DQEJARYQeG9ybXVzQGdtYWlsLmNvbTCCAiIwDQYJKoZIhvcN
# AQEBBQADggIPADCCAgoCggIBAKr2WuURfyFgf3jRzAxUJ8B4MGl2pgHcGnvTjeiB
# L6xwGlWzYiF1ucSUW8MkgulVc+WT2yNXK+Sm2F8IyZzskB0R+vZfp5hPMl8GoyB7
# oEtuwunEJDIoUCWatRMvVPCT7+TlL0+fZuPnQ3oqnY+AqT/ET8Im8oVO0McJndqa
# Rfto1k7ak3No4u1W/274hu4DelYAxeb9mpNeFnYfkAruoYsgN9NVhD9FMOrdcwG8
# ic7tQGPoMXa9C8qdgyeXESSrgSkcHXq62TwEVoK7Hv2A73e/hlxzPqX5VwUkZkV1
# jwCwQwj0kGIPFzVUpx4gruYWuJ5btHwHtZlB7IhpQBwuQkF0XtWmJ6IWzR2RKyyx
# GHt2BYbBCTDEMVwpM5mLP4KkuwOcpJL2sgKCVquX29X9oPpqqQzeIHhsbyvAmlrf
# xQFUz690JeDYLr3d2HpxD7jzniJcDaq4sf/bxdtqU1ZIAXAI1KErB6B6VWQoesWx
# dPDXSTbmhw/7d8adUYGhxWicUY0Vp9N7r2oEsL7hA73hsccveJBeHovUDUt2yVYZ
# xMNfBA+a94d2gXDy4dPfZ1CmT7ifQ38ClgkDWZUxekjhtx+1WPnYT4F4SuGneKDI
# l9JnRztt6xG0UTIMcLgzE5NrLlaKdILPXG/qP4VRJRyjEJgdD1IwvAfTdAYGaXLX
# z6O9AgMBAAGjggF4MIIBdDAMBgNVHRMBAf8EAjAAMD0GA1UdHwQ2MDQwMqAwoC6G
# LGh0dHA6Ly9jY3NjYTIwMjEuY3JsLmNlcnR1bS5wbC9jY3NjYTIwMjEuY3JsMHMG
# CCsGAQUFBwEBBGcwZTAsBggrBgEFBQcwAYYgaHR0cDovL2Njc2NhMjAyMS5vY3Nw
# LWNlcnR1bS5jb20wNQYIKwYBBQUHMAKGKWh0dHA6Ly9yZXBvc2l0b3J5LmNlcnR1
# bS5wbC9jY3NjYTIwMjEuY2VyMB8GA1UdIwQYMBaAFN10XUwA23ufoHTKsW73PMAy
# wHDNMB0GA1UdDgQWBBSbo4Vic2BmodM1NmsAW4N1/N0VlDBLBgNVHSAERDBCMAgG
# BmeBDAEEATA2BgsqhGgBhvZ3AgUBBDAnMCUGCCsGAQUFBwIBFhlodHRwczovL3d3
# dy5jZXJ0dW0ucGwvQ1BTMBMGA1UdJQQMMAoGCCsGAQUFBwMDMA4GA1UdDwEB/wQE
# AwIHgDANBgkqhkiG9w0BAQsFAAOCAgEADZ14LtIisUdnaERD8OHOpbMMZY7zloi7
# aVuP0euezvciM5l0S/1y6LdwQKyC8EoLm8ImdSW5HL9rgLmdDhAZlmFqDf+OrscM
# 3rOIvOY/Zs0VmRY5cOn6Ht760PvPsdBSHodPhZ3zCTASWUaakf+AI3cRBkEqzqtY
# R4L4+9RhLyDTkCIAKdRYzBhmNAGWziI6iW9EwnxxNR8JxVsYdspcgb7wVKI0IFDZ
# 0JzXIotahi1+tAHgS+PXWXrffC6jG3Zr7ZdNanxYTDn4wyT11fNuT1MJDMCOpuvt
# IsnXQexxVsVovSzf/4wtaKQp4nyckgjrSQQUkFRTT5ynyEALBhEs42o8zY61WaKI
# 2jWjZeLAALFBooIiEK0hye/UqcxEc2q76Diub8H7HFMO3+fIsFDZMaXB3JBmoZW4
# X8CX45nv76Vdt6ldlH/6WzS1J3LdfW51kbOwby8ZLZkyz6cawcsfmeiHMzY9w3aL
# 459i7xeLEn57BfDZMvi3F24LoAEA6D2CM/vvCK2+KL5nzbNhaq1Ksfl7QDDdhg88
# tz8qsHjY6PEEcwedcB9YEc9yEuMaLNmxTjga0hi5yIL7FsXZ/tqf5kmLwUSyO7r5
# azilEYS1PQ4O5y+UWURDQ7tKH6CbPE5QuQ35kDfGaVMQziExOW1QQKwf0N0R393c
# 184HgEAr0bUxggciMIIHHgIBATBqMFYxCzAJBgNVBAYTAlBMMSEwHwYDVQQKExhB
# c3NlY28gRGF0YSBTeXN0ZW1zIFMuQS4xJDAiBgNVBAMTG0NlcnR1bSBDb2RlIFNp
# Z25pbmcgMjAyMSBDQQIQYpSo2Nu09IRO7XqaiixN1TANBglghkgBZQMEAgEFAKCB
# hDAYBgorBgEEAYI3AgEMMQowCKACgAChAoAAMBkGCSqGSIb3DQEJAzEMBgorBgEE
# AYI3AgEEMBwGCisGAQQBgjcCAQsxDjAMBgorBgEEAYI3AgEVMC8GCSqGSIb3DQEJ
# BDEiBCDdsdYP87AQVXQHfX3ILrU0ih32BR1aH+x49Owys30QKzANBgkqhkiG9w0B
# AQEFAASCAgCOTm/PS4DuliwSvJouR3prkqL4fX5SdfsOYafl3GUeDZkcFiq50GPa
# CqEG8hM045u4NhjAhL8Y5vR9+qkBledHMPVOj2NEW5zd2/4JgAjT51yy16UiZUPu
# ayvA0LoQ57Bd//5ZHl6hL8dfkrrIo9K5SEuvzNBDrcFCaWN80AElKDJeO1T07tiL
# 9tXHXP1oQrICjJYcsFgsFz1S+LzCEPok6LEN37b4JCTMa0Z57aiavfSwwpf0bmmh
# oT8KThJG3jI/GjDm+sy7ce7R98jIz53kL75jpkOKGWR1dS9e/gBjxTo8GOxbisc4
# f01ItXhy+ALE3YZFQBN+/dN6W4/hPf1LX4wOVn+rV4T9myYOdU5mAVA1SG0QDnz8
# lCvVJ/14WwE0ZWTnyXGxQigPys64oJQ9kltHA39XJlN7o8AuBvXz0ls7cKKaEFIk
# muTAmpeufv/EBgztB52uRpFoVNE0m+p0nzqQyEJUhefV5iP4kYQhVHSVlVYmtAzf
# TIcOE3XeYAkfp8CdyMOGHf3vMBrF2QRlUwTXGafpkPjyY98lUcLO7jP9moGHF2uZ
# OB5zVurOmQUmEK1h7s70jGX77ZwE68vwK5OCozNbW//u6/9Ej76/OiMAgZHDZE8F
# mcwHAOdXNIWMJoB2Vp8N/3Vh+ffngTaJBBumvuDXtX3n1gus3gNYKKGCBAIwggP+
# BgkqhkiG9w0BCQYxggPvMIID6wIBATBqMFYxCzAJBgNVBAYTAlBMMSEwHwYDVQQK
# ExhBc3NlY28gRGF0YSBTeXN0ZW1zIFMuQS4xJDAiBgNVBAMTG0NlcnR1bSBUaW1l
# c3RhbXBpbmcgMjAyMSBDQQIQK9SucLnQY1sq6YTI1nSqMDANBglghkgBZQMEAgIF
# AKCCAVYwGgYJKoZIhvcNAQkDMQ0GCyqGSIb3DQEJEAEEMBwGCSqGSIb3DQEJBTEP
# Fw0yMzAyMTgyMzA3NThaMDcGCyqGSIb3DQEJEAIvMSgwJjAkMCIEIAO5mmRJdJhK
# lbbMXYDTRNB0+972yiQEhCvmzw5EIgeKMD8GCSqGSIb3DQEJBDEyBDBZM61DtitS
# mAOzoCucwgfdrxQboRnRr4AWVir2odkt7lhUq2qE1LsflKapotX3wGswgZ8GCyqG
# SIb3DQEJEAIMMYGPMIGMMIGJMIGGBBS/T2vEmC3eFQWo78jHp51NFDUAzjBuMFqk
# WDBWMQswCQYDVQQGEwJQTDEhMB8GA1UEChMYQXNzZWNvIERhdGEgU3lzdGVtcyBT
# LkEuMSQwIgYDVQQDExtDZXJ0dW0gVGltZXN0YW1waW5nIDIwMjEgQ0ECECvUrnC5
# 0GNbKumEyNZ0qjAwDQYJKoZIhvcNAQEBBQAEggIAWxExi4YND1q0NXLN2FG7rg6F
# 7nUaQvYbcvicGLGHriqWyytQ+hqQzU+JK5iU7iJZbhJMxCdlsqIoRTnmrRtnkMiO
# 8Kmiv29LSHeK6q0Mz0YBfMnK+a2/e30Kei+D+40pYbc7dM4P5a6aDcd9IqaNhp0I
# 8cOOuOxhM4dCtcFUeMYNX5yc/LNjRYai3r8ObU7LNhvW8mgI1kkG+g5CF9zTFO2N
# hBPl6VT+RhI7faPI2ynvcTIwEOqBnXVHm4r20Smb7OzeWwtOFxxesdAkhWzXG+mK
# pTH1ASRyjxwXZhDhn8cqHVDLWM1FI4TFkNnbzkv7G0Tmu2YW7T2I8i9puz1v3FwT
# +U/C2qly3mSntkQ8ABNnufoPPLGHXZZT8nqv/ZZs/k/z9GlPmqBNe2oFIQbFjkc3
# rGaINiB/vR1vzvDgKnIMi4IvxghmbmHQQk1oz1SHpsnRWLZArjQR98iqTUgV67yr
# 0EbWKacCulOSvDOqttniYeYVpJqgA7DVDiopm1fO+DKuVH7dpKj6UswQaDl9T8pa
# P3HLzM1S/SXzIssX9tRkuN9k++tP0vaoWywRaONBrfmjeoftXgZA9XwRdZ+FTcOU
# fBDJRHwY4wn9h366DXvqOgsl3UVjfmdGCLec/n0EncXAevFqh2JWIfMor/AI0gsK
# mJEppRvqIpYsS7+bjVI=
# SIG # End signature block
