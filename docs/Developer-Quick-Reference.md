# SqlSizer Developer Quick Reference

## Table of Contents
- [Validation Helpers](#validation-helpers)
- [Configuration Builders](#configuration-builders)
- [Testing](#testing)
- [Common Patterns](#common-patterns)
- [Troubleshooting](#troubleshooting)

---

## Validation Helpers

### Basic Parameter Validation

```powershell
# Null check
$value = Assert-NotNull $value "parameterName"

# String not empty
$name = Assert-NotNullOrEmpty $name "userName"

# Numeric range
$depth = Assert-GreaterThan $depth 0 "maxDepth"
$count = Assert-InRange $count 1 100 "recordCount"

# Enum validation
$state = Assert-ValidTraversalState $state
$direction = Assert-ValidTraversalDirection $direction
```

### Domain-Specific Validation

```powershell
# Session ID validation (prevents SQL injection)
$sessionId = Assert-ValidSessionId $sessionId

# Connection info validation
$conn = Assert-ValidConnectionInfo $connectionInfo

# Table validation with detailed errors
$table = Get-ValidatedTableInfo `
    -SchemaName "dbo" `
    -TableName "Orders" `
    -DatabaseInfo $dbInfo `
    -RequirePrimaryKey $true
```

### SQL Security

```powershell
# Check for SQL injection patterns
if (Test-SqlInjectionRisk $userInput) {
    Write-Warning "Potential SQL injection detected"
}

# Or throw exception
Test-SqlInjectionRisk $userInput -Throw
```

---

## Configuration Builders

### Fluent API - Basic Usage

```powershell
# Simple include configuration
$config = New-TraversalConfigurationBuilder |
    Add-IncludeTable "Sales" "Orders" -MaxDepth 3 |
    Add-IncludeTable "Sales" "Customers" -MaxDepth 2 |
    Build-Configuration
```

### Complex Configuration

```powershell
# Full-featured configuration
$config = New-TraversalConfigurationBuilder |
    Add-IncludeTable "Sales" "Customers" -MaxDepth 2 -Top 100 |
    Add-IncludeTable "Sales" "Orders" -MaxDepth 3 -Top 500 |
    Add-IncludeTable "Sales" "OrderDetails" -MaxDepth 4 |
    Add-IgnoredTable "dbo" "AuditLog" |
    Add-IgnoredTable "dbo" "SystemLog" |
    Set-MaxDepth "Production" "Products" -Depth 2 |
    Set-TopLimit "Sales" "LargeTable" -Top 1000 |
    Build-Configuration
```

### Quick Builders

```powershell
# Include specific tables
$config = New-SimpleIncludeConfiguration -Tables @(
    @{ Schema = "Sales"; Table = "Orders"; MaxDepth = 3; Top = 1000 },
    @{ Schema = "Sales"; Table = "Customers"; MaxDepth = 2 }
)

# Exclude tables
$config = New-ExclusionConfiguration -Tables @(
    @{ Schema = "dbo"; Table = "AuditLog" },
    @{ Schema = "dbo"; Table = "SystemLog" }
)
```

### Legacy Migration

```powershell
# Convert from ColorMap
$oldColorMap = Get-LegacyColorMap
$newConfig = $oldColorMap | ConvertFrom-ColorMap

# Convert to ColorMap (for backward compatibility)
$colorMap = $newConfig | ConvertTo-ColorMap
```

---

## Testing

### Running Tests

```powershell
# All tests
Invoke-Pester

# Specific test file
Invoke-Pester .\TraversalHelpers.Tests.ps1

# With detailed output
Invoke-Pester -Output Detailed

# Exclude integration tests
Invoke-Pester -ExcludeTag Integration

# Only integration tests
$env:RUN_INTEGRATION_TESTS = "true"
Invoke-Pester -Tag Integration
```

### Writing Tests

```powershell
Describe 'My Function Tests' {
    BeforeAll {
        # Setup code
        $testData = @{ ... }
    }
    
    Context 'Valid Inputs' {
        It 'Returns expected result' {
            $result = My-Function -Param1 "value"
            $result | Should -Be "expected"
        }
    }
    
    Context 'Invalid Inputs' {
        It 'Throws on null parameter' {
            { My-Function -Param1 $null } | Should -Throw
        }
    }
}
```

---

## Common Patterns

### Function Template with Validation

```powershell
function My-Function {
    [CmdletBinding()]
    [OutputType([type])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$SessionId,
        
        [Parameter(Mandatory = $true)]
        [TableInfo]$Table,
        
        [Parameter(Mandatory = $false)]
        [int]$MaxDepth = -1
    )
    
    try {
        # Validate inputs
        $SessionId = Assert-ValidSessionId $SessionId
        $Table = Assert-NotNull $Table "Table"
        
        if ($MaxDepth -ne -1) {
            $MaxDepth = Assert-GreaterThan $MaxDepth 0 "MaxDepth"
        }
        
        # Function logic here
        # ...
        
        return $result
    }
    catch {
        Write-Error "My-Function failed: $_"
        throw
    }
}
```

### Configuration Pattern

```powershell
# Build configuration
$config = New-TraversalConfigurationBuilder |
    Add-IncludeTable $schema $table -MaxDepth $depth |
    Build-Configuration

# Use configuration
$result = Find-Subset-Refactored `
    -Database $database `
    -ConnectionInfo $connection `
    -DatabaseInfo $dbInfo `
    -SessionId $sessionId `
    -TraversalConfiguration $config `
    -FullSearch $false
```

### Safe Table Lookup

```powershell
# Get table with validation
$table = Get-ValidatedTableInfo `
    -SchemaName $schema `
    -TableName $tableName `
    -DatabaseInfo $dbInfo `
    -ThrowIfNotFound $true `
    -RequirePrimaryKey $true

# Or check manually
if (-not (Test-TableHasPrimaryKey $table)) {
    Write-Warning "Table has no primary key"
    return
}
```

---

## Troubleshooting

### Common Errors

#### "Table not found in database schema"
```powershell
# Error includes list of available tables
# Solution: Check schema name and table name spelling
$tables = $dbInfo.Tables | Select-Object SchemaName, TableName
Write-Host "Available tables:"
$tables | Format-Table
```

#### "Parameter cannot be null"
```powershell
# Solution: Ensure all required parameters are provided
# Use -Verbose to see which parameter is null
My-Function -Param1 $value -Verbose
```

#### "SQL injection risk detected"
```powershell
# Solution: Don't pass user input directly
# Use parameterized queries or validated values
Assert-ValidSessionId $sessionId  # Validates format
```

#### "Table does not have a primary key"
```powershell
# Solution: Add primary key or use -RequirePrimaryKey $false
$table = Get-ValidatedTableInfo `
    -SchemaName $schema `
    -TableName $tableName `
    -DatabaseInfo $dbInfo `
    -RequirePrimaryKey $false  # Allow tables without PK
```

### Debugging Tips

```powershell
# Enable verbose output
$VerbosePreference = "Continue"
Find-Subset-Refactored -Verbose ...

# Check validation
Write-Host "Validating session ID..."
$sessionId = Assert-ValidSessionId $sessionId
Write-Host "Session ID valid: $sessionId"

# Test SQL injection
Write-Host "Testing for SQL injection..."
if (Test-SqlInjectionRisk $value) {
    Write-Warning "Risk detected in: $value"
}

# Inspect configuration
$config = New-TraversalConfigurationBuilder |
    Add-IncludeTable "dbo" "Orders" |
    Build-Configuration
Write-Host "Rules count: $($config.Rules.Count)"
$config.Rules | Format-List
```

### Performance

```powershell
# Measure execution time
Measure-Command {
    Find-Subset-Refactored ...
}

# Check query caching
$PSDefaultParameterValues['Invoke-SqlcmdEx:Verbose'] = $true

# Monitor memory
[System.GC]::GetTotalMemory($false) / 1MB
```

---

## Quick Checklist

### Before Running Find-Subset-Refactored

- [ ] Database connection validated
- [ ] DatabaseInfo retrieved and cached
- [ ] Session ID generated and validated
- [ ] Start queries defined
- [ ] Configuration built (if needed)
- [ ] Test database connection first

### Code Quality

- [ ] All parameters validated
- [ ] Error handling in place (try/catch)
- [ ] XML documentation complete
- [ ] Unit tests written
- [ ] PSScriptAnalyzer passes
- [ ] No hardcoded values

### Testing

- [ ] Unit tests pass
- [ ] Integration tests pass (if enabled)
- [ ] Edge cases covered
- [ ] Error scenarios tested
- [ ] Performance acceptable

---

## Examples

### Complete Workflow

```powershell
# 1. Setup
$connection = New-SqlConnectionInfo -Server "localhost"
$dbInfo = Get-DatabaseInfo -Database "MyDB" -ConnectionInfo $connection

# 2. Create session
$sessionId = "SUBSET-$(Get-Date -Format 'yyyyMMdd-HHmmss')"
$sessionId = Assert-ValidSessionId $sessionId

Start-SqlSizerSession `
    -Database "MyDB" `
    -ConnectionInfo $connection `
    -DatabaseInfo $dbInfo `
    -SessionId $sessionId

# 3. Define start set
$query = New-Object Query
$query.Color = [Color]::Green
$query.Schema = "Sales"
$query.Table = "Orders"
$query.KeyColumns = @('OrderID')
$query.Where = "OrderDate >= '2024-01-01'"
$query.Top = 100

Initialize-StartSet `
    -Database "MyDB" `
    -ConnectionInfo $connection `
    -Queries @($query) `
    -DatabaseInfo $dbInfo `
    -SessionId $sessionId

# 4. Build configuration
$config = New-TraversalConfigurationBuilder |
    Add-IncludeTable "Sales" "Customers" -MaxDepth 2 |
    Add-IncludeTable "Sales" "OrderDetails" -MaxDepth 3 |
    Add-IgnoredTable "dbo" "AuditLog" |
    Build-Configuration

# 5. Find subset
$result = Find-Subset-Refactored `
    -Database "MyDB" `
    -ConnectionInfo $connection `
    -DatabaseInfo $dbInfo `
    -SessionId $sessionId `
    -TraversalConfiguration $config `
    -FullSearch $false `
    -UseDfs $false

# 6. Check results
Write-Host "Finished: $($result.Finished)"
Write-Host "Iterations: $($result.CompletedIterations)"

# 7. Get subset tables
$tables = Get-SubsetTables `
    -Database "MyDB" `
    -Connection $connection `
    -DatabaseInfo $dbInfo `
    -SessionId $sessionId

$tables | Format-Table SchemaName, TableName, RowCount

# 8. Cleanup
Clear-SqlSizerSession `
    -SessionId $sessionId `
    -Database "MyDB" `
    -ConnectionInfo $connection `
    -DatabaseInfo $dbInfo
```

---

## Resources

- **Documentation**: `docs/` directory
- **Examples**: `Examples/` directory
- **Tests**: `Tests/` directory
- **Issues**: GitHub Issues
- **Wiki**: GitHub Wiki

---

**Last Updated**: October 19, 2025  
**Version**: 1.0  
**Maintainer**: SqlSizer Team
