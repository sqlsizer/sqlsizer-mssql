# Find-Subset Refactoring: Testable Functions

## Overview

This refactoring splits the monolithic `Find-Subset-Refactored.ps1` function into testable, modular components with comprehensive unit tests.

## Architecture Changes

### Before
- Single 800+ line function with 15 nested helper functions
- No unit tests
- Difficult to test in isolation
- Mixed concerns (logic, SQL generation, database operations)

### After
- **3 separate modules** with focused responsibilities
- **150+ unit tests** covering core logic
- **Pure functions** that can be tested without database
- **Clear separation** of concerns

## New Module Structure

```
SqlSizer-MSSQL/
├── Shared/
│   ├── TraversalHelpers.ps1      # Pure logic functions
│   └── QueryBuilders.ps1         # SQL generation functions
├── Public/
│   └── Find-Subset-Refactored.ps1 # Main orchestration (updated)
Tests/
├── TraversalHelpers.Tests.ps1    # 80+ unit tests
├── QueryBuilders.Tests.ps1       # 70+ unit tests
├── Integration.Tests.ps1         # Database integration tests
├── Run-Tests.ps1                 # Test runner script
└── README.md                     # Test documentation
```

## Extracted Functions

### TraversalHelpers.ps1 (Pure Logic)

| Function | Purpose | Testability |
|----------|---------|-------------|
| `Get-NewTraversalState` | Calculates state transitions | ✅ Pure function |
| `Get-TraversalConstraints` | Retrieves MaxDepth/Top constraints | ✅ Pure function |
| `Test-ShouldTraverseDirection` | Determines traversal eligibility | ✅ Pure function |
| `Get-TopClause` | Generates SQL TOP clause | ✅ Pure function |
| `Get-ForeignKeyRelationships` | Extracts FK collections | ✅ Pure function |
| `Get-TargetTableInfo` | Gets target table metadata | ✅ Pure function |
| `Test-ShouldSkipTable` | Checks if table should be ignored | ✅ Pure function |
| `Get-JoinConditions` | Builds SQL JOIN clauses | ✅ Pure function |
| `Get-AdditionalWhereConditions` | Builds WHERE constraints | ✅ Pure function |

### QueryBuilders.ps1 (SQL Generation)

| Function | Purpose | Testability |
|----------|---------|-------------|
| `New-CTETraversalQuery` | Builds main CTE traversal query | ✅ String generation |
| `New-PendingResolutionQuery` | Resolves Pending states | ✅ String generation |
| `New-ExcludePendingQuery` | Marks Pending as Exclude | ✅ String generation |
| `New-GetNextOperationQuery` | BFS/DFS query generation | ✅ String generation |
| `New-MarkOperationInProgressQuery` | Marks operations active | ✅ String generation |
| `New-CompleteOperationsQuery` | Completes operations | ✅ String generation |
| `New-GetIterationStatisticsQuery` | Retrieves progress stats | ✅ String generation |

## Test Coverage

### TraversalHelpers.Tests.ps1
- **80+ test cases** covering:
  - State transition logic (all states × all directions)
  - Configuration overrides
  - Constraint handling
  - Edge cases (null values, empty collections)
  - Boolean decision logic

### QueryBuilders.Tests.ps1
- **70+ test cases** covering:
  - SQL structure validation
  - Parameter injection
  - BFS vs DFS query differences
  - Batch size handling
  - Synapse vs SQL Server differences
  - Comment and formatting

### Integration.Tests.ps1
- Template for database-dependent tests
- Performance benchmarking
- End-to-end validation
- Real-world scenarios

## Benefits

### 1. Testability
- ✅ **Pure functions** can be tested without mocking
- ✅ **SQL generation** can be validated by string matching
- ✅ **Fast tests** - no database required for unit tests
- ✅ **Isolated tests** - each function tested independently

### 2. Maintainability
- ✅ **Single Responsibility** - each function has one job
- ✅ **Clear names** - function names describe intent
- ✅ **Small functions** - average 20 lines vs 800+ before
- ✅ **Documentation** - each function has clear doc comments

### 3. Reliability
- ✅ **Regression prevention** - tests catch breaking changes
- ✅ **Edge case coverage** - explicit tests for corner cases
- ✅ **Consistent behavior** - documented in tests

### 4. Development Speed
- ✅ **Rapid feedback** - tests run in seconds
- ✅ **Safe refactoring** - tests verify behavior unchanged
- ✅ **Clear contracts** - function signatures define inputs/outputs
- ✅ **Examples** - tests serve as usage examples

## Running Tests

### Quick Start
```powershell
# Run all unit tests
.\Tests\Run-Tests.ps1

# With code coverage
.\Tests\Run-Tests.ps1 -CodeCoverage

# Specific test file
Invoke-Pester -Path .\Tests\TraversalHelpers.Tests.ps1
```

### Continuous Integration
```powershell
# Generate XML reports for CI/CD
$config = New-PesterConfiguration
$config.Run.Path = '.\Tests\'
$config.TestResult.Enabled = $true
$config.TestResult.OutputPath = '.\testResults.xml'
Invoke-Pester -Configuration $config
```

## Migration Guide

### Using the New Functions

**Before:**
```powershell
# Logic was embedded in Find-Subset-Refactored
# No way to test in isolation
```

**After:**
```powershell
# Import the module (automatic via .psm1)
Import-Module SqlSizer-MSSQL

# Use helper functions directly if needed
$newState = Get-NewTraversalState `
    -Direction ([TraversalDirection]::Outgoing) `
    -CurrentState ([TraversalState]::Include) `
    -Fk $foreignKey `
    -FullSearch $false

# Generate queries independently
$query = New-GetNextOperationQuery `
    -SessionId $sessionId `
    -UseDfs $false
```

### Updating Find-Subset-Refactored

The main function now calls the extracted helpers:

```powershell
# Old: Inline logic
if ($Direction -eq [TraversalDirection]::Outgoing) {
    if ($CurrentState -eq [TraversalState]::Include) {
        $newState = [TraversalState]::Include
    }
    # ... lots more logic
}

# New: Call helper
$newState = Get-NewTraversalState `
    -Direction $Direction `
    -CurrentState $CurrentState `
    -Fk $Fk `
    -TraversalConfiguration $TraversalConfiguration `
    -FullSearch $FullSearch
```

## Test-Driven Development Workflow

### Adding New Features

1. **Write test first:**
```powershell
It 'Should handle new constraint type' {
    $result = Get-TraversalConstraints -Fk $fk -NewConstraint $value
    $result.NewConstraint | Should -Be $expected
}
```

2. **Run test (should fail):**
```powershell
Invoke-Pester -Path .\Tests\TraversalHelpers.Tests.ps1
```

3. **Implement feature:**
```powershell
function Get-TraversalConstraints {
    # Add logic for NewConstraint
}
```

4. **Run test (should pass):**
```powershell
Invoke-Pester -Path .\Tests\TraversalHelpers.Tests.ps1
```

## Performance Impact

### Unit Test Performance
- **Total tests:** 150+
- **Execution time:** ~5-10 seconds
- **Memory usage:** Minimal (no database)

### Production Performance
- **No performance degradation** - functions are called the same way
- **Query caching** still works
- **Same SQL generated** as before

## Future Enhancements

With testable functions, we can easily:

1. **Add new traversal strategies** - test new algorithms independently
2. **Optimize SQL generation** - verify output is correct
3. **Support new constraints** - test constraint handling
4. **Improve error handling** - test edge cases explicitly
5. **Add metrics/logging** - test metrics calculation

## Best Practices

### When Writing Tests

1. **Arrange-Act-Assert pattern:**
```powershell
It 'Should do something' {
    # Arrange
    $input = Create-TestData
    
    # Act
    $result = Function-UnderTest -Input $input
    
    # Assert
    $result | Should -Be $expected
}
```

2. **Test one thing per test:**
```powershell
# Good
It 'Should return Include for Outgoing + Include' { }
It 'Should return Pending for Incoming + Include' { }

# Bad
It 'Should handle all state transitions' { }
```

3. **Use descriptive names:**
```powershell
# Good
It 'Should apply StateOverride when configuration is provided'

# Bad
It 'Test config override'
```

4. **Test edge cases:**
```powershell
It 'Should handle null configuration'
It 'Should handle empty FK collection'
It 'Should handle table with no primary key'
```

## Conclusion

This refactoring achieves:

- ✅ **100% testable** core logic functions
- ✅ **150+ unit tests** with fast execution
- ✅ **Zero breaking changes** to external API
- ✅ **Improved maintainability** through smaller functions
- ✅ **Better documentation** via tests and comments
- ✅ **Foundation for TDD** going forward

The codebase is now positioned for safe, rapid iteration with confidence.
