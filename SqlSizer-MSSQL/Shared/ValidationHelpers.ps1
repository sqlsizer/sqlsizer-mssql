<#
.SYNOPSIS
    Validation helper functions for SqlSizer-MSSQL.
    
.DESCRIPTION
    This module provides robust parameter validation and error handling
    functions used throughout the SqlSizer module to improve code quality
    and provide better error messages.
#>

function Assert-NotNull
{
    <#
    .SYNOPSIS
        Validates that a parameter is not null.
    .DESCRIPTION
        Throws an ArgumentNullException if the parameter is null.
        Returns the value if valid for method chaining.
    .EXAMPLE
        $table = Assert-NotNull $table "table"
    #>
    [CmdletBinding()]
    [OutputType([object])]
    param
    (
        [Parameter(Mandatory = $true, Position = 0)]
        [AllowNull()]
        [object]$Value,
        
        [Parameter(Mandatory = $true, Position = 1)]
        [string]$ParameterName,
        
        [Parameter(Mandatory = $false)]
        [string]$Message
    )
    
    if ($null -eq $Value)
    {
        if ([string]::IsNullOrEmpty($Message))
        {
            $Message = "Parameter '$ParameterName' cannot be null."
        }
        throw [System.ArgumentNullException]::new($ParameterName, $Message)
    }
    
    return $Value
}

function Assert-NotNullOrEmpty
{
    <#
    .SYNOPSIS
        Validates that a string parameter is not null or empty.
    .DESCRIPTION
        Throws an ArgumentException if the string is null, empty, or whitespace.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param
    (
        [Parameter(Mandatory = $true, Position = 0)]
        [AllowEmptyString()]
        [string]$Value,
        
        [Parameter(Mandatory = $true, Position = 1)]
        [string]$ParameterName,
        
        [Parameter(Mandatory = $false)]
        [string]$Message
    )
    
    if ([string]::IsNullOrWhiteSpace($Value))
    {
        if ([string]::IsNullOrEmpty($Message))
        {
            $Message = "Parameter '$ParameterName' cannot be null or empty."
        }
        throw [System.ArgumentException]::new($Message, $ParameterName)
    }
    
    return $Value
}

function Assert-GreaterThan
{
    <#
    .SYNOPSIS
        Validates that a numeric value is greater than a minimum.
    .DESCRIPTION
        Throws an ArgumentOutOfRangeException if value is not greater than minimum.
    #>
    [CmdletBinding()]
    [OutputType([int])]
    param
    (
        [Parameter(Mandatory = $true, Position = 0)]
        [int]$Value,
        
        [Parameter(Mandatory = $true, Position = 1)]
        [int]$Minimum,
        
        [Parameter(Mandatory = $true, Position = 2)]
        [string]$ParameterName,
        
        [Parameter(Mandatory = $false)]
        [string]$Message
    )
    
    if ($Value -le $Minimum)
    {
        if ([string]::IsNullOrEmpty($Message))
        {
            $Message = "Parameter '$ParameterName' must be greater than $Minimum. Got: $Value"
        }
        throw [System.ArgumentOutOfRangeException]::new($ParameterName, $Value, $Message)
    }
    
    return $Value
}

function Assert-GreaterThanOrEqual
{
    <#
    .SYNOPSIS
        Validates that a numeric value is greater than or equal to a minimum.
    #>
    [CmdletBinding()]
    [OutputType([int])]
    param
    (
        [Parameter(Mandatory = $true, Position = 0)]
        [int]$Value,
        
        [Parameter(Mandatory = $true, Position = 1)]
        [int]$Minimum,
        
        [Parameter(Mandatory = $true, Position = 2)]
        [string]$ParameterName
    )
    
    if ($Value -lt $Minimum)
    {
        $message = "Parameter '$ParameterName' must be greater than or equal to $Minimum. Got: $Value"
        throw [System.ArgumentOutOfRangeException]::new($ParameterName, $Value, $message)
    }
    
    return $Value
}

function Assert-InRange
{
    <#
    .SYNOPSIS
        Validates that a value is within a specified range.
    #>
    [CmdletBinding()]
    [OutputType([int])]
    param
    (
        [Parameter(Mandatory = $true, Position = 0)]
        [int]$Value,
        
        [Parameter(Mandatory = $true, Position = 1)]
        [int]$Minimum,
        
        [Parameter(Mandatory = $true, Position = 2)]
        [int]$Maximum,
        
        [Parameter(Mandatory = $true, Position = 3)]
        [string]$ParameterName
    )
    
    if ($Value -lt $Minimum -or $Value -gt $Maximum)
    {
        $message = "Parameter '$ParameterName' must be between $Minimum and $Maximum. Got: $Value"
        throw [System.ArgumentOutOfRangeException]::new($ParameterName, $Value, $message)
    }
    
    return $Value
}

function Assert-ValidEnum
{
    <#
    .SYNOPSIS
        Validates that a value is a valid enum member.
    .DESCRIPTION
        Checks if the value is defined in the specified enum type.
    #>
    [CmdletBinding()]
    [OutputType([object])]
    param
    (
        [Parameter(Mandatory = $true, Position = 0)]
        [object]$Value,
        
        [Parameter(Mandatory = $true, Position = 1)]
        [Type]$EnumType,
        
        [Parameter(Mandatory = $true, Position = 2)]
        [string]$ParameterName
    )
    
    if (-not [System.Enum]::IsDefined($EnumType, $Value))
    {
        $validValues = [System.Enum]::GetNames($EnumType) -join ', '
        $message = "Parameter '$ParameterName' must be one of: $validValues. Got: $Value"
        throw [System.ArgumentException]::new($message, $ParameterName)
    }
    
    return $Value
}

function Assert-ValidTable
{
    <#
    .SYNOPSIS
        Validates that a table exists in the database schema.
    .DESCRIPTION
        Checks DatabaseInfo for the specified table and throws if not found.
    #>
    [CmdletBinding()]
    [OutputType([TableInfo])]
    param
    (
        [Parameter(Mandatory = $true)]
        [string]$SchemaName,
        
        [Parameter(Mandatory = $true)]
        [string]$TableName,
        
        [Parameter(Mandatory = $true)]
        [DatabaseInfo]$DatabaseInfo,
        
        [Parameter(Mandatory = $false)]
        [bool]$RequirePrimaryKey = $true
    )
    
    Assert-NotNullOrEmpty $SchemaName "SchemaName"
    Assert-NotNullOrEmpty $TableName "TableName"
    Assert-NotNull $DatabaseInfo "DatabaseInfo"
    
    $table = $DatabaseInfo.Tables | Where-Object {
        ($_.SchemaName -eq $SchemaName) -and ($_.TableName -eq $TableName)
    }
    
    if ($null -eq $table)
    {
        throw [System.ArgumentException]::new(
            "Table '$SchemaName.$TableName' not found in database.",
            "TableName"
        )
    }
    
    if ($RequirePrimaryKey -and $table.PrimaryKey.Count -eq 0)
    {
        throw [System.InvalidOperationException]::new(
            "Table '$SchemaName.$TableName' does not have a primary key. " +
            "SqlSizer requires tables to have primary keys for subset operations."
        )
    }
    
    return $table
}

function Assert-ValidSessionId
{
    <#
    .SYNOPSIS
        Validates a session ID format.
    .DESCRIPTION
        Ensures session ID is not empty and has valid format.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param
    (
        [Parameter(Mandatory = $true)]
        [string]$SessionId
    )
    
    Assert-NotNullOrEmpty $SessionId "SessionId"
    
    # SessionId should not contain special characters that could break SQL
    if ($SessionId -match "[';]")
    {
        throw [System.ArgumentException]::new(
            "SessionId cannot contain special SQL characters like semicolon or quote.",
            "SessionId"
        )
    }
    
    if ($SessionId.Length -gt 100)
    {
        throw [System.ArgumentException]::new(
            "SessionId cannot exceed 100 characters. Got: $($SessionId.Length) characters.",
            "SessionId"
        )
    }
    
    return $SessionId
}

function Assert-ValidConnectionInfo
{
    <#
    .SYNOPSIS
        Validates SqlConnectionInfo object.
    .DESCRIPTION
        Ensures connection info has required properties and valid values.
    #>
    [CmdletBinding()]
    [OutputType([SqlConnectionInfo])]
    param
    (
        [Parameter(Mandatory = $true)]
        [SqlConnectionInfo]$ConnectionInfo
    )
    
    Assert-NotNull $ConnectionInfo "ConnectionInfo"
    Assert-NotNullOrEmpty $ConnectionInfo.Server "ConnectionInfo.Server"
    
    # Must have either AccessToken or Credential
    if ([string]::IsNullOrEmpty($ConnectionInfo.AccessToken) -and $null -eq $ConnectionInfo.Credential)
    {
        # Allow Windows Authentication (both null)
        # but at least Server must be specified
    }
    
    return $ConnectionInfo
}

function Test-TableHasPrimaryKey
{
    <#
    .SYNOPSIS
        Tests if a table has a primary key.
    .DESCRIPTION
        Returns true if the table has at least one primary key column.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param
    (
        [Parameter(Mandatory = $true)]
        [TableInfo]$Table
    )
    
    Assert-NotNull $Table "Table"
    return $Table.PrimaryKey.Count -gt 0
}

function Get-ValidatedTableInfo
{
    <#
    .SYNOPSIS
        Gets and validates table information from DatabaseInfo.
    .DESCRIPTION
        Combines lookup and validation in one operation with detailed error messages.
    .RETURNS
        TableInfo object if valid, throws exception otherwise.
    #>
    [CmdletBinding()]
    [OutputType([TableInfo])]
    param
    (
        [Parameter(Mandatory = $true)]
        [string]$SchemaName,
        
        [Parameter(Mandatory = $true)]
        [string]$TableName,
        
        [Parameter(Mandatory = $true)]
        [DatabaseInfo]$DatabaseInfo,
        
        [Parameter(Mandatory = $false)]
        [bool]$RequirePrimaryKey = $true,
        
        [Parameter(Mandatory = $false)]
        [bool]$ThrowIfNotFound = $true
    )
    
    $table = $DatabaseInfo.Tables | Where-Object {
        ($_.SchemaName -eq $SchemaName) -and ($_.TableName -eq $TableName)
    }
    
    if ($null -eq $table)
    {
        if ($ThrowIfNotFound)
        {
            throw [System.ArgumentException]::new(
                "Table '$SchemaName.$TableName' not found in database schema. " +
                "Available tables: $(($DatabaseInfo.Tables | ForEach-Object { "$($_.SchemaName).$($_.TableName)" }) -join ', ')",
                "TableName"
            )
        }
        return $null
    }
    
    if ($RequirePrimaryKey -and $table.PrimaryKey.Count -eq 0)
    {
        throw [System.InvalidOperationException]::new(
            "Table '$SchemaName.$TableName' does not have a primary key. " +
            "Primary key columns: 0. " +
            "SqlSizer requires tables to have primary keys for subset tracking."
        )
    }
    
    return $table
}

function Assert-ValidTraversalState
{
    <#
    .SYNOPSIS
        Validates a TraversalState enum value.
    #>
    [CmdletBinding()]
    [OutputType([TraversalState])]
    param
    (
        [Parameter(Mandatory = $true)]
        [TraversalState]$State
    )
    
    return Assert-ValidEnum $State ([TraversalState]) "State"
}

function Assert-ValidTraversalDirection
{
    <#
    .SYNOPSIS
        Validates a TraversalDirection enum value.
    #>
    [CmdletBinding()]
    [OutputType([TraversalDirection])]
    param
    (
        [Parameter(Mandatory = $true)]
        [TraversalDirection]$Direction
    )
    
    return Assert-ValidEnum $Direction ([TraversalDirection]) "Direction"
}

function New-ValidationError
{
    <#
    .SYNOPSIS
        Creates a standardized validation error object.
    .DESCRIPTION
        Provides consistent error formatting across the module.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param
    (
        [Parameter(Mandatory = $true)]
        [string]$ParameterName,
        
        [Parameter(Mandatory = $true)]
        [string]$ErrorMessage,
        
        [Parameter(Mandatory = $false)]
        [object]$ActualValue,
        
        [Parameter(Mandatory = $false)]
        [string]$ExpectedValue
    )
    
    return @{
        Parameter     = $ParameterName
        Error         = $ErrorMessage
        ActualValue   = $ActualValue
        ExpectedValue = $ExpectedValue
        Timestamp     = Get-Date
    }
}

function Write-ValidationWarning
{
    <#
    .SYNOPSIS
        Writes a standardized validation warning.
    .DESCRIPTION
        Use for non-critical validation issues that should be logged but not fail.
    #>
    [CmdletBinding()]
    param
    (
        [Parameter(Mandatory = $true)]
        [string]$ParameterName,
        
        [Parameter(Mandatory = $true)]
        [string]$WarningMessage
    )
    
    Write-Warning "[$ParameterName] $WarningMessage"
}

function Test-SqlInjectionRisk
{
    <#
    .SYNOPSIS
        Tests a string for potential SQL injection patterns.
    .DESCRIPTION
        Basic heuristic check for dangerous SQL patterns.
        Not a complete security solution but catches obvious issues.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param
    (
        [Parameter(Mandatory = $true)]
        [string]$Value,
        
        [Parameter(Mandatory = $false)]
        [switch]$Throw
    )
    
    # Patterns that suggest SQL injection attempts
    $dangerousPatterns = @(
        "';",           # Statement terminator
        "'--",          # Comment
        "' OR",         # Common injection
        "' AND",        # Common injection
        "EXEC\s*\(",    # Execute command
        "DROP\s+TABLE", # DDL
        "DELETE\s+FROM",# DML
        "INSERT\s+INTO",# DML
        "xp_"           # Extended stored procedures
    )
    
    foreach ($pattern in $dangerousPatterns)
    {
        if ($Value -match $pattern)
        {
            if ($Throw)
            {
                throw [System.Security.SecurityException]::new(
                    "Value contains potentially dangerous SQL pattern: $pattern. " +
                    "Value: $Value"
                )
            }
            return $true
        }
    }
    
    return $false
}

# Export all validation functions
Export-ModuleMember -Function @(
    'Assert-NotNull',
    'Assert-NotNullOrEmpty',
    'Assert-GreaterThan',
    'Assert-GreaterThanOrEqual',
    'Assert-InRange',
    'Assert-ValidEnum',
    'Assert-ValidTable',
    'Assert-ValidSessionId',
    'Assert-ValidConnectionInfo',
    'Test-TableHasPrimaryKey',
    'Get-ValidatedTableInfo',
    'Assert-ValidTraversalState',
    'Assert-ValidTraversalDirection',
    'New-ValidationError',
    'Write-ValidationWarning',
    'Test-SqlInjectionRisk'
)
