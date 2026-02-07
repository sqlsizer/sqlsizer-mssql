# How SqlSizer-MSSQL Works

This document provides a comprehensive technical explanation of how SqlSizer-MSSQL finds and manages data subsets in SQL Server databases.

---

## Table of Contents

1. [Overview](#overview)
2. [Core Concepts](#core-concepts)
3. [Architecture](#architecture)
4. [The Subset Algorithm](#the-subset-algorithm)
5. [Data Structures](#data-structures)
6. [Session Management](#session-management)
7. [Workflow Examples](#workflow-examples)
8. [Performance Considerations](#performance-considerations)

---

## Overview

SqlSizer-MSSQL is a PowerShell module that extracts coherent subsets of data from SQL Server databases while maintaining **referential integrity**. It works by treating your database schema as a graph where:

- **Nodes** = Tables
- **Edges** = Foreign Key relationships

The algorithm traverses this graph starting from user-defined "seed" records and follows foreign key relationships to discover all related data that must be included to maintain database consistency.

```
┌─────────────────────────────────────────────────────────────────┐
│                    DATABASE AS A GRAPH                          │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│    ┌──────────┐         FK          ┌──────────┐               │
│    │  Orders  │ ──────────────────► │ Customer │               │
│    └──────────┘                      └──────────┘               │
│         │                                 ▲                     │
│         │ FK                              │ FK                  │
│         ▼                                 │                     │
│    ┌──────────┐         FK          ┌──────────┐               │
│    │ OrderItem│ ──────────────────► │ Product  │               │
│    └──────────┘                      └──────────┘               │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

---

## Core Concepts

### Traversal States

Every record in the subset search is assigned a **TraversalState** that determines how it's processed:

| State | Purpose | Behavior |
|-------|---------|----------|
| **Include** | Record should be in the subset | Follows all FK relationships to find dependencies |
| **Exclude** | Record should NOT be in subset | Stops traversal - does not propagate |
| **Pending** | Needs evaluation | Follows outgoing FKs; resolved after full traversal |
| **InboundOnly** | For removal operations | Only follows incoming FKs (finds dependent records) |

### Traversal Directions

Foreign key relationships can be followed in two directions:

```
┌─────────────────────────────────────────────────────────────────┐
│                    TRAVERSAL DIRECTIONS                         │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  OUTGOING (→)                       INCOMING (←)                │
│  "What does this record depend on?" "What depends on this?"    │
│                                                                 │
│  ┌─────────┐      FK      ┌─────────┐                          │
│  │  Order  │ ──────────►  │Customer │  Order DEPENDS ON Customer│
│  └─────────┘              └─────────┘                          │
│      ▲                         │                                │
│      │                         │                                │
│   Outgoing                  Incoming                            │
│   from Order               to Customer                          │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

- **Outgoing**: If Order has FK to Customer, traversing outgoing from Order finds Customer
- **Incoming**: If Order has FK to Customer, traversing incoming to Customer finds Orders

### FullSearch Mode

| Mode | Description |
|------|-------------|
| `FullSearch = $false` | Only follows **outgoing** FKs (finds dependencies) |
| `FullSearch = $true` | Follows **both** outgoing and incoming FKs (finds complete closure) |

---

## Architecture

### Module Structure

```
SqlSizer-MSSQL/
├── SqlSizer-MSSQL.psm1    # Module loader
├── SqlSizer-MSSQL.psd1    # Module manifest
├── Public/                 # Exported cmdlets (90+ functions)
│   ├── Find-Subset.ps1
│   ├── Find-RemovalSubset.ps1
│   ├── Initialize-StartSet.ps1
│   ├── Copy-DataFromSubset.ps1
│   └── ... (other cmdlets)
├── Shared/                 # Internal helper functions
│   └── Get-ColumnValue.ps1
└── Types/                  # Type definitions
    └── SqlSizer-MSSQL-Types.ps1
```

### Key Components

```
┌─────────────────────────────────────────────────────────────────┐
│                    COMPONENT ARCHITECTURE                        │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  ┌─────────────────┐     ┌─────────────────┐                   │
│  │   User Script   │────►│ SqlConnectionInfo│                   │
│  └─────────────────┘     └─────────────────┘                   │
│          │                       │                              │
│          ▼                       ▼                              │
│  ┌─────────────────┐     ┌─────────────────┐                   │
│  │ Get-DatabaseInfo│────►│  DatabaseInfo   │                   │
│  └─────────────────┘     └─────────────────┘                   │
│          │                       │                              │
│          ▼                       ▼                              │
│  ┌─────────────────┐     ┌─────────────────┐                   │
│  │Start-SqlSizerSession│─►│   Session ID    │                   │
│  └─────────────────┘     └─────────────────┘                   │
│          │                       │                              │
│          ▼                       ▼                              │
│  ┌─────────────────┐     ┌─────────────────┐                   │
│  │Initialize-StartSet│──►│ Processing Tables│                   │
│  └─────────────────┘     └─────────────────┘                   │
│          │                       │                              │
│          ▼                       ▼                              │
│  ┌─────────────────┐     ┌─────────────────┐                   │
│  │ Find-Subset-*   │────►│  Result Tables  │                   │
│  └─────────────────┘     └─────────────────┘                   │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

---

## The Subset Algorithm

### Phase 1: Initialization

1. **Create Session**: `Start-SqlSizerSession` creates a dedicated schema (`SqlSizer_{SessionId}`) with tracking tables
2. **Analyze Database**: `Get-DatabaseInfo` extracts complete metadata (tables, columns, FKs, indexes)
3. **Define Start Set**: `Initialize-StartSet` inserts seed records with initial states

```powershell
# Example: Start with 10 customers named 'John'
$query = New-Object -TypeName Query
$query.State = [TraversalState]::Include
$query.Schema = "Sales"
$query.Table = "Customer"
$query.KeyColumns = @('CustomerID')
$query.Where = "[$table].FirstName = 'John'"
$query.Top = 10

Initialize-StartSet -Database $db -Queries @($query) ...
```

### Phase 2: Graph Traversal

The algorithm uses **Breadth-First Search (BFS)** or **Depth-First Search (DFS)** to traverse the FK graph:

```
┌─────────────────────────────────────────────────────────────────┐
│                    BFS TRAVERSAL EXAMPLE                        │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  Iteration 0     Iteration 1       Iteration 2                 │
│  ───────────     ───────────       ───────────                 │
│                                                                 │
│  Customer ────► Order ──────────► OrderItem                    │
│  (seed)         (discovered)       (discovered)                │
│                       │                  │                      │
│                       ▼                  ▼                      │
│                   Product             Supplier                  │
│                   (discovered)        (discovered)              │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

**Algorithm Steps:**

1. **Select Operations**: Find unprocessed records grouped by (Table, State, Depth)
2. **Generate SQL**: Build CTE-based queries to find related records
3. **Execute & Insert**: Run queries, insert newly discovered records with appropriate state
4. **Mark Processed**: Update processed counts
5. **Repeat**: Continue until no unprocessed records remain

### Phase 3: State Resolution

After traversal completes, **Pending** records are resolved:

- Records reachable from **Include** records → become **Include**
- Records NOT reachable from **Include** → become **Exclude**

### SQL Generation (CTE-Based)

The algorithm generates efficient Common Table Expression (CTE) queries:

```sql
-- Example generated query: Find Customers referenced by Orders
WITH SourceRecords AS (
    SELECT Key0, Key1, ... FROM SqlSizer_Session123.Sales_Order
    WHERE Color = 2  -- Include state
    AND Iteration = 5
),
TargetRecords AS (
    SELECT 
        c.CustomerID AS Key0,
        2 AS Color,           -- Include state
        s.Key0 AS SourceKey0,
        6 AS Depth,
        42 AS FkId,
        6 AS Iteration
    FROM Sales.Customer c
    INNER JOIN Sales.Order o ON o.CustomerID = c.CustomerID
    INNER JOIN SourceRecords s ON s.Key0 = o.OrderID
    WHERE NOT EXISTS (
        SELECT 1 FROM SqlSizer_Session123.Sales_Customer t
        WHERE t.Key0 = c.CustomerID
    )
)
INSERT INTO SqlSizer_Session123.Sales_Customer
SELECT * FROM TargetRecords;
```

---

## Data Structures

### DatabaseInfo

Contains complete database metadata:

```powershell
class DatabaseInfo {
    [List[string]]$Schemas           # All schemas
    [List[TableInfo]]$Tables         # Table metadata
    [List[ViewInfo]]$Views           # View definitions
    [List[StoredProcedureInfo]]$StoredProcedures
    [int]$PrimaryKeyMaxSize          # Largest PK column count
    [string]$DatabaseSize            # Total size
}
```

### TableInfo

Represents a table with all its relationships:

```powershell
class TableInfo {
    [int]$Id
    [string]$SchemaName
    [string]$TableName
    [bool]$IsIdentity               # Has identity column
    [List[ColumnInfo]]$PrimaryKey   # PK columns
    [List[ColumnInfo]]$Columns      # All columns
    [List[TableFk]]$ForeignKeys     # Outgoing FKs
    [List[TableInfo]]$IsReferencedBy # Tables with FKs to this table
    [List[string]]$Triggers
    [TableStatistics]$Statistics
}
```

### TableFk (Foreign Key)

```powershell
class TableFk {
    [string]$Name              # FK constraint name
    [string]$FkSchema          # Source table schema
    [string]$FkTable           # Source table name
    [string]$Schema            # Referenced table schema
    [string]$Table             # Referenced table name
    [ForeignKeyRule]$DeleteRule
    [ForeignKeyRule]$UpdateRule
    [List[ColumnInfo]]$FkColumns   # Source columns
    [List[ColumnInfo]]$Columns     # Referenced columns
}
```

### Processing Tables

For each table with a primary key, SqlSizer creates a processing table:

```sql
-- Schema: SqlSizer_{SessionId}
-- Table: {SchemaName}_{TableName}
CREATE TABLE SqlSizer_Session123.Sales_Customer (
    Key0 INT,          -- PK column 1
    Key1 VARCHAR(50),  -- PK column 2 (if composite)
    Color INT,         -- TraversalState
    SourceKey0 INT,    -- Source record that led here
    Depth INT,         -- Distance from seed records
    FkId INT,          -- FK used to reach this record
    Iteration INT      -- When this was discovered
);
```

---

## Session Management

### Session Lifecycle

```
┌─────────────────────────────────────────────────────────────────┐
│                    SESSION LIFECYCLE                            │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  1. Start-SqlSizerSession                                       │
│     ├─ Creates SqlSizer_{SessionId} schema                     │
│     ├─ Creates processing tables for each table                │
│     └─ Creates tracking metadata tables                        │
│                                                                 │
│  2. Initialize-StartSet                                         │
│     └─ Inserts seed records into processing tables             │
│                                                                 │
│  3. Find-Subset                                      │
│     ├─ Traverses FK relationships                              │
│     ├─ Populates processing tables                             │
│     └─ Creates Result_* views                                  │
│                                                                 │
│  4. Get-SubsetTables / Copy-DataFromSubset                     │
│     └─ Reads results from processing tables                    │
│                                                                 │
│  5. Clear-SqlSizerSession                                       │
│     └─ Drops SqlSizer_{SessionId} schema and all objects       │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### Multiple Concurrent Sessions

SqlSizer supports multiple simultaneous sessions with isolated schemas:

```powershell
$session1 = Start-SqlSizerSession -Database $db ...  # Creates SqlSizer_abc123
$session2 = Start-SqlSizerSession -Database $db ...  # Creates SqlSizer_def456

# Sessions are completely independent
Find-Subset -SessionId $session1 ...
Find-Subset -SessionId $session2 ...

# Clean up individually or all at once
Clear-SqlSizerSession -SessionId $session1 ...
Clear-SqlSizerSessions -Database $db ...  # Clears all sessions
```

---

## Workflow Examples

### Example 1: Create Subset Database

```powershell
# 1. Setup connection
$connection = New-SqlConnectionInfo -Server "localhost" -Username "sa" -Password $pwd

# 2. Get database metadata
$info = Get-DatabaseInfo -Database "Production" -ConnectionInfo $connection

# 3. Start session
$sessionId = Start-SqlSizerSession -Database "Production" -ConnectionInfo $connection -DatabaseInfo $info

# 4. Define starting records
$query = New-Object Query
$query.State = [TraversalState]::Include
$query.Schema = "Sales"
$query.Table = "SalesOrder"
$query.KeyColumns = @('SalesOrderID')
$query.Top = 100

Initialize-StartSet -Database "Production" -Queries @($query) -SessionId $sessionId ...

# 5. Find complete subset
Find-Subset -Database "Production" -SessionId $sessionId `
    -DatabaseInfo $info -ConnectionInfo $connection -FullSearch $false

# 6. Create new database with subset
Copy-Database -Database "Production" -NewDatabase "Production_Subset" -ConnectionInfo $connection

$newInfo = Get-DatabaseInfo -Database "Production_Subset" -ConnectionInfo $connection
Disable-ForeignKeys -Database "Production_Subset" ...
Clear-Database -Database "Production_Subset" ...
Copy-DataFromSubset -Source "Production" -Destination "Production_Subset" -SessionId $sessionId ...
Enable-ForeignKeys -Database "Production_Subset" ...
Test-ForeignKeys -Database "Production_Subset" ...

# 7. Cleanup
Clear-SqlSizerSession -SessionId $sessionId ...
```

### Example 2: Remove Data Safely

```powershell
# Find all records that must be deleted to remove target records
Initialize-StartSet -Queries $removalQueries -SessionId $sessionId ...

Find-RemovalSubset -Database $db -SessionId $sessionId `
    -DatabaseInfo $info -ConnectionInfo $connection

# Delete in correct order (children before parents)
Remove-FoundSubsetFromDatabase -Database $db -SessionId $sessionId ...
```

---

## Performance Considerations

### Memory Efficiency

- **Server-side processing**: All heavy lifting done in SQL Server
- **Streaming results**: Results paged, not loaded entirely into memory
- **No record duplication**: Each record tracked once regardless of how many paths reach it

### Query Optimization

- **CTE-based queries**: Better query plan optimization
- **Query caching**: Reuses generated SQL for same table/state combinations
- **Batch processing**: Configurable `MaxBatchSize` for large datasets

### Best Practices

| Scenario | Recommendation |
|----------|----------------|
| Large databases | Use `MaxBatchSize` to limit memory per iteration |
| Complex schemas | Use `FullSearch = $false` initially, then expand |
| Slow performance | Check for missing indexes on FK columns |
| Azure SQL | Use `-IsSynapse $true` for Synapse-specific SQL |

### Index Recommendations

Ensure indexes exist on:
- All primary key columns (usually automatic)
- All foreign key columns (often missing!)
- Consider: `Install-ForeignKeyIndexes` cmdlet

---

## Appendix: Key Cmdlets Reference

| Cmdlet | Purpose |
|--------|---------|
| `New-SqlConnectionInfo` | Create database connection object |
| `Get-DatabaseInfo` | Extract database metadata |
| `Start-SqlSizerSession` | Initialize subsetting session |
| `Initialize-StartSet` | Define seed records |
| `Find-Subset` | Find complete subset |
| `Find-RemovalSubset` | Find deletion dependencies |
| `Get-SubsetTables` | List tables with subset data |
| `Copy-DataFromSubset` | Copy subset to another database |
| `Remove-FoundSubsetFromDatabase` | Delete subset records |
| `Clear-SqlSizerSession` | Cleanup session artifacts |
| `Test-ForeignKeys` | Validate referential integrity |

---

## Further Reading

- [Quick Start Guide](Quick-Start-Refactored-Algorithm.md)
- [Algorithm Comparison](Algorithm-Flow-Comparison.md) 
- [Migration Guide](MIGRATION-CHECKLIST.md)
- [Developer Reference](Developer-Quick-Reference.md)
