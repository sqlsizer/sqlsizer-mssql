<#
.SYNOPSIS
    Fluent API builders for TraversalConfiguration objects.
    
.DESCRIPTION
    Provides a clean, readable way to build complex traversal configurations
    using method chaining (fluent interface pattern).
    
.EXAMPLE
    $config = New-TraversalConfigurationBuilder |
        Add-TableRule -Schema "Sales" -Table "Orders" -State Include -MaxDepth 3 |
        Add-TableRule -Schema "Sales" -Table "OrderDetails" -Top 100 |
        Add-IgnoredTable -Schema "dbo" -Table "AuditLog" |
        Build
#>

class TraversalConfigurationBuilder
{
    hidden [System.Collections.Generic.List[TraversalRule]]$Rules
    
    TraversalConfigurationBuilder()
    {
        $this.Rules = New-Object "System.Collections.Generic.List[TraversalRule]"
    }
    
    <#
    .SYNOPSIS
        Adds a table-specific traversal rule.
    .DESCRIPTION
        Configures state override and/or constraints for a specific table.
    .EXAMPLE
        $builder.AddTableRule("dbo", "Orders", [TraversalState]::Include, 3, 100)
    #>
    [TraversalConfigurationBuilder] AddTableRule(
        [string]$SchemaName,
        [string]$TableName,
        [TraversalState]$State,
        [int]$MaxDepth = -1,
        [int]$Top = -1
    )
    {
        $rule = New-Object TraversalRule
        $rule.SchemaName = $SchemaName
        $rule.TableName = $TableName
        
        # Add state override
        $rule.StateOverride = New-Object StateOverride
        $rule.StateOverride.State = $State
        
        # Add constraints if specified
        if ($MaxDepth -ne -1 -or $Top -ne -1)
        {
            $rule.Constraints = New-Object TraversalConstraints
            $rule.Constraints.MaxDepth = $MaxDepth
            $rule.Constraints.Top = $Top
        }
        
        $this.Rules.Add($rule)
        return $this
    }
    
    <#
    .SYNOPSIS
        Adds a table with state override only (no constraints).
    #>
    [TraversalConfigurationBuilder] AddStateOverride(
        [string]$SchemaName,
        [string]$TableName,
        [TraversalState]$State
    )
    {
        return $this.AddTableRule($SchemaName, $TableName, $State, -1, -1)
    }
    
    <#
    .SYNOPSIS
        Adds a table with constraints only (no state override).
    #>
    [TraversalConfigurationBuilder] AddConstraints(
        [string]$SchemaName,
        [string]$TableName,
        [int]$MaxDepth = -1,
        [int]$Top = -1
    )
    {
        $rule = New-Object TraversalRule
        $rule.SchemaName = $SchemaName
        $rule.TableName = $TableName
        
        $rule.Constraints = New-Object TraversalConstraints
        $rule.Constraints.MaxDepth = $MaxDepth
        $rule.Constraints.Top = $Top
        
        $this.Rules.Add($rule)
        return $this
    }
    
    <#
    .SYNOPSIS
        Marks a table as excluded from traversal.
    #>
    [TraversalConfigurationBuilder] AddIgnoredTable(
        [string]$SchemaName,
        [string]$TableName
    )
    {
        return $this.AddStateOverride($SchemaName, $TableName, [TraversalState]::Exclude)
    }
    
    <#
    .SYNOPSIS
        Adds a table with Include state and optional constraints.
    #>
    [TraversalConfigurationBuilder] AddIncludeTable(
        [string]$SchemaName,
        [string]$TableName,
        [int]$MaxDepth = -1,
        [int]$Top = -1
    )
    {
        return $this.AddTableRule($SchemaName, $TableName, [TraversalState]::Include, $MaxDepth, $Top)
    }
    
    <#
    .SYNOPSIS
        Sets a maximum depth for a table.
    #>
    [TraversalConfigurationBuilder] SetMaxDepth(
        [string]$SchemaName,
        [string]$TableName,
        [int]$MaxDepth
    )
    {
        return $this.AddConstraints($SchemaName, $TableName, $MaxDepth, -1)
    }
    
    <#
    .SYNOPSIS
        Sets a maximum record count for a table.
    #>
    [TraversalConfigurationBuilder] SetTopLimit(
        [string]$SchemaName,
        [string]$TableName,
        [int]$Top
    )
    {
        return $this.AddConstraints($SchemaName, $TableName, -1, $Top)
    }
    
    <#
    .SYNOPSIS
        Builds the final TraversalConfiguration object.
    #>
    [TraversalConfiguration] Build()
    {
        $config = New-Object TraversalConfiguration
        $config.Rules = $this.Rules.ToArray()
        return $config
    }
    
    <#
    .SYNOPSIS
        Gets the current rule count.
    #>
    [int] GetRuleCount()
    {
        return $this.Rules.Count
    }
    
    <#
    .SYNOPSIS
        Clears all rules (for reuse).
    #>
    [TraversalConfigurationBuilder] Clear()
    {
        $this.Rules.Clear()
        return $this
    }
}

function New-TraversalConfigurationBuilder
{
    <#
    .SYNOPSIS
        Creates a new fluent builder for TraversalConfiguration.
    .DESCRIPTION
        Entry point for building configurations using method chaining.
    .EXAMPLE
        $config = New-TraversalConfigurationBuilder |
            Add-IncludeTable "Sales" "Orders" -MaxDepth 3 |
            Add-IgnoredTable "dbo" "AuditLog" |
            Build
    .OUTPUTS
        TraversalConfigurationBuilder
    #>
    [CmdletBinding()]
    [OutputType([TraversalConfigurationBuilder])]
    param()
    
    return [TraversalConfigurationBuilder]::new()
}

function Add-TableRule
{
    <#
    .SYNOPSIS
        Adds a table-specific rule to the configuration builder.
    .DESCRIPTION
        Supports pipeline and method chaining for fluent API.
    .EXAMPLE
        $builder | Add-TableRule -Schema "Sales" -Table "Orders" -State Include -MaxDepth 3
    #>
    [CmdletBinding()]
    [OutputType([TraversalConfigurationBuilder])]
    param
    (
        [Parameter(Mandatory = $true, ValueFromPipeline = $true)]
        [TraversalConfigurationBuilder]$Builder,
        
        [Parameter(Mandatory = $true)]
        [string]$Schema,
        
        [Parameter(Mandatory = $true)]
        [string]$Table,
        
        [Parameter(Mandatory = $false)]
        [TraversalState]$State = [TraversalState]::Include,
        
        [Parameter(Mandatory = $false)]
        [int]$MaxDepth = -1,
        
        [Parameter(Mandatory = $false)]
        [int]$Top = -1
    )
    
    process
    {
        return $Builder.AddTableRule($Schema, $Table, $State, $MaxDepth, $Top)
    }
}

function Add-IncludeTable
{
    <#
    .SYNOPSIS
        Adds a table with Include state to the configuration.
    .EXAMPLE
        $builder | Add-IncludeTable -Schema "Sales" -Table "Orders" -MaxDepth 3 -Top 100
    #>
    [CmdletBinding()]
    [OutputType([TraversalConfigurationBuilder])]
    param
    (
        [Parameter(Mandatory = $true, ValueFromPipeline = $true)]
        [TraversalConfigurationBuilder]$Builder,
        
        [Parameter(Mandatory = $true)]
        [string]$Schema,
        
        [Parameter(Mandatory = $true)]
        [string]$Table,
        
        [Parameter(Mandatory = $false)]
        [int]$MaxDepth = -1,
        
        [Parameter(Mandatory = $false)]
        [int]$Top = -1
    )
    
    process
    {
        return $Builder.AddIncludeTable($Schema, $Table, $MaxDepth, $Top)
    }
}

function Add-IgnoredTable
{
    <#
    .SYNOPSIS
        Marks a table as ignored (Exclude state).
    .EXAMPLE
        $builder | Add-IgnoredTable -Schema "dbo" -Table "AuditLog"
    #>
    [CmdletBinding()]
    [OutputType([TraversalConfigurationBuilder])]
    param
    (
        [Parameter(Mandatory = $true, ValueFromPipeline = $true)]
        [TraversalConfigurationBuilder]$Builder,
        
        [Parameter(Mandatory = $true)]
        [string]$Schema,
        
        [Parameter(Mandatory = $true)]
        [string]$Table
    )
    
    process
    {
        return $Builder.AddIgnoredTable($Schema, $Table)
    }
}

function Set-MaxDepth
{
    <#
    .SYNOPSIS
        Sets maximum traversal depth for a table.
    .EXAMPLE
        $builder | Set-MaxDepth -Schema "Sales" -Table "Orders" -Depth 5
    #>
    [CmdletBinding()]
    [OutputType([TraversalConfigurationBuilder])]
    param
    (
        [Parameter(Mandatory = $true, ValueFromPipeline = $true)]
        [TraversalConfigurationBuilder]$Builder,
        
        [Parameter(Mandatory = $true)]
        [string]$Schema,
        
        [Parameter(Mandatory = $true)]
        [string]$Table,
        
        [Parameter(Mandatory = $true)]
        [int]$Depth
    )
    
    process
    {
        return $Builder.SetMaxDepth($Schema, $Table, $Depth)
    }
}

function Set-TopLimit
{
    <#
    .SYNOPSIS
        Sets maximum record count for a table.
    .EXAMPLE
        $builder | Set-TopLimit -Schema "Sales" -Table "Orders" -Top 1000
    #>
    [CmdletBinding()]
    [OutputType([TraversalConfigurationBuilder])]
    param
    (
        [Parameter(Mandatory = $true, ValueFromPipeline = $true)]
        [TraversalConfigurationBuilder]$Builder,
        
        [Parameter(Mandatory = $true)]
        [string]$Schema,
        
        [Parameter(Mandatory = $true)]
        [string]$Table,
        
        [Parameter(Mandatory = $true)]
        [int]$Top
    )
    
    process
    {
        return $Builder.SetTopLimit($Schema, $Table, $Top)
    }
}

function Build-Configuration
{
    <#
    .SYNOPSIS
        Builds the final TraversalConfiguration from the builder.
    .DESCRIPTION
        Terminal operation in the fluent API chain.
    .EXAMPLE
        $config = $builder | Build-Configuration
    #>
    [CmdletBinding()]
    [OutputType([TraversalConfiguration])]
    param
    (
        [Parameter(Mandatory = $true, ValueFromPipeline = $true)]
        [TraversalConfigurationBuilder]$Builder
    )
    
    process
    {
        return $Builder.Build()
    }
}

<#
.SYNOPSIS
    Quick configuration builders for common scenarios.
#>

function New-SimpleIncludeConfiguration
{
    <#
    .SYNOPSIS
        Creates a configuration that includes specific tables with optional depth limit.
    .EXAMPLE
        $config = New-SimpleIncludeConfiguration -Tables @(
            @{ Schema = "Sales"; Table = "Orders"; MaxDepth = 3 },
            @{ Schema = "Sales"; Table = "Customers"; MaxDepth = 2 }
        )
    #>
    [CmdletBinding()]
    [OutputType([TraversalConfiguration])]
    param
    (
        [Parameter(Mandatory = $true)]
        [hashtable[]]$Tables
    )
    
    $builder = New-TraversalConfigurationBuilder
    
    foreach ($table in $Tables)
    {
        $maxDepth = if ($table.ContainsKey('MaxDepth')) { $table.MaxDepth } else { -1 }
        $top = if ($table.ContainsKey('Top')) { $table.Top } else { -1 }
        
        $builder = $builder.AddIncludeTable(
            $table.Schema,
            $table.Table,
            $maxDepth,
            $top
        )
    }
    
    return $builder.Build()
}

function New-ExclusionConfiguration
{
    <#
    .SYNOPSIS
        Creates a configuration that excludes specific tables.
    .EXAMPLE
        $config = New-ExclusionConfiguration -Tables @(
            @{ Schema = "dbo"; Table = "AuditLog" },
            @{ Schema = "dbo"; Table = "SystemLog" }
        )
    #>
    [CmdletBinding()]
    [OutputType([TraversalConfiguration])]
    param
    (
        [Parameter(Mandatory = $true)]
        [hashtable[]]$Tables
    )
    
    $builder = New-TraversalConfigurationBuilder
    
    foreach ($table in $Tables)
    {
        $builder = $builder.AddIgnoredTable($table.Schema, $table.Table)
    }
    
    return $builder.Build()
}

function ConvertFrom-ColorMap
{
    <#
    .SYNOPSIS
        Converts a legacy ColorMap to modern TraversalConfiguration.
    .DESCRIPTION
        Migration helper for existing code using ColorMap.
    .EXAMPLE
        $colorMap = Get-LegacyColorMap
        $config = ConvertFrom-ColorMap $colorMap
    #>
    [CmdletBinding()]
    [OutputType([TraversalConfiguration])]
    param
    (
        [Parameter(Mandatory = $true, ValueFromPipeline = $true)]
        [ColorMap]$ColorMap
    )
    
    process
    {
        return New-TraversalConfigurationFromColorMap -ColorMap $ColorMap
    }
}

function ConvertTo-ColorMap
{
    <#
    .SYNOPSIS
        Converts a TraversalConfiguration to legacy ColorMap.
    .DESCRIPTION
        Compatibility helper for code expecting ColorMap.
    .EXAMPLE
        $config = Get-TraversalConfiguration
        $colorMap = ConvertTo-ColorMap $config
    #>
    [CmdletBinding()]
    [OutputType([ColorMap])]
    param
    (
        [Parameter(Mandatory = $true, ValueFromPipeline = $true)]
        [TraversalConfiguration]$Configuration
    )
    
    process
    {
        return New-ColorMapFromTraversalConfiguration -Configuration $Configuration
    }
}

# Export all configuration builder functions
Export-ModuleMember -Function @(
    'New-TraversalConfigurationBuilder',
    'Add-TableRule',
    'Add-IncludeTable',
    'Add-IgnoredTable',
    'Set-MaxDepth',
    'Set-TopLimit',
    'Build-Configuration',
    'New-SimpleIncludeConfiguration',
    'New-ExclusionConfiguration',
    'ConvertFrom-ColorMap',
    'ConvertTo-ColorMap'
)

<#
.NOTES
    Usage Examples:
    
    # Example 1: Basic configuration with method chaining
    $config = New-TraversalConfigurationBuilder |
        Add-IncludeTable "Sales" "Orders" -MaxDepth 3 |
        Add-IncludeTable "Sales" "Customers" -MaxDepth 2 |
        Add-IgnoredTable "dbo" "AuditLog" |
        Build-Configuration
    
    # Example 2: Using pipeline syntax
    $config = New-TraversalConfigurationBuilder |
        Add-TableRule -Schema "Sales" -Table "Orders" -State Include -MaxDepth 3 -Top 1000 |
        Add-TableRule -Schema "Production" -Table "Products" -State Include -MaxDepth 2 |
        Set-MaxDepth -Schema "Sales" -Table "OrderDetails" -Depth 4 |
        Build-Configuration
    
    # Example 3: Quick configuration for common scenario
    $config = New-SimpleIncludeConfiguration -Tables @(
        @{ Schema = "Sales"; Table = "Orders"; MaxDepth = 3 },
        @{ Schema = "Sales"; Table = "Customers"; MaxDepth = 2; Top = 100 }
    )
    
    # Example 4: Exclusion list
    $config = New-ExclusionConfiguration -Tables @(
        @{ Schema = "dbo"; Table = "AuditLog" },
        @{ Schema = "dbo"; Table = "SystemLog" },
        @{ Schema = "dbo"; Table = "ErrorLog" }
    )
    
    # Example 5: Converting from legacy ColorMap
    $oldColorMap = Get-LegacyColorMap
    $newConfig = $oldColorMap | ConvertFrom-ColorMap
#>
