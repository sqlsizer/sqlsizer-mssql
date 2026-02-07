# SqlSizer-MSSQL Tests

This directory contains unit tests for the SqlSizer-MSSQL module using Pester.

## Prerequisites

Install Pester if you haven't already:

```powershell
Install-Module -Name Pester -Force -SkipPublisherCheck
```

## Running Tests

### Run all tests

```powershell
# From the repository root
Invoke-Pester -Path .\Tests\

# With detailed output
Invoke-Pester -Path .\Tests\ -Output Detailed
```

### Run specific test files

```powershell
# Test traversal helpers only
Invoke-Pester -Path .\Tests\TraversalHelpers.Tests.ps1

# Test query builders only
Invoke-Pester -Path .\Tests\QueryBuilders.Tests.ps1
```

### Run with code coverage

```powershell
$config = New-PesterConfiguration
$config.Run.Path = '.\Tests\'
$config.CodeCoverage.Enabled = $true
$config.CodeCoverage.Path = '.\SqlSizer-MSSQL\Shared\*.ps1'
$config.CodeCoverage.OutputPath = '.\Tests\coverage.xml'
$config.Output.Verbosity = 'Detailed'

Invoke-Pester -Configuration $config
```

### Generate test results

```powershell
# Generate NUnit XML for CI/CD integration
$config = New-PesterConfiguration
$config.Run.Path = '.\Tests\'
$config.TestResult.Enabled = $true
$config.TestResult.OutputPath = '.\Tests\testResults.xml'
$config.TestResult.OutputFormat = 'NUnitXml'

Invoke-Pester -Configuration $config
```

## Test Structure

- **TraversalHelpers.Tests.ps1** - Tests for pure helper functions
  - `Get-NewTraversalState` - State transition logic
  - `Get-TraversalConstraints` - Constraint retrieval
  - `Test-ShouldTraverseDirection` - Traversal decision logic
  - `Get-TopClause` - SQL TOP clause generation
  - `Get-ForeignKeyRelationships` - FK relationship extraction
  - `Get-TargetTableInfo` - Target table information
  - `Test-ShouldSkipTable` - Table skip logic
  - `Get-JoinConditions` - SQL JOIN generation
  - `Get-AdditionalWhereConditions` - WHERE clause generation

- **QueryBuilders.Tests.ps1** - Tests for SQL query builders
  - `New-GetNextOperationQuery` - BFS/DFS query generation
  - `New-MarkOperationInProgressQuery` - Operation marking
  - `New-CompleteOperationsQuery` - Operation completion
  - `New-GetIterationStatisticsQuery` - Statistics retrieval
  - `New-ExcludePendingQuery` - Pending exclusion (marks orphaned Pending as Exclude)
  - `New-CTETraversalQuery` - Main traversal CTE query (includes Pending→Include promotion)

## Writing New Tests

Follow this structure when adding new tests:

```powershell
Describe 'FunctionName' {
    BeforeAll {
        # Setup test data
    }

    Context 'Feature or scenario' {
        It 'Should do something specific' {
            # Arrange
            $input = # ... setup
            
            # Act
            $result = FunctionName -Parameter $input
            
            # Assert
            $result | Should -Be $expected
        }
    }
}
```

## Test Coverage Goals

- **Helper Functions**: 100% coverage (pure functions, easily testable)
- **Query Builders**: 95%+ coverage (SQL string generation)
- **Integration Functions**: 70%+ coverage (database-dependent)

## Continuous Integration

These tests are designed to run in CI/CD pipelines without requiring a database connection. They test:

1. **Logic correctness** - State transitions, decisions
2. **SQL generation** - Query structure, parameter injection
3. **Edge cases** - Null handling, empty collections
4. **Configuration** - Override behavior, constraints

## Troubleshooting

### Module not found

Ensure the module is properly imported:

```powershell
Import-Module .\SqlSizer-MSSQL\SqlSizer-MSSQL.psd1 -Force
```

### Type not found errors

Some tests may require type definitions from the main module. Ensure all type files are loaded:

```powershell
# Check if types are loaded
[TraversalState], [TraversalDirection] | ForEach-Object { $_.Name }
```

### Mock failures

If mocking fails, verify you're using Pester v5+ syntax:

```powershell
Get-Module Pester | Select-Object Version
```

## Contributing

When adding new functionality:

1. Write tests first (TDD approach)
2. Ensure all tests pass
3. Maintain or improve code coverage
4. Update this README if adding new test files
