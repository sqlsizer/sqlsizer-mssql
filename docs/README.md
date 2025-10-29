# SqlSizer-MSSQL Documentation

This directory contains documentation for SqlSizer-MSSQL, focusing on the modern refactored algorithms.

## 🆕 What's New

**[Recent Changes - October 2025](RECENT-CHANGES.md)** - Comprehensive summary of recent improvements, including:
- Refactored algorithms (production-ready)
- 150+ unit tests with modular architecture
- Enhanced documentation (12+ new guides)
- Bug fixes and performance improvements

## Archive

Legacy documentation for the original algorithms has been moved to the `Archive/` directory. New projects should use the refactored algorithms documented here.

**See:** [`Archive/README.md`](Archive/README.md) for information on legacy algorithm documentation.

## Getting Started
- **[Quick Start Guide](Quick-Start-Refactored-Algorithm.md)** - Get started with the refactored algorithm
- **[Migration Checklist](MIGRATION-CHECKLIST.md)** - Step-by-step migration guide from legacy to refactored
- **[Recent Changes](RECENT-CHANGES.md)** - October 2025 updates and improvements

## Algorithm Documentation
- **[Algorithm Comparison](Algorithm-Flow-Comparison.md)** - Visual flow diagrams comparing algorithms
- **[Find-Subset Refactoring Guide](Find-Subset-Refactoring-Guide.md)** - Technical deep dive
- **[Find-RemovalSubset Refactoring Guide](Find-RemovalSubset-Refactoring-Guide.md)** - Removal algorithm improvements
- **[Architecture Diagram](Architecture-Diagram.md)** - System architecture overview

## Configuration & API
- **[ColorMap Compatibility](ColorMap-Compatibility-Guide.md)** - Backwards compatibility with legacy code
- **[ColorMap Modernization](ColorMap-Modernization-Guide.md)** - New TraversalConfiguration API
- **[Dynamic Keys Test Plan](QueryBuilders-Dynamic-Keys-TestPlan.md)** - N-column primary key support

## Development & Testing
- **[Developer Reference](Developer-Quick-Reference.md)** - Validation helpers, config builders
- **[Testing Guide](Testing-Quick-Reference.md)** - Test architecture and running tests
- **[Testing Summary](Testing-Refactoring-Summary.md)** - Test structure and coverage
- **[Code Improvements](Code-Improvements-Summary.md)** - Code quality enhancements

## Project Documentation
- **[Refactoring Complete](REFACTORING-COMPLETE.md)** - Summary of refactoring work
- **[Refactoring Summary](REFACTORING-SUMMARY.md)** - Executive summary of changes
- **[Modernization Summary](MODERNIZATION-SUMMARY.md)** - Modern API adoption guide
- **[Reorganization Summary](REORGANIZATION-SUMMARY.md)** - File structure changes
- **[Filename Improvements](FILENAME-IMPROVEMENTS.md)** - Naming convention updates
- **[Verification Checklist](VERIFICATION-CHECKLIST.md)** - Quality assurance checklist

### AdventureWorks2019

Examples using the AdventureWorks2019 sample database for SQL Server.

#### Subset
Examples demonstrating subset extraction and database operations:
- **01-Find-Multiple-Subsets.ps1** - Finding multiple subsets
- **02-Create-New-Database-With-Subset.ps1** - Create a new database with a subset of data
- **03-Create-New-Database-Alternative-Approach.ps1** - Alternative subset creation approach
- **04-Create-Subset-Without-Backup-Restore.ps1** - Subset without backup/restore
- **05-Interactive-Subset-Search.ps1** - Interactive subset search
- **06-Interactive-Search-Alternative.ps1** - Alternative interactive search
- **07-Create-Subset-In-New-Schema.ps1** - Create subset in new schema
- **08-Create-Subset-In-New-Table.ps1** - Create subset in new table
- **09-Two-Phase-Search-Strategy.ps1** - Two-phase search strategy

#### Removal
Examples for data removal operations:
- **01-Basic-Data-Removal.ps1** - Basic data removal
- **02-Data-Removal-Alternative-Method.ps1** - Alternative removal approach
- **03-Data-Removal-Advanced.ps1** - Advanced removal techniques
- **04-Data-Removal-Complex-Scenario.ps1** - Complex removal scenarios
- **05-Iterative-Removal-Slow-Method.ps1** - Iterative removal (slower approach)
- **06-Iterative-Removal-Alternative-1.ps1** - Second iterative approach
- **07-Iterative-Removal-Alternative-2.ps1** - Third iterative approach
- **08-Iterative-Removal-Alternative-3.ps1** - Fourth iterative approach

#### Schema
Schema management examples:
- **01-Remove-Database-Schema.ps1** - Remove schema from database
- **02-Copy-Database-Schema.ps1** - Copy database schema

#### Comparison
Data comparison examples:
- **01-Compare-Database-Subsets.ps1** - Compare different subsets
- **02-Compare-Table-Data.ps1** - Compare table data

#### JSON
JSON import/export examples:
- **01-Import-Export-JSON-Data.ps1** - Import and export data using JSON
- **02-Export-JSON-Schema.ps1** - Export and work with JSON schema

#### Visualization
Visual representation examples using modern TraversalConfiguration API:
- **01-Generate-Relationship-Color-Map.ps1** - Generate traversal configurations with constraints
- **02-Alternative-Color-Map-Approach.ps1** - Alternative traversal configuration approach

#### Maintenance
Database maintenance and integrity examples:
- **01-Install-Indexes-And-Foreign-Keys.ps1** - Install indexes and foreign keys
- **02-Run-Data-Integrity-Checks.ps1** - Run integrity checks on data
- **03-Run-Test-Queries.ps1** - Test query examples
- **04-Manage-Database-Triggers.ps1** - Work with database triggers

### Azure

Examples for Azure cloud platforms.

#### AzureSQL
Examples for Azure SQL Database:
- **01-Basic-Azure-SQL-Operations.ps1** - Basic Azure SQL operations
- **02-Advanced-Azure-SQL-Features.ps1** - Advanced Azure SQL features
- **03-Complex-Azure-SQL-Scenarios.ps1** - Complex Azure SQL scenarios

#### Synapse
Examples for Azure Synapse Analytics SQL Pool (to be added).

## Getting Started

1. Each example is self-contained and includes comments explaining the workflow
2. Update connection strings and database names as needed for your environment
3. Examples assume the SqlSizer-MSSQL module is installed and imported
4. Most examples require appropriate database permissions
5. **Note**: Examples use the modern `TraversalConfiguration` API instead of legacy `ColorMap` classes

## Modern API Usage

All examples in this directory use the modern traversal configuration API:

- **TraversalConfiguration** instead of `ColorMap`
- **TraversalRule** instead of `ColorItem`
- **StateOverride** instead of `ForcedColor`
- **TraversalConstraints** instead of `Condition`
- **TraversalState enum** instead of `Color enum`

For legacy `ColorMap` examples and backwards compatibility information, see the [ColorMap Modernization Guide](../docs/ColorMap-Modernization-Guide.md).

## Prerequisites

- PowerShell 5.1 or later
- SqlSizer-MSSQL module installed
- SQL Server or Azure SQL Database access
- Sample databases (AdventureWorks2019, AdventureWorksLT)

## Usage

```powershell
# Import the module
Import-Module SqlSizer-MSSQL

# Navigate to the desired example category
cd ExamplesNew\AdventureWorks2019\Subset

# Run an example
.\02-Create-New-Database-With-Subset.ps1
```

## Notes

- These examples are designed to demonstrate specific features
- Always test in a non-production environment first
- Review and modify connection strings before running
- Some examples may take significant time to run on large databases

## Related Documentation

- [Main Examples Directory](../Examples/) - Original examples directory
- [SqlSizer-MSSQL Documentation](../docs/)
- [Testing Documentation](../Tests/README.md)
