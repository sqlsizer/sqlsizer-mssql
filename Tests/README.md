# SqlSizer-MSSQL Tests

This directory contains unit tests and integration tests for the SqlSizer-MSSQL module using Pester.

## Prerequisites

```powershell
# Install Pester
Install-Module -Name Pester -Force -SkipPublisherCheck

# For integration tests: SQL Server instance (local or remote)
```

## Running Tests

### Quick Start

```powershell
# Unit tests only (no database required)
Invoke-Pester -Path .\Tests\ -Exclude *Integration*

# Integration tests (requires SQL Server)
.\Tests\Run-IntegrationTests.ps1 -DataSize Tiny
```

### Run all unit tests

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

- **Find-Subset.Integration.Tests.ps1** - End-to-end tests against real database
  - Basic FK traversal (single/multi-hop chains)
  - Diamond patterns (multiple FK paths to same table)
  - Self-referencing tables (hierarchies)
  - Circular references (Employee ↔ Department)
  - Deep chains (8-level FK chains)
  - Composite keys (2 and 3 column PKs)
  - Nullable FKs
  - FullSearch mode (incoming FK handling)
  - TraversalConfiguration (MaxDepth, Top, StateOverride)
  - IgnoredTables
  - BFS vs DFS comparison
  - MaxBatchSize chunking
  - Interactive mode
  - Edge cases (empty results, orphan tables, high fanout)
  - **End-to-End Database Subset Creation**
    - Creates subset from complex multi-table queries
    - Copies schema and data to new database
    - Verifies ALL foreign key constraints are satisfied
    - Drops test database on success

## Integration Tests

### Running Integration Tests

```powershell
# Use wrapper script (handles module loading)
.\Tests\Run-IntegrationTests.ps1 -DataSize Tiny

# Data size presets
.\Tests\Run-IntegrationTests.ps1 -DataSize Small   # ~2,000 rows
.\Tests\Run-IntegrationTests.ps1 -DataSize Medium  # ~20,000 rows
.\Tests\Run-IntegrationTests.ps1 -DataSize Large   # ~100,000 rows

# Custom SQL Server instance
.\Tests\Run-IntegrationTests.ps1 -Server "myserver\instance"

# Skip database setup (reuse existing data)
.\Tests\Run-IntegrationTests.ps1 -SkipDataSetup

# Filter tests by name pattern (supports wildcards)
.\Tests\Run-IntegrationTests.ps1 -Filter "*End-to-End*"
.\Tests\Run-IntegrationTests.ps1 -Filter "*Diamond*"
.\Tests\Run-IntegrationTests.ps1 -Filter "*self-ref*"
```

### Test Database

Integration tests create a `SqlSizerIntegrationTests` database with 32+ tables:

| Pattern | Tables |
|---------|--------|
| Simple FK chains | Products → SubCategories → Categories |
| Diamond pattern | Customers → Contacts (3 FK paths) |
| Self-reference | Categories, Employees (manager hierarchy) |
| Circular refs | Employees ↔ Departments |
| Deep chains | DeepChainA through DeepChainH (8 levels) |
| Composite keys | OrderDetails, ProductSuppliers, Inventory |
| Many-to-many | ProductSuppliers, TeamMembers |
| High fanout | HighFanoutParent → HighFanoutChildren |

The database is retained after tests for inspection.

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
