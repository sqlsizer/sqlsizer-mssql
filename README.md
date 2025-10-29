![logo](https://avatars.githubusercontent.com/u/96390582?s=100&v=4)
# sqlsizer-mssql

A PowerShell module for managing data in Microsoft SQL Server, Azure SQL databases and Azure Synapse Analytics SQL Pool.

## 🆕 Recent Updates (October 2025)

The refactored algorithms are now **production-ready** with comprehensive testing and documentation:
- ✅ **`Find-Subset-Refactored`** - 45% lower complexity, 50% less memory usage
- ✅ **150+ unit tests** - Fast, database-free testing
- ✅ **Modular architecture** - 16 testable helper functions
- ✅ **Enhanced docs** - 12+ new guides including migration path
- ✅ **100% backward compatible** - Drop-in replacement

**[See What's New →](docs/RECENT-CHANGES.md)** | **[Changelog →](CHANGELOG.md)** | **[Migration Guide →](docs/MIGRATION-CHECKLIST.md)**

## Core Features

The core feature is the ability to find a desired subset from a database with:

- **No limitation on database or subset size**
- **No limitation on primary key or foreign key size** (handles any number of columns and types)
- **Server-side processing** (Azure SQL, SQL Server, or Synapse)
- **Minimal memory usage** on PowerShell side

# Use Cases
**SqlSizer** can help with:
- Creating databases with subsets of data from production databases
- Copying data between databases or to Azure BLOB storage
- Comparing data across subsets or tables
- Removing data subsets efficiently (respecting FK constraints)
- Extracting/importing data (CSV, JSON)
- Managing database schemas, foreign keys, and triggers
- Testing data consistency and integrity
 
 
# How It Works

## Algorithm

SqlSizer uses **graph traversal** (BFS/DFS with multiple sources) to find subsets by following foreign key relationships.

**Key Features:**
- **Graph Traversal**: Explores FK relationships using Breadth-first search or Depth-first search
- **Explicit State Management**: Clear `TraversalState` enum (Include, Exclude, Pending, InboundOnly)
- **Two-Phase Processing**:
  - **Phase 1 (Traversal)**: Marks all reachable records by following FKs
  - **Phase 2 (Resolution)**: Resolves ambiguous Pending states based on complete graph
- **CTE-Based SQL**: Uses Common Table Expressions for optimized queries
- **No Record Duplication**: Efficient memory usage
- **Cycle Detection**: Handles circular FK relationships

**Performance:**
- ~50% less memory usage vs legacy implementation
- Clean CTE-based SQL with better optimization potential
- Predictable resource consumption

# Finding Subsets

**Steps:**
1. Define queries marking initial records (with Include/Exclude/Pending states)
2. Optionally configure traversal constraints (max depth, record limits)
3. Run `Find-Subset-Refactored`
4. Use the resulting subset

**Example:**
```powershell
# Define initial records
$query = New-Object -TypeName Query
$query.State = [TraversalState]::Include  # Include these records and dependencies
$query.Schema = "Person"
$query.Table = "Person"
$query.KeyColumns = @('BusinessEntityID')
$query.Where = "[`$table].FirstName = 'John'"
$query.Top = 10

# Initialize start set
Initialize-StartSet -Database $database -Queries @($query) -SessionId $sessionId ...

# Find subset
Find-Subset-Refactored -Database $database -SessionId $sessionId -FullSearch $false ...

# Get results
Get-SubsetTables -Database $database -SessionId $sessionId ...
```

# Finding Removal Subsets

When you need to delete records that are referenced by other records via foreign keys:

**Steps:**
1. Mark target rows for removal using `Initialize-StartSet`
2. Run `Find-RemovalSubset-Refactored` to find all dependent rows
3. Use `Remove-Subset` to delete in correct order

**Example:**
```powershell
# Mark rows to remove
Initialize-StartSet -SessionId $sessionId -Queries $removalQueries ...

# Find all rows that must be removed first (follows incoming FKs)
Find-RemovalSubset-Refactored -SessionId $sessionId -Database $database -MaxBatchSize 1000 ...

# Remove in correct order
Remove-Subset -SessionId $sessionId -Database $database ...
```

**Key Features:**
- CTE-based SQL queries
- Multi-level query caching
- Modular function design (7 focused functions)
- 57% simpler batch logic vs legacy implementation

## Traversal States

When defining queries, you specify how to traverse FK relationships using states:

| State | Color Enum | Description | Behavior |
|-------|-----------|-------------|----------|
| **Include** | `Color.Green` | Include in subset | Follows all FK relationships (outgoing & incoming based on FullSearch) |
| **Exclude** | `Color.Red` | Exclude from subset | Local exclusion only - does NOT traverse |
| **Pending** | `Color.Yellow` | Needs evaluation | Reached via incoming FK; resolved after full traversal |
| **InboundOnly** | `Color.Blue` | Removal mode | Only follows incoming FKs (for deletion operations) |

### State Transition Diagram

```
Initial Query States
┌─────────────────────────────────────────────────────────────┐
│  Include (Green)    Exclude (Red)    Pending (Yellow)       │
│       │                  │                  │                │
│       │                  │                  │                │
│       ▼                  ▼                  ▼                │
└───────┼──────────────────┼──────────────────┼────────────────┘
        │                  │                  │
        │                  │                  │
   Traversal Phase         │                  │
        │                  │                  │
        │                  │                  │
┌───────▼──────────────────▼──────────────────▼────────────────┐
│                                                                │
│  Include:                 Exclude:            Pending:         │
│  ├─ Outgoing FK → Include  (no traversal)     ├─ Outgoing FK → Pending │
│  └─ Incoming FK*→ Include                     └─ (no incoming FK traversal) │
│     (*if FullSearch)                                          │
│                                                                │
└────────────────────────────┬───────────────────────────────────┘
                             │
                    Resolution Phase
                             │
                             ▼
               ┌─────────────────────────┐
               │  Pending Records:       │
               │  - If reachable from    │
               │    Include → Include    │
               │  - Otherwise → Exclude  │
               └─────────────────────────┘
```

### Key Rules

1. **Include** → Follows FKs and includes dependencies
2. **Exclude** → Does NOT propagate to related records
3. **Pending** → Follows outgoing FKs with Pending state, resolved after traversal
4. **InboundOnly** → Special mode for finding deletion dependencies

![Diagram1](https://user-images.githubusercontent.com/115426/190853966-c51be4e3-0e24-41bf-bda8-1eabec89a6c5.png)

# Prerequisites

```powershell
Install-Module sqlserver -Scope CurrentUser
Install-Module dbatools -Scope CurrentUser
Install-Module Az -Scope CurrentUser

```

# Installation
Run the following to install SqlSizer-MSSQL from the  [PowerShell Gallery](https://www.powershellgallery.com/packages/SqlSizer-MSSQL).

To install for all users, remove the -Scope parameter and run in an elevated session:

```powershell
Install-Module SqlSizer-MSSQL -Scope CurrentUser
```

Before running scripts:

```powershell
Import-Module SqlSizer-MSSQL
```

# Examples

The repository contains comprehensive examples demonstrating various SqlSizer features:

- **`Examples/`** - Original examples using legacy `Find-Subset` and `Find-RemovalSubset` (still functional for backwards compatibility)
- **`ExamplesNew/`** - Modern examples organized by category (can use either algorithm - just change function name)

**Note:** To use the refactored algorithm in any example, simply replace `Find-Subset` with `Find-Subset-Refactored` and `Find-RemovalSubset` with `Find-RemovalSubset-Refactored`. All parameters remain the same.

## Sample 1 (on-premises SQL server)
```powershell
$server = "localhost"
$database = "AdventureWorks2019"
$username = "someuser"
$password = ConvertTo-SecureString -String "pass" -AsPlainText -Force

# Create connection
$connection = New-SqlConnectionInfo -Server $server -Username $username -Password $password

# Get database info
$info = Get-DatabaseInfo -Database $database -ConnectionInfo $connection

# Start session
$sessionId = Start-SqlSizerSession -Database $database -ConnectionInfo $connection -DatabaseInfo $info

# Define start set
# Query 1: 10 persons with first name = 'John'
$query = New-Object -TypeName Query
$query.State = [TraversalState]::Include  # Include records and their dependencies
$query.Schema = "Person"
$query.Table = "Person"
$query.KeyColumns = @('BusinessEntityID')
$query.Where = "[`$table].FirstName = 'John'"
$query.Top = 10
$query.OrderBy = "[`$table].LastName ASC"

# Init start set
Initialize-StartSet -Database $database -ConnectionInfo $connection -Queries @($query) -DatabaseInfo $info -SessionId $sessionId

# Find subset
Find-Subset-Refactored -Database $database -ConnectionInfo $connection -DatabaseInfo $info -FullSearch $false -UseDfs $false -SessionId $sessionId

# Get subset info
Get-SubsetTables -Database $database -Connection $connection -DatabaseInfo $info -SessionId $sessionId

# Create a new db with found subset of data
$newDatabase = "AdventureWorks2019_subset_John"
Copy-Database -Database $database -NewDatabase $newDatabase -ConnectionInfo $connection
$infoNew = Get-DatabaseInfo -Database $newDatabase -ConnectionInfo $connection

Disable-ForeignKeys -Database $newDatabase -ConnectionInfo $connection -DatabaseInfo $infoNew
Disable-AllTablesTriggers -Database $newDatabase -ConnectionInfo $connection -DatabaseInfo $infoNew
Clear-Database -Database $newDatabase -ConnectionInfo $connection -DatabaseInfo $infoNew
Copy-DataFromSubset -Source $database -Destination $newDatabase -ConnectionInfo $connection -DatabaseInfo $info -SessionId $sessionId
Enable-ForeignKeys -Database $newDatabase -ConnectionInfo $connection -DatabaseInfo $infoNew
Enable-AllTablesTriggers -Database $newDatabase -ConnectionInfo $connection -DatabaseInfo $infoNew
Format-Indexes -Database $newDatabase -ConnectionInfo $connection -DatabaseInfo $infoNew
Compress-Database -Database $newDatabase -ConnectionInfo $connection
Test-ForeignKeys -Database $newDatabase -ConnectionInfo $connection -DatabaseInfo $infoNew

$infoNew = Get-DatabaseInfo -Database $newDatabase -ConnectionInfo $connection -MeasureSize $true

Write-Verbose "Subset size: $($infoNew.DatabaseSize)"
$sum = 0
foreach ($table in $infoNew.Tables)
{
    $sum += $table.Statistics.Rows
}

Write-Verbose "Logical reads from db during subsetting: $($connection.Statistics.LogicalReads)"
Write-Verbose "Total rows: $($sum)"
Write-Verbose "==================="

Clear-SqlSizerSession -SessionId $sessionId -Database $database -ConnectionInfo $connection -DatabaseInfo $info

# end of script
```
## Sample 2 (Azure SQL database)

```powershell

## Example that shows how to subset a database in Azure

# Connection settings
$server = "sqlsizer.database.windows.net"
$database = "##db##"

Connect-AzAccount
$accessToken = (Get-AzAccessToken -ResourceUrl https://database.windows.net).Token

# Create connection
$connection = New-SqlConnectionInfo -Server $server -AccessToken $accessToken

# Get database info
$info = Get-DatabaseInfo -Database $database -ConnectionInfo $connection

# Start session
$sessionId = Start-SqlSizerSession -Database $database -ConnectionInfo $connection -DatabaseInfo $info

# Define start set - top 10 customers
$query = New-Object -TypeName Query
$query.State = [TraversalState]::Include  # Include records and their dependencies
$query.Schema = "SalesLT"
$query.Table = "Customer"
$query.KeyColumns = @('CustomerID')
$query.Top = 10

# Init start set
Initialize-StartSet -Database $database -ConnectionInfo $connection -Queries @($query) -DatabaseInfo $info -SessionId $sessionId

# Find subset
Find-Subset-Refactored -Database $database -ConnectionInfo $connection -DatabaseInfo $info -FullSearch $false -UseDfs $false -SessionId $sessionId

# Get subset info
Get-SubsetTables -Database $database -Connection $connection -DatabaseInfo $info -SessionId $sessionId
```

## Schema visualizations

Demo01:
https://sqlsizer.github.io/sqlsizer-mssql/Visualizations/Demo01/

Demo02:
https://sqlsizer.github.io/sqlsizer-mssql/Visualizations/Demo02/

Demo03:
https://sqlsizer.github.io/sqlsizer-mssql/Visualizations/Demo03/

# Backwards Compatibility

The original `Find-Subset` and `Find-RemovalSubset` functions are still available for backwards compatibility, but new projects should use the refactored versions.

**Migration is simple:** Just change the function name. All parameters and behavior remain the same.

| Original | Refactored | Key Benefits |
|----------|-----------|--------------|
| `Find-Subset` | `Find-Subset-Refactored` | 12% less code, 45% lower complexity, no record duplication |
| `Find-RemovalSubset` | `Find-RemovalSubset-Refactored` | 57% simpler batch logic, CTE-based SQL |

**See Migration Guide:** [Quick Start Guide](docs/Quick-Start-Refactored-Algorithm.md)

**Legacy Documentation:** For documentation on the original algorithms, see [`docs/Archive/`](docs/Archive/)

# Documentation

## Getting Started
- **[Quick Start Guide](docs/Quick-Start-Refactored-Algorithm.md)** - Get started with the refactored algorithm
- **[Algorithm Comparison](docs/Algorithm-Flow-Comparison.md)** - Visual flow diagrams
- **[Refactoring Summary](docs/REFACTORING-SUMMARY.md)** - What changed and why

## Advanced Topics
- **[ColorMap Compatibility](docs/ColorMap-Compatibility-Guide.md)** - Backwards compatibility with legacy code
- **[ColorMap Modernization](docs/ColorMap-Modernization-Guide.md)** - New TraversalConfiguration API
- **[Removal Guide](docs/Find-RemovalSubset-Refactoring-Guide.md)** - Removal algorithm improvements
- **[Technical Deep Dive](docs/Find-Subset-Refactoring-Guide.md)** - Detailed algorithm comparison

## Development
- **[Developer Reference](docs/Developer-Quick-Reference.md)** - Validation helpers, config builders
- **[Testing Guide](docs/Testing-Refactoring-Summary.md)** - Test architecture and running tests
- **[Code Improvements](docs/Code-Improvements-Summary.md)** - Code quality enhancements

# License
[![FOSSA Status](https://app.fossa.com/api/projects/git%2Bgithub.com%2Fsqlsizer%2Fsqlsizer-mssql.svg?type=large)](https://app.fossa.com/projects/git%2Bgithub.com%2Fsqlsizer%2Fsqlsizer-mssql?ref=badge_large)

