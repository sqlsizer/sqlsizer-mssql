# How SqlSizer-MSSQL Works

> **TL;DR**: SqlSizer finds all data connected to your "seed" records by following foreign key relationships, ensuring your subset remains referentially consistent.

---

## Table of Contents

1. [Quick Start (5-Minute Guide)](#quick-start-5-minute-guide)
2. [Overview](#overview)
3. [Core Concepts](#core-concepts)
4. [Architecture](#architecture)
5. [The Subset Algorithm](#the-subset-algorithm)
6. [Data Structures](#data-structures)
7. [Session Management](#session-management)
8. [Common Scenarios](#common-scenarios)
9. [Workflow Examples](#workflow-examples)
10. [Performance Considerations](#performance-considerations)
11. [Troubleshooting](#troubleshooting)
12. [Glossary](#glossary)

---

## Quick Start (5-Minute Guide)

```powershell
# 1. Connect to your database
$connection = New-SqlConnectionInfo -Server "localhost" -Username "sa" -Password $securePassword

# 2. Analyze database structure
$info = Get-DatabaseInfo -Database "MyDatabase" -ConnectionInfo $connection

# 3. Create a session
$sessionId = Start-SqlSizerSession -Database "MyDatabase" -ConnectionInfo $connection -DatabaseInfo $info

# 4. Define your seed records
$query = New-Object -TypeName Query2
$query.State = [TraversalState]::Include
$query.Schema = "Sales"
$query.Table = "Customer"
$query.KeyColumns = @('CustomerID')
$query.Where = "[`$table].CustomerID = 123"

# 5. Initialize and find subset
Initialize-StartSet -Database "MyDatabase" -Queries @($query) -DatabaseInfo $info -SessionId $sessionId -ConnectionInfo $connection
Find-Subset -Database "MyDatabase" -SessionId $sessionId -DatabaseInfo $info -ConnectionInfo $connection

# 6. View results
Get-SubsetTables -Database "MyDatabase" -SessionId $sessionId -DatabaseInfo $info -ConnectionInfo $connection | Format-Table

# 7. Cleanup when done
Clear-SqlSizerSession -Database "MyDatabase" -SessionId $sessionId -ConnectionInfo $connection
```

**What just happened?**
1. You told SqlSizer to start with Customer #123
2. It found all Orders for that Customer
3. It found all OrderItems for those Orders
4. It found all Products referenced by those OrderItems
5. ...and so on, until all related data was discovered

---

## Overview

SqlSizer-MSSQL is a PowerShell module that extracts coherent subsets of data from SQL Server databases while maintaining **referential integrity**. It treats your database schema as a directed graph:

| Graph Element | Database Equivalent |
|---------------|---------------------|
| **Node** | Table |
| **Edge** | Foreign Key relationship |
| **Direction** | FK points from child → parent |

The algorithm traverses this graph starting from user-defined "seed" records and follows foreign key relationships to discover all related data that must be included to maintain database consistency.

```
┌─────────────────────────────────────────────────────────────────────────┐
│                       DATABASE AS A GRAPH                               │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                         │
│     ┌───────────┐                            ┌───────────┐              │
│     │ OrderItem │────── FK (ProductID) ────►│  Product  │              │
│     └───────────┘                            └───────────┘              │
│           │                                        ▲                    │
│           │                                        │                    │
│      FK (OrderID)                          FK (SupplierID)              │
│           │                                        │                    │
│           ▼                                        │                    │
│     ┌───────────┐                            ┌───────────┐              │
│     │   Order   │                            │ Supplier  │              │
│     └───────────┘                            └───────────┘              │
│           │                                                             │
│      FK (CustomerID)                                                    │
│           │                                                             │
│           ▼                                                             │
│     ┌───────────┐                                                       │
│     │ Customer  │  ◄─── SEED RECORD (where traversal starts)          │
│     └───────────┘                                                       │
│                                                                         │
│  Arrow direction: Child table ──► Parent table (FK direction)          │
└─────────────────────────────────────────────────────────────────────────┘
```

### Why Use SqlSizer?

| Problem | SqlSizer Solution |
|---------|-------------------|
| Need test data from production | Extract consistent subset with `Find-Subset` |
| Deleting records breaks FK constraints | Use `Find-RemovalSubset` to find deletion order |
| Moving data between databases | Export subset with `Copy-DataFromSubset` |
| Need to understand data relationships | Visualize with subset analysis tools |

---

## Core Concepts

### Traversal States

Every record discovered during subset search is assigned a **TraversalState** that controls its inclusion and how it propagates:

```
┌─────────────────────────────────────────────────────────────────────────┐
│                      TRAVERSAL STATE FLOW                               │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                         │
│   ┌──────────┐                     ┌──────────┐                        │
│   │  Seed    │  ──►  Traversal  ──►│ Include  │ ══► In final subset    │
│   │ Records  │        Start        └──────────┘                        │
│   └──────────┘                           │                             │
│        │                                 │ follows FKs                 │
│        │                                 ▼                             │
│        │            ┌──────────────────────────────────┐               │
│        │            │   Discovered Related Records     │               │
│        │            └──────────────────────────────────┘               │
│        │                   │              │              │             │
│        │                   ▼              ▼              ▼             │
│        │            ┌──────────┐  ┌───────────┐  ┌─────────────┐       │
│        │            │ Include  │  │  Pending  │  │ InboundOnly │       │
│        │            │ (keep)   │  │ (resolve) │  │ (incoming)  │       │
│        │            └──────────┘  └───────────┘  └─────────────┘       │
│        │                                 │                             │
│        │                       ┌─────────┴─────────┐                   │
│        │                       ▼                   ▼                   │
│        │                 ┌──────────┐       ┌──────────┐               │
│        └──► Explicit ──► │ Exclude  │       │ Include  │               │
│              exclusion   │ (skip)   │       │ (keep)   │               │
│                          └──────────┘       └──────────┘               │
│                               ║                   ║                    │
│                               ▼                   ▼                    │
│                         NOT in subset       IN final subset            │
│                                                                         │
└─────────────────────────────────────────────────────────────────────────┘
```

| State | Code | When Used | FK Traversal | Final Outcome |
|-------|------|-----------|--------------|---------------|
| **Include** | `[TraversalState]::Include` | Must be in subset | Outgoing + Incoming (if FullSearch) | ✅ In subset |
| **Exclude** | `[TraversalState]::Exclude` | Must NOT be in subset | None - stops here | ❌ Not in subset |
| **Pending** | `[TraversalState]::Pending` | Discovered via incoming FKs (non-full search) | Outgoing only | Promoted to Include during traversal if reachable via Include path, otherwise Exclude |
| **InboundOnly** | `[TraversalState]::InboundOnly` | For removal operations | Incoming only | Finds dependents |

### Traversal Directions

Foreign key relationships can be traversed in two directions, each answering different questions:

```
┌─────────────────────────────────────────────────────────────────────────┐
│                       TRAVERSAL DIRECTIONS                              │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                         │
│  ══════════════════════════════════════════════════════════════════    │
│  OUTGOING TRAVERSAL                                                     │
│  Question: "What does this record DEPEND ON?"                           │
│  Use: Finding all parent/referenced data                                │
│  ══════════════════════════════════════════════════════════════════    │
│                                                                         │
│     ┌───────────┐              FK               ┌───────────┐          │
│     │   Order   │ ═══════════════════════════► │ Customer  │          │
│     │ (source)  │         CustomerID            │ (target)  │          │
│     └───────────┘                               └───────────┘          │
│                                                                         │
│     "Order depends on Customer" → traversing outgoing finds Customer   │
│                                                                         │
│  ══════════════════════════════════════════════════════════════════    │
│  INCOMING TRAVERSAL                                                     │
│  Question: "What DEPENDS ON this record?"                               │
│  Use: Finding all child/dependent data (for deletion or full closure)  │
│  ══════════════════════════════════════════════════════════════════    │
│                                                                         │
│     ┌───────────┐              FK               ┌───────────┐          │
│     │   Order   │ ◄═══════════════════════════ │ Customer  │          │
│     │ (target)  │         CustomerID            │ (source)  │          │
│     └───────────┘                               └───────────┘          │
│                                                                         │
│     "Orders depend on Customer" → traversing incoming finds Orders     │
│                                                                         │
└─────────────────────────────────────────────────────────────────────────┘
```

### FullSearch Mode

The `FullSearch` parameter controls which directions are followed:

| Parameter | Outgoing FKs | Incoming FKs | Use Case |
|-----------|--------------|--------------|----------|
| `$false` (default) | ✅ Yes | ❌ No | Finding dependencies of seed records |
| `$true` | ✅ Yes | ✅ Yes | Finding complete data closure (both directions) |

**When to use FullSearch:**
- `$false` - "Give me this Customer and everything they need" (Orders, Products referenced)
- `$true` - "Give me this Customer and everything connected" (includes their Orders, OrderItems, etc.)

---

## Architecture

### Module Structure

```
SqlSizer-MSSQL/
├── SqlSizer-MSSQL.psm1      # Module loader
├── SqlSizer-MSSQL.psd1      # Module manifest
├── Public/                   # 90+ exported cmdlets
│   ├── Find-Subset.ps1           # Core algorithm
│   ├── Find-RemovalSubset.ps1    # Deletion dependency finder
│   ├── Initialize-StartSet.ps1   # Seed record setup
│   ├── Get-SubsetTables.ps1      # Result retrieval
│   ├── Copy-DataFromSubset.ps1   # Data export
│   └── ... (other cmdlets)
├── Shared/                   # Internal helpers
│   └── Get-ColumnValue.ps1       # Value handling utilities
└── Types/                    # Type definitions
    └── SqlSizer-MSSQL-Types.ps1  # Classes and enums
```

### Data Flow Through Components

```
┌─────────────────────────────────────────────────────────────────────────┐
│                        SQLSIZER WORKFLOW                                │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                         │
│  ┌─────────────────────────────────────────────────────────────────┐   │
│  │  STEP 1: SETUP                                                   │   │
│  ├─────────────────────────────────────────────────────────────────┤   │
│  │                                                                  │   │
│  │  New-SqlConnectionInfo ──► SqlConnectionInfo object             │   │
│  │           │                                                      │   │
│  │           ▼                                                      │   │
│  │  Get-DatabaseInfo ──────► DatabaseInfo (tables, FKs, columns)   │   │
│  │           │                                                      │   │
│  │           ▼                                                      │   │
│  │  Start-SqlSizerSession ─► SessionId + Processing Tables         │   │
│  │                                                                  │   │
│  └─────────────────────────────────────────────────────────────────┘   │
│                              │                                          │
│                              ▼                                          │
│  ┌─────────────────────────────────────────────────────────────────┐   │
│  │  STEP 2: DEFINE SEED RECORDS                                    │   │
│  ├─────────────────────────────────────────────────────────────────┤   │
│  │                                                                  │   │
│  │  Query2 object(s) ─────► Initialize-StartSet                    │   │
│  │   • State (Include/Exclude/Pending)                             │   │
│  │   • Schema + Table                                               │   │
│  │   • Where clause                                                 │   │
│  │   • Top N limit                                                  │   │
│  │                                                                  │   │
│  └─────────────────────────────────────────────────────────────────┘   │
│                              │                                          │
│                              ▼                                          │
│  ┌─────────────────────────────────────────────────────────────────┐   │
│  │  STEP 3: TRAVERSAL                                              │   │
│  ├─────────────────────────────────────────────────────────────────┤   │
│  │                                                                  │   │
│  │  Find-Subset ──────────► Graph traversal (BFS/DFS)              │   │
│  │   • Follows FK relationships                                    │   │
│  │   • Populates processing tables                                 │   │
│  │   • Resolves Pending states                                     │   │
│  │                                                                  │   │
│  └─────────────────────────────────────────────────────────────────┘   │
│                              │                                          │
│                              ▼                                          │
│  ┌─────────────────────────────────────────────────────────────────┐   │
│  │  STEP 4: RESULTS                                                │   │
│  ├─────────────────────────────────────────────────────────────────┤   │
│  │                                                                  │   │
│  │  Get-SubsetTables ─────► List of tables with row counts         │   │
│  │  Get-SubsetTableRows ──► Actual row data                        │   │
│  │  Copy-DataFromSubset ──► Export to target database              │   │
│  │  Get-SubsetTableJson ──► Export as JSON                         │   │
│  │                                                                  │   │
│  └─────────────────────────────────────────────────────────────────┘   │
│                              │                                          │
│                              ▼                                          │
│  ┌─────────────────────────────────────────────────────────────────┐   │
│  │  STEP 5: CLEANUP                                                │   │
│  ├─────────────────────────────────────────────────────────────────┤   │
│  │                                                                  │   │
│  │  Clear-SqlSizerSession ► Removes session schema and tables      │   │
│  │                                                                  │   │
│  └─────────────────────────────────────────────────────────────────┘   │
│                                                                         │
└─────────────────────────────────────────────────────────────────────────┘
```

### Processing Tables (In-Database Storage)

For each table with a primary key, SqlSizer creates a **processing table** to track discovered records:

```sql
-- Created in schema: SqlSizer_{SessionId}
-- One table per source table: {SchemaName}_{TableName}

CREATE TABLE SqlSizer_abc123.Sales_Customer (
    Key0 INT,           -- First PK column value
    Key1 VARCHAR(50),   -- Second PK column value (if composite)
    -- ... more KeyN columns for larger PKs
    
    Color INT,          -- TraversalState (1=Include, 2=Exclude, 3=Pending, 4=InboundOnly)
    SourceKey0 INT,     -- Source record that led to this one
    Depth INT,          -- Hops from seed records
    FkId INT,           -- Which FK relationship was followed
    Iteration INT       -- When this was discovered
);
```

This design enables:
- **Server-side processing**: Heavy lifting done in SQL Server
- **No record duplication**: Each record tracked once regardless of paths
- **Audit trail**: Know how each record was discovered

---

## The Subset Algorithm

### Overview: Three Phases

```
┌─────────────────────────────────────────────────────────────────────────┐
│                     ALGORITHM PHASES                                    │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                         │
│   PHASE 1              PHASE 2                   PHASE 3               │
│   ─────────            ─────────                 ─────────             │
│   Initialize           Traverse                  Resolve               │
│                                                                         │
│   ┌─────────┐     ┌──────────────────┐     ┌───────────────┐          │
│   │  Seed   │ ──► │   Follow FKs     │ ──► │   Resolve     │          │
│   │ Records │     │  (BFS or DFS)    │     │   Pending     │          │
│   └─────────┘     └──────────────────┘     └───────────────┘          │
│                           │                        │                   │
│   Duration: Fast          │ Duration: Main work    │ Duration: Fast   │
│   (~seconds)              │ (~seconds to hours)    │ (~seconds)       │
│                           │                        │                   │
│                           ▼                        ▼                   │
│                   ┌──────────────────┐     ┌───────────────┐          │
│                   │ Processing tables │     │ Final subset  │          │
│                   │ populated         │     │ ready         │          │
│                   └──────────────────┘     └───────────────┘          │
│                                                                         │
└─────────────────────────────────────────────────────────────────────────┘
```

### Phase 1: Initialization

| Step | Function | What Happens |
|------|----------|--------------|
| 1 | `Start-SqlSizerSession` | Creates `SqlSizer_{SessionId}` schema with processing tables |
| 2 | `Get-DatabaseInfo` | Extracts complete metadata (tables, columns, FKs, indexes) |
| 3 | `Initialize-StartSet` | Inserts seed records with initial states |

```powershell
# Example: Start with 10 customers named 'John'
$query = New-Object -TypeName Query2
$query.State = [TraversalState]::Include
$query.Schema = "Sales"
$query.Table = "Customer"
$query.KeyColumns = @('CustomerID')
$query.Where = "[`$table].FirstName = 'John'"
$query.Top = 10

Initialize-StartSet -Database $db -Queries @($query) -SessionId $sessionId `
    -DatabaseInfo $info -ConnectionInfo $connection
```

### Phase 2: Graph Traversal

The algorithm uses **Breadth-First Search (BFS)** by default, or optionally **Depth-First Search (DFS)**:

```
┌─────────────────────────────────────────────────────────────────────────┐
│           BFS TRAVERSAL EXAMPLE (FullSearch = $true)                    │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                         │
│  Depth 0           Depth 1             Depth 2           Depth 3       │
│  ═══════           ═══════             ═══════           ═══════       │
│                                                                         │
│  ┌──────────┐                                                          │
│  │ Customer │ ←── SEED RECORD                                          │
│  │  (John)  │                                                          │
│  └──────────┘                                                          │
│       │                                                                 │
│       │ incoming FK (CustomerID)                                       │
│       ▼                                                                 │
│  ┌──────────┐                                                          │
│  │  Order   │ ←── discovered via incoming FK                           │
│  │ (3 rows) │                                                          │
│  └──────────┘                                                          │
│       │                                                                 │
│       ├─── incoming FK ──► ┌───────────┐                               │
│       │                    │ OrderItem │ ←── John's order items        │
│       │                    │ (12 rows) │                               │
│       │                    └───────────┘                               │
│       │                          │                                     │
│       │                          │ outgoing FK (ProductID)             │
│       │                          ▼                                     │
│       │                    ┌───────────┐                               │
│       │                    │  Product  │ ←── products ordered          │
│       │                    │ (8 rows)  │                               │
│       │                    └───────────┘                               │
│       │                                                                 │
│       └─── outgoing FK ──► ┌───────────┐                               │
│                            │ Salesman  │ ←── who sold these            │
│                            │ (2 rows)  │                               │
│                            └───────────┘                               │
│                                                                         │
└─────────────────────────────────────────────────────────────────────────┘
```

**Algorithm Loop:**

```
WHILE unprocessed records exist:
    1. SELECT next operation (table + state + depth)
    2. FOR EACH foreign key relationship:
        a. GENERATE CTE query
        b. EXECUTE query to find related records
        c. INSERT newly discovered records (skip duplicates)
    3. MARK records as processed
    4. INCREMENT iteration counter
```

**BFS vs DFS:**
| Algorithm | Parameter | Behavior | Best For |
|-----------|-----------|----------|----------|
| **BFS** | `UseDfs = $false` | Processes all records at depth N before depth N+1 | Even discovery, predictable |
| **DFS** | `UseDfs = $true` | Follows one path deeply before backtracking | Memory efficiency, early results |

### Phase 3: State Resolution

After traversal, any remaining **Pending** records are marked as **Exclude**:

```
┌─────────────────────────────────────────────────────────────────────────┐
│                     PENDING STATE HANDLING                              │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                         │
│   DURING TRAVERSAL (handled automatically):                            │
│   ┌─────────┐                                                          │
│   │ Include │                                                          │
│   └────┬────┘                                                          │
│        │ incoming FK (non-full search)                                 │
│        ▼                                                               │
│   ┌─────────┐     outgoing FK      ┌─────────┐                        │
│   │ Pending │ ─────────────────►   │ Pending │                        │
│   └─────────┘                      └─────────┘                        │
│        │                                │                              │
│        │ If later found via Include path, promoted to Include         │
│        ▼                                                               │
│   ┌─────────┐                                                          │
│   │ Include │ (promoted during traversal)                              │
│   └─────────┘                                                          │
│                                                                         │
│   AFTER TRAVERSAL (final cleanup):                                     │
│   - Any remaining Pending records → marked as Exclude                  │
│   - These are orphaned dependents not reachable via Include paths     │
│                                                                         │
│   ┌─────────┐                                                          │
│   │ Exclude │ (was Pending, never connected to Include)                │
│   └─────────┘                                                          │
│                                                                         │
│   KEY INSIGHT:                                                          │
│   Pending→Include promotion happens DURING traversal, not after.       │
│   When a record already exists as Pending and is discovered again via  │
│   an Include path, it is immediately promoted to Include.              │
│                                                                         │
└─────────────────────────────────────────────────────────────────────────┘
```

### SQL Generation (CTE-Based)

The algorithm generates efficient **Common Table Expression (CTE)** queries for each traversal:

```sql
-- Example: Find Customers referenced by Orders (outgoing FK traversal)
WITH SourceRecords AS (
    -- Get unprocessed Order records marked Include at current iteration
    SELECT Key0, Key1 
    FROM SqlSizer_Session123.Sales_Order
    WHERE Color = 1          -- Include state
      AND Iteration = 5      -- Current iteration
),
TargetRecords AS (
    -- Find referenced Customer records
    SELECT 
        c.CustomerID AS Key0,
        1 AS Color,           -- Include state for new records
        s.Key0 AS SourceKey0, -- Trace back to source
        6 AS Depth,           -- One deeper than source
        42 AS FkId,           -- FK constraint ID
        6 AS Iteration        -- Current iteration
    FROM Sales.Customer c
    INNER JOIN Sales.Order o 
        ON o.CustomerID = c.CustomerID
    INNER JOIN SourceRecords s 
        ON s.Key0 = o.OrderID
    WHERE NOT EXISTS (
        -- Skip already-discovered records
        SELECT 1 
        FROM SqlSizer_Session123.Sales_Customer t
        WHERE t.Key0 = c.CustomerID
    )
)
INSERT INTO SqlSizer_Session123.Sales_Customer
SELECT * FROM TargetRecords;
```

**Why CTEs?**
- Readable and maintainable SQL
- Optimizable by SQL Server query planner
- Clear separation of source selection and target insertion

---

## Data Structures

### DatabaseInfo

Contains complete database metadata:

```powershell
class DatabaseInfo {
    [List[string]]$Schemas           # All schemas in the database
    [List[TableInfo]]$Tables         # Table metadata (columns, FKs, etc.)
    [List[ViewInfo]]$Views           # View definitions
    [List[StoredProcedureInfo]]$StoredProcedures
    [int]$PrimaryKeyMaxSize          # Largest PK column count (for sizing processing tables)
    [string]$DatabaseSize            # Total database size
}
```

### TableInfo

Represents a table with all its relationships:

```powershell
class TableInfo {
    [int]$Id                         # Internal table ID
    [string]$SchemaName              # e.g., "Sales"
    [string]$TableName               # e.g., "Customer"
    [bool]$IsIdentity                # Has IDENTITY column
    [List[ColumnInfo]]$PrimaryKey    # Primary key columns
    [List[ColumnInfo]]$Columns       # All columns
    [List[TableFk]]$ForeignKeys      # Outgoing FKs (this table → other tables)
    [List[TableInfo]]$IsReferencedBy # Other tables that reference this table
    [List[string]]$Triggers          # Trigger names
    [TableStatistics]$Statistics     # Row count, size info
}
```

### TableFk (Foreign Key)

```powershell
class TableFk {
    [string]$Name              # FK constraint name (e.g., "FK_Order_Customer")
    [string]$FkSchema          # Source table schema (where FK is defined)
    [string]$FkTable           # Source table name
    [string]$Schema            # Referenced/target table schema
    [string]$Table             # Referenced/target table name
    [ForeignKeyRule]$DeleteRule  # CASCADE, SET NULL, etc.
    [ForeignKeyRule]$UpdateRule
    [List[ColumnInfo]]$FkColumns   # Source columns (e.g., CustomerID in Order)
    [List[ColumnInfo]]$Columns     # Referenced columns (e.g., CustomerID in Customer)
}
```

### Query2 (Seed Record Definition)

```powershell
class Query2 {
    [TraversalState]$State     # Include, Exclude, Pending, or InboundOnly
    [string]$Schema            # Target table schema
    [string]$Table             # Target table name
    [string[]]$KeyColumns      # PK column names for identification
    [string]$Where             # Filter clause (use $table as table alias)
    [int]$Top                  # Limit number of records (-1 = no limit)
    [string]$OrderBy           # Optional ordering
}
```

---

## Session Management

### Session Lifecycle

```
┌─────────────────────────────────────────────────────────────────────────┐
│                       SESSION LIFECYCLE                                 │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                         │
│  ┌─────────────────────────────────────────────────────────────────┐   │
│  │ 1. Start-SqlSizerSession                                        │   │
│  │    • Creates SqlSizer_{SessionId} schema                        │   │
│  │    • Creates processing tables for each table with PK           │   │
│  │    • Creates tracking/metadata tables                           │   │
│  │    └─► Returns: SessionId (string)                              │   │
│  └─────────────────────────────────────────────────────────────────┘   │
│                              │                                          │
│                              ▼                                          │
│  ┌─────────────────────────────────────────────────────────────────┐   │
│  │ 2. Initialize-StartSet                                          │   │
│  │    • Inserts seed records into processing tables                │   │
│  │    • Assigns initial TraversalState and Depth 0                 │   │
│  └─────────────────────────────────────────────────────────────────┘   │
│                              │                                          │
│                              ▼                                          │
│  ┌─────────────────────────────────────────────────────────────────┐   │
│  │ 3. Find-Subset / Find-RemovalSubset                             │   │
│  │    • Traverses FK relationships                                 │   │
│  │    • Populates processing tables with discovered records        │   │
│  │    • Resolves Pending states                                    │   │
│  └─────────────────────────────────────────────────────────────────┘   │
│                              │                                          │
│                              ▼                                          │
│  ┌─────────────────────────────────────────────────────────────────┐   │
│  │ 4. Result Operations                                            │   │
│  │    • Get-SubsetTables → List tables with row counts             │   │
│  │    • Get-SubsetTableRows → Retrieve actual data                 │   │
│  │    • Copy-DataFromSubset → Export to another database           │   │
│  │    • Get-SubsetTableJson/Csv → Export to files                  │   │
│  └─────────────────────────────────────────────────────────────────┘   │
│                              │                                          │
│                              ▼                                          │
│  ┌─────────────────────────────────────────────────────────────────┐   │
│  │ 5. Clear-SqlSizerSession                                        │   │
│  │    • Drops SqlSizer_{SessionId} schema                          │   │
│  │    • Removes all processing tables                              │   │
│  │    └─► Session completely cleaned up                            │   │
│  └─────────────────────────────────────────────────────────────────┘   │
│                                                                         │
└─────────────────────────────────────────────────────────────────────────┘
```

### Multiple Concurrent Sessions

SqlSizer supports multiple simultaneous sessions with isolated schemas:

```powershell
$session1 = Start-SqlSizerSession -Database $db -ConnectionInfo $conn -DatabaseInfo $info  # SqlSizer_abc123
$session2 = Start-SqlSizerSession -Database $db -ConnectionInfo $conn -DatabaseInfo $info  # SqlSizer_def456

# Sessions are completely independent - no interference
Find-Subset -SessionId $session1 -Database $db -ConnectionInfo $conn -DatabaseInfo $info
Find-Subset -SessionId $session2 -Database $db -ConnectionInfo $conn -DatabaseInfo $info

# Clean up individually
Clear-SqlSizerSession -SessionId $session1 -Database $db -ConnectionInfo $conn

# Or clear ALL sessions at once
Clear-SqlSizerSessions -Database $db -ConnectionInfo $conn
```

---

## Common Scenarios

### Scenario 1: Create Development Database from Production

**Goal**: Create a small, realistic test database with 50 customers and all their data.

```powershell
# Select 50 random active customers
$query = New-Object -TypeName Query2
$query.State = [TraversalState]::Include
$query.Schema = "Sales"
$query.Table = "Customer"
$query.KeyColumns = @('CustomerID')
$query.Where = "[`$table].IsActive = 1"
$query.Top = 50
$query.OrderBy = "NEWID()"  # Random selection

Initialize-StartSet -Database "Production" -Queries @($query) -SessionId $sessionId `
    -DatabaseInfo $info -ConnectionInfo $connection

# Find all related data (orders, products, etc.)
Find-Subset -Database "Production" -SessionId $sessionId `
    -DatabaseInfo $info -ConnectionInfo $connection -FullSearch $true

# Copy to development database
Copy-DataFromSubset -SourceDatabase "Production" -DestinationDatabase "Development" `
    -SessionId $sessionId -ConnectionInfo $connection
```

### Scenario 2: Safely Delete a Customer and All Their Data

**Goal**: Delete Customer #123 and all records that depend on them.

```powershell
# Mark customer for removal
$query = New-Object -TypeName Query2
$query.State = [TraversalState]::InboundOnly  # Only find what depends on this
$query.Schema = "Sales"
$query.Table = "Customer"
$query.KeyColumns = @('CustomerID')
$query.Where = "[`$table].CustomerID = 123"

Initialize-StartSet -Database $db -Queries @($query) -SessionId $sessionId `
    -DatabaseInfo $info -ConnectionInfo $connection

# Find all dependent records (Orders, OrderItems, Reviews, etc.)
Find-RemovalSubset -Database $db -SessionId $sessionId `
    -DatabaseInfo $info -ConnectionInfo $connection

# Review what will be deleted
Get-SubsetTables -Database $db -SessionId $sessionId `
    -DatabaseInfo $info -ConnectionInfo $connection | Format-Table

# Delete in correct order (children before parents)
Remove-FoundSubsetFromDatabase -Database $db -SessionId $sessionId `
    -ConnectionInfo $connection
```

### Scenario 3: Export Subset as JSON

**Goal**: Export specific data for external processing or archival.

```powershell
# Find subset (same as before)
Find-Subset -Database $db -SessionId $sessionId `
    -DatabaseInfo $info -ConnectionInfo $connection

# Export each table as JSON
$tables = Get-SubsetTables -Database $db -SessionId $sessionId `
    -DatabaseInfo $info -ConnectionInfo $connection

foreach ($table in $tables) {
    $json = Get-SubsetTableJson -Database $db -SessionId $sessionId `
        -Schema $table.SchemaName -Table $table.TableName `
        -ConnectionInfo $connection
    
    $json | Out-File "export\$($table.SchemaName)_$($table.TableName).json"
}
```

### Scenario 4: Compare Two Subsets

**Goal**: Verify consistency between two subset operations.

```powershell
# Create two subsets
$sessionA = Start-SqlSizerSession -Database $db -ConnectionInfo $conn -DatabaseInfo $info
$sessionB = Start-SqlSizerSession -Database $db -ConnectionInfo $conn -DatabaseInfo $info

# (Initialize and find subsets in each session...)

# Compare results
Compare-SavedSubsets -Database $db -SessionIdA $sessionA -SessionIdB $sessionB `
    -ConnectionInfo $conn
```

---

## Workflow Examples

### Example 1: Create Subset Database (Complete)

```powershell
# 1. Setup connection
$password = ConvertTo-SecureString "MyPassword" -AsPlainText -Force
$connection = New-SqlConnectionInfo -Server "localhost" -Username "sa" -Password $password

# 2. Get database metadata (cached for all operations)
$info = Get-DatabaseInfo -Database "Production" -ConnectionInfo $connection

# 3. Start session
$sessionId = Start-SqlSizerSession -Database "Production" `
    -ConnectionInfo $connection -DatabaseInfo $info

try {
    # 4. Define starting records
    $query = New-Object -TypeName Query2
    $query.State = [TraversalState]::Include
    $query.Schema = "Sales"
    $query.Table = "SalesOrder"
    $query.KeyColumns = @('SalesOrderID')
    $query.Top = 100

    Initialize-StartSet -Database "Production" -Queries @($query) `
        -SessionId $sessionId -DatabaseInfo $info -ConnectionInfo $connection

    # 5. Find complete subset
    Find-Subset -Database "Production" -SessionId $sessionId `
        -DatabaseInfo $info -ConnectionInfo $connection -FullSearch $false

    # 6. Create and populate new database
    Copy-Database -Database "Production" -NewDatabase "Production_Subset" `
        -ConnectionInfo $connection

    $newInfo = Get-DatabaseInfo -Database "Production_Subset" -ConnectionInfo $connection

    Disable-ForeignKeys -Database "Production_Subset" -ConnectionInfo $connection `
        -DatabaseInfo $newInfo
    Clear-Database -Database "Production_Subset" -ConnectionInfo $connection `
        -DatabaseInfo $newInfo
    Copy-DataFromSubset -SourceDatabase "Production" -DestinationDatabase "Production_Subset" `
        -SessionId $sessionId -ConnectionInfo $connection -DatabaseInfo $info
    Enable-ForeignKeys -Database "Production_Subset" -ConnectionInfo $connection `
        -DatabaseInfo $newInfo

    # 7. Validate
    Test-ForeignKeys -Database "Production_Subset" -ConnectionInfo $connection -DatabaseInfo $newInfo
}
finally {
    # 8. Always cleanup
    Clear-SqlSizerSession -Database "Production" -SessionId $sessionId -ConnectionInfo $connection
}
```

### Example 2: Remove Data Safely (Complete)

```powershell
$sessionId = Start-SqlSizerSession -Database $db -ConnectionInfo $connection -DatabaseInfo $info

try {
    # Define records to remove
    $query = New-Object -TypeName Query2
    $query.State = [TraversalState]::InboundOnly
    $query.Schema = "Person"
    $query.Table = "Person"
    $query.KeyColumns = @('BusinessEntityID')
    $query.Where = "[`$table].FirstName = 'TestUser'"

    Initialize-StartSet -Database $db -Queries @($query) `
        -SessionId $sessionId -DatabaseInfo $info -ConnectionInfo $connection

    # Find all dependent records
    Find-RemovalSubset -Database $db -SessionId $sessionId `
        -DatabaseInfo $info -ConnectionInfo $connection

    # Preview what will be deleted
    Write-Host "The following data will be deleted:"
    Get-SubsetTables -Database $db -SessionId $sessionId `
        -DatabaseInfo $info -ConnectionInfo $connection | Format-Table

    # Delete in correct FK order (children first)
    Remove-FoundSubsetFromDatabase -Database $db -SessionId $sessionId `
        -ConnectionInfo $connection
}
finally {
    Clear-SqlSizerSession -Database $db -SessionId $sessionId -ConnectionInfo $connection
}
```

---

## Performance Considerations

### Memory Efficiency

| Feature | Benefit |
|---------|---------|
| **Server-side processing** | All heavy lifting done in SQL Server, not PowerShell |
| **Streaming results** | Results paged, not loaded entirely into memory |
| **No record duplication** | Each record tracked once regardless of discovery paths |
| **O(1) lookups** | Hashtable-based table lookups instead of linear search |

### Query Optimization

| Optimization | Description |
|--------------|-------------|
| **CTE-based queries** | Better query plan optimization by SQL Server |
| **Query caching** | Same table/state combinations reuse generated SQL |
| **Batch processing** | Configurable `MaxBatchSize` for controlled resource usage |
| **Parallel FK queries** | Multiple FK relationships processed in single SQL batch |

### Best Practices

| Scenario | Recommendation |
|----------|----------------|
| Large databases (>1M rows) | Set `MaxBatchSize` to 10000-50000 |
| Complex schemas (>100 tables) | Start with `FullSearch = $false`, expand if needed |
| Slow performance | Check for missing indexes on FK columns |
| Azure SQL | Connection already optimized for cloud |
| Azure Synapse | Set `IsSynapse = $true` in connection info |
| Memory pressure | Use DFS (`UseDfs = $true`) for lower memory footprint |

### Index Recommendations

```powershell
# Check for missing FK indexes
$info = Get-DatabaseInfo -Database $db -ConnectionInfo $connection

# This cmdlet creates indexes on FK columns that lack them
Install-ForeignKeyIndexes -Database $db -ConnectionInfo $connection -DatabaseInfo $info
```

**Critical indexes to verify:**
- ✅ All primary key columns (usually automatic)
- ⚠️ All foreign key columns (often missing!)
- ⚠️ Columns in WHERE clauses of your seed queries

---

## Troubleshooting

### Common Issues and Solutions

| Issue | Cause | Solution |
|-------|-------|----------|
| **Session already exists** | Previous session not cleaned up | `Clear-SqlSizerSession` or `Clear-SqlSizerSessions` |
| **Timeout during traversal** | Large dataset, missing indexes | Add indexes, reduce `Top` in seed query, use `MaxBatchSize` |
| **Out of memory** | Too many records in PowerShell | Use `-FullSearch $false`, add `MaxBatchSize` |
| **FK constraint errors on copy** | Wrong deletion/insertion order | Use provided cmdlets - they handle ordering |
| **Missing tables in subset** | No FK path to table | Add explicit seed query for orphan tables |
| **Circular reference warning** | Self-referential or cyclic FKs | Normal - algorithm handles cycles correctly |

### Debugging Tips

**Enable Verbose Output:**
```powershell
Find-Subset -Database $db -SessionId $sessionId `
    -DatabaseInfo $info -ConnectionInfo $connection `
    -Verbose
```

**Check Processing Table Counts:**
```powershell
# Connect directly to check what's been discovered
$sql = @"
SELECT 
    OBJECT_SCHEMA_NAME(object_id) AS [Schema],
    OBJECT_NAME(object_id) AS [Table],
    SUM(row_count) AS [RowCount]
FROM sys.dm_db_partition_stats
WHERE OBJECT_SCHEMA_NAME(object_id) LIKE 'SqlSizer_%'
GROUP BY object_id
ORDER BY [RowCount] DESC
"@

Invoke-Sqlcmd -Query $sql -Database $db -ServerInstance "localhost"
```

**View Generated SQL:**
```powershell
# Enable script output to see generated queries
$VerbosePreference = 'Continue'
Find-Subset -Verbose ...
```

### Session Cleanup

If sessions accumulate or operations fail mid-way:

```powershell
# List all SqlSizer schemas
Get-SqlSizerInfo -Database $db -ConnectionInfo $connection

# Clear specific session
Clear-SqlSizerSession -Database $db -SessionId "problematic_session_id" -ConnectionInfo $connection

# Nuclear option: clear ALL sessions
Clear-SqlSizerSessions -Database $db -ConnectionInfo $connection
```

---

## Glossary

| Term | Definition |
|------|------------|
| **Seed Record** | Starting point for traversal - records you explicitly specify |
| **Processing Table** | Temporary table tracking discovered records per source table |
| **Session** | Isolated workspace with its own schema and processing tables |
| **SessionId** | Unique identifier for a session (e.g., "abc123") |
| **Traversal State** | Classification of a record (Include, Exclude, Pending, InboundOnly) |
| **Outgoing FK** | Following FK from child table to parent (dependency direction) |
| **Incoming FK** | Following FK from parent to child (dependent direction) |
| **FullSearch** | Mode that follows both outgoing and incoming FKs |
| **Depth** | Number of hops from seed records |
| **Iteration** | Processing cycle number when record was discovered |
| **BFS** | Breadth-First Search - processes all records at same depth before going deeper |
| **DFS** | Depth-First Search - follows one path fully before exploring alternatives |
| **CTE** | Common Table Expression - SQL feature for readable subqueries |
| **Color** | Internal name for TraversalState (legacy terminology) |

---

## Appendix: Key Cmdlets Reference

### Core Operations

| Cmdlet | Purpose | Example |
|--------|---------|---------|
| `New-SqlConnectionInfo` | Create connection object | `-Server "localhost" -Username "sa" -Password $pwd` |
| `Get-DatabaseInfo` | Extract database metadata | `-Database "MyDB" -ConnectionInfo $conn` |
| `Start-SqlSizerSession` | Initialize session | `-Database $db -ConnectionInfo $conn -DatabaseInfo $info` |
| `Initialize-StartSet` | Define seed records | `-Database $db -Queries @($query) -SessionId $sid` |
| `Find-Subset` | Find subset by traversal | `-Database $db -SessionId $sid -FullSearch $false` |
| `Find-RemovalSubset` | Find deletion dependencies | `-Database $db -SessionId $sid` |

### Result Operations

| Cmdlet | Purpose | Output |
|--------|---------|--------|
| `Get-SubsetTables` | List tables in subset | Table names + row counts |
| `Get-SubsetTableRows` | Get actual row data | PSObjects with column values |
| `Get-SubsetTableJson` | Export as JSON | JSON string |
| `Get-SubsetTableCsv` | Export as CSV | CSV string |
| `Get-SubsetTableXml` | Export as XML | XML string |
| `Copy-DataFromSubset` | Copy to another DB | (side effect) |

### Data Operations

| Cmdlet | Purpose |
|--------|---------|
| `Copy-Database` | Clone database structure |
| `Clear-Database` | Delete all data from tables |
| `Remove-FoundSubsetFromDatabase` | Delete subset records in FK order |
| `Import-SubsetFromFileSet` | Import from file-based export |

### Maintenance

| Cmdlet | Purpose |
|--------|---------|
| `Clear-SqlSizerSession` | Remove single session |
| `Clear-SqlSizerSessions` | Remove ALL sessions |
| `Get-SqlSizerInfo` | List active sessions |
| `Disable-ForeignKeys` | Temporarily disable FK constraints |
| `Enable-ForeignKeys` | Re-enable FK constraints |
| `Test-ForeignKeys` | Validate FK integrity |
| `Install-ForeignKeyIndexes` | Create missing FK indexes |

---

## Further Reading

**In This Repository:**
- [Examples/AdventureWorks2019/Subset/](../Examples/AdventureWorks2019/Subset/) - Working subset examples
- [Examples/AdventureWorks2019/Removal/](../Examples/AdventureWorks2019/Removal/) - Data removal examples
- [README.md](../README.md) - Quick start and feature overview

**Example Scripts:**
- [00-Simple-Find-Subset-Example.ps1](../Examples/AdventureWorks2019/Subset/00-Simple-Find-Subset-Example.ps1) - Basic usage
- [01-Basic-Data-Removal.ps1](../Examples/AdventureWorks2019/Removal/01-Basic-Data-Removal.ps1) - Safe deletion

---

*Last updated: February 2026 | SqlSizer-MSSQL v2.0.1*
