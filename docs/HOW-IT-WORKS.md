# How SqlSizer-MSSQL Works

> **TL;DR**: SqlSizer finds all data connected to your "seed" records by following foreign key relationships, ensuring your subset remains referentially consistent.

---

## Table of Contents

1. [Quick Start (5-Minute Guide)](#quick-start-5-minute-guide)
2. [Overview](#overview)
3. [Core Concepts](#core-concepts)
4. [Traversal Configuration](#traversal-configuration)
5. [Architecture](#architecture)
6. [Database Schema Internals](#database-schema-internals)
7. [The Subset Algorithm](#the-subset-algorithm)
8. [The Removal Algorithm](#the-removal-algorithm)
9. [SQL Generation (CTE-Based)](#sql-generation-cte-based)
10. [Data Structures](#data-structures)
11. [Session Management](#session-management)
12. [Checkpoint & Resume](#checkpoint--resume)
13. [Subset Impact Reports](#subset-impact-reports)
14. [Advanced Features](#advanced-features)
15. [Common Scenarios](#common-scenarios)
16. [Workflow Examples](#workflow-examples)
17. [Copy-Database](#copy-database)
18. [Azure SQL Support](#azure-sql-support)
19. [Performance Considerations](#performance-considerations)
20. [Troubleshooting](#troubleshooting)
21. [Glossary](#glossary)

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
$query = New-Object -TypeName SqlSizerQuery
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
| **Include** | `[TraversalState]::Include` | Must be in subset | Outgoing + Incoming (if FullSearch) | In subset |
| **Exclude** | `[TraversalState]::Exclude` | Must NOT be in subset | None - stops here | Not in subset |
| **Pending** | `[TraversalState]::Pending` | Candidate/bookkeeping state | Outgoing only when explicitly present | Not returned in subset outputs unless promoted to Include |
| **InboundOnly** | `[TraversalState]::InboundOnly` | For removal operations | Incoming only | Finds dependents |
| **IncludeFull** | `[TraversalState]::IncludeFull` | Force incoming traversal for specific records | Outgoing + Incoming (always) | In subset |

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

### Complete State Transition Table

The function `Get-NewTraversalState` in `TraversalHelpers.ps1` implements these rules:

| Current State | Direction | FullSearch | New State | Explanation |
|---------------|-----------|------------|-----------|-------------|
| **Include** | Outgoing | - | Include | Referenced data must be included |
| **Include** | Incoming | `$false` | *(no traverse)* | Minimal subset mode ignores dependents that reference the seed |
| **Include** | Incoming | `$true` | Include | Full closure: include all dependents |
| **IncludeFull** | Outgoing | - | Include | Follow dependencies normally |
| **IncludeFull** | Incoming | - | Include | Always include dependents (per-record full search) |
| **Pending** | Outgoing | - | Pending | Propagate uncertainty to dependencies |
| **Pending** | Incoming | - | *(no traverse)* | Don't explore further from uncertain records |
| **Exclude** | Outgoing | - | *(no traverse)* | Exclusion stops all traversal |
| **Exclude** | Incoming | - | *(no traverse)* | Exclusion stops all traversal |
| **InboundOnly** | Outgoing | - | *(no traverse)* | Removal mode: only finds dependents |
| **InboundOnly** | Incoming | - | InboundOnly | Continue finding dependents |

The function `Test-ShouldTraverseDirection` controls whether traversal even occurs for a given State+Direction combination before `Get-NewTraversalState` is called. In default subset mode this means `Include` follows outgoing dependencies only; `FullSearch`, `IncludeFull`, and removal mode opt into incoming traversal.

### FullSearch Mode

The `FullSearch` parameter controls which directions are followed:

| Parameter | Outgoing FKs | Incoming FKs | Use Case |
|-----------|--------------|--------------|----------|
| `$false` (default) | Yes | No | Finding dependencies of seed records |
| `$true` | Yes | Yes | Finding complete data closure (both directions) |

**When to use FullSearch:**
- `$false` - "Give me this Customer and everything they need" (Orders, Products referenced)
- `$true` - "Give me this Customer and everything connected" (includes their Orders, OrderItems, etc.)

---

## Traversal Configuration

`TraversalConfiguration` lets you customize traversal behavior per table, overriding the default state transitions and adding constraints.

### Creating a Configuration

```powershell
$config = New-Object TraversalConfiguration

# Add a rule for a specific table
$rule = New-Object TraversalRule
$rule.SchemaName = "Sales"
$rule.TableName = "AuditLog"
$rule.StateOverride = New-Object StateOverride
$rule.StateOverride.State = [TraversalState]::Exclude  # Never include audit logs
$config.Rules = @($rule)

# Pass to Find-Subset
Find-Subset -Database $db -SessionId $sid -DatabaseInfo $info `
    -ConnectionInfo $conn -TraversalConfiguration $config
```

### StateOverride

Forces a specific `TraversalState` for any records discovered in a table, regardless of the normal transition rules:

```powershell
# Force all Product records to be included
$rule = New-Object TraversalRule
$rule.SchemaName = "Production"
$rule.TableName = "Product"
$rule.StateOverride = [StateOverride]::new([TraversalState]::Include)
```

### TraversalConstraints

Limits how far or how much the traversal explores for a specific table:

```powershell
$rule = New-Object TraversalRule
$rule.SchemaName = "Sales"
$rule.TableName = "OrderHistory"
$rule.Constraints = New-Object TraversalConstraints
$rule.Constraints.MaxDepth = 3          # Stop after 3 hops from this table
$rule.Constraints.Top = 1000            # Max 1000 rows discovered for this table
```

Available constraints:

| Constraint | Default | Description |
|------------|---------|-------------|
| `MaxDepth` | `-1` (unlimited) | Stop traversal after N hops from source |
| `Top` | `-1` (unlimited) | Limit discovered rows to N, ordered by target primary key for repeatability |
| `SourceSchemaName` + `SourceTableName` | `""` (any) | Only process when source matches |
| `ForeignKeyName` | `""` (any) | Only process via this specific FK |
| `Filter` | `""` (any) | Apply the rule only to matching target rows; use `[$table]` as the target alias |

### Fluent API

`TraversalRule` supports a fluent builder pattern:

```powershell
$rule = [TraversalRule]::new("Sales", "OrderHistory")
$rule.SetStateOverride([TraversalState]::Include).SetMaxDepth(3).SetTop(1000)
```

Rules for the same table are evaluated in `AddRule` order. A filtered rule handles
matching target rows first; a later unfiltered rule acts as the fallback:

```powershell
$vip = [TraversalRule]::new("dbo", "Accounts")
$vip.SetFilter("[`$table].[Tier] = 'VIP'").SetStateOverride([TraversalState]::IncludeFull)
$config.AddRule($vip)

$rest = [TraversalRule]::new("dbo", "Accounts")
$rest.SetStateOverride([TraversalState]::Include)
$config.AddRule($rest)
```

### Ignored Tables

Skip entire tables during traversal (they won't be discovered at all):

```powershell
$config = New-Object TraversalConfiguration
$config.AddIgnoredTable("dbo", "AuditLog")
$config.AddIgnoredTable("dbo", "ChangeTracking")

# Or set all at once
$config.IgnoredTables = @(
    [TableInfo2]@{ SchemaName = "dbo"; TableName = "AuditLog" },
    [TableInfo2]@{ SchemaName = "dbo"; TableName = "ChangeTracking" }
)
```

### Practical Examples

**Limit traversal depth on a high-fanout table:**
```powershell
# Don't follow more than 2 levels deep from ProductCategory
$rule = [TraversalRule]::new("Production", "ProductCategory")
$rule.SetMaxDepth(2)
$config.AddRule($rule)
```

**Exclude lookup/reference tables:**
```powershell
# Force exclude for lookup tables that don't need subsetting
foreach ($table in @("CountryCode", "CurrencyCode", "StatusType")) {
    $rule = [TraversalRule]::new("dbo", $table)
    $rule.SetStateOverride([TraversalState]::Exclude)
    $config.AddRule($rule)
}
```

**Cap rows on large tables:**
```powershell
# Only include up to 500 log entries
$rule = [TraversalRule]::new("dbo", "EventLog")
$rule.SetTop(500)
$config.AddRule($rule)
```

---

## Architecture

### Module Structure

```
SqlSizer-MSSQL/
├── SqlSizer-MSSQL.psm1      # Module loader
├── SqlSizer-MSSQL.psd1      # Module manifest (v2.0.2)
├── Public/                   # 100+ exported cmdlets
│   ├── Find-Subset.ps1           # Core subset algorithm
│   ├── Find-RemovalSubset.ps1    # Deletion dependency finder
│   ├── Initialize-StartSet.ps1   # Seed record setup
│   ├── Get-SubsetTables.ps1      # Result retrieval
│   ├── Get-SubsetImpactReport.ps1     # Read-only session impact report
│   ├── Export-SubsetImpactReport.ps1  # JSON/Markdown/HTML report export
│   ├── Copy-DataFromSubset.ps1   # Data export
│   ├── Copy-Database.ps1         # Full database clone (backup/restore)
│   ├── Install-SqlSizerCore.ps1  # Schema installation
│   ├── Install-SqlSizerSessionTables.ps1  # Session table creation
│   ├── Resume-Subset.ps1         # Checkpoint resume
│   └── ... (other cmdlets)
├── Shared/                   # Internal helper modules
│   ├── QueryBuilders.ps1         # CTE-based SQL query generation
│   ├── TraversalHelpers.ps1      # State transition & constraint logic
│   ├── SubsetImpactReportHelpers.ps1  # Report shaping and rendering helpers
│   └── ValidationHelpers.ps1     # Input validation functions
└── Types/                    # Type definitions
    └── SqlSizer-MSSQL-Types.ps1  # Classes, enums, and data structures
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
│  │  SqlSizerQuery object(s) ─────► Initialize-StartSet             │   │
│  │   • State (Include/Exclude/Pending/IncludeFull)                 │   │
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
│  │  Find-Subset ──────────► Graph traversal (BFS/size-first)       │   │
│  │   • Follows FK relationships                                    │   │
│  │   • Populates processing tables                                 │   │
│  │   • Resolves Pending states                                     │   │
│  │   • Optional: checkpoint progress to JSON file                  │   │
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
│  │  Get-SubsetImpactReport ► Table impact + relationship summary   │   │
│  │  Export-SubsetImpactReport ► JSON/Markdown/HTML report files    │   │
│  │  Copy-DataFromSubset ──► Export to target database              │   │
│  │  Get-SubsetTableJson ──► Export as JSON                         │   │
│  │  Get-SubsetTableCsv ──► Export as CSV                           │   │
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
-- Named: {SchemaName}_{TableName}

CREATE TABLE SqlSizer_abc123.Sales_Customer (
    Id INT IDENTITY(1,1) PRIMARY KEY,
    Key0 INT NOT NULL,           -- First PK column value
    Key1 VARCHAR(50) NOT NULL,   -- Second PK column value (if composite)
    -- ... more KeyN columns for larger PKs

    [State] TINYINT NOT NULL,    -- TraversalState (1=Include, 2=Exclude, 3=Pending, 4=InboundOnly, 5=IncludeFull)
    [Source] SMALLINT NULL,      -- SqlSizer.Tables.Id of the table that led here
    [Depth] SMALLINT NOT NULL,   -- Hops from seed records
    [Fk] SMALLINT,               -- SqlSizer.ForeignKeys.Id that was followed
    [Iteration] INT NOT NULL     -- When this record was discovered
);

-- Indexes (for subset mode):
CREATE NONCLUSTERED INDEX [Index]   ON ... (Key0, Key1, ..., [State] ASC)
CREATE NONCLUSTERED INDEX [Index_2] ON ... ([Iteration]) INCLUDE ([Depth], [Fk])

-- Indexes (for removal mode):
CREATE NONCLUSTERED INDEX [Index]   ON ... (Key0, Key1, ..., [Depth] ASC)
```

This design enables:
- **Server-side processing**: Heavy lifting done in SQL Server
- **No record duplication**: Each record tracked once regardless of paths
- **Audit trail**: Know how each record was discovered (Source, Fk, Depth, Iteration)

### Structure and Signature System

The `Structure` class maps each table to a **signature** (its `SchemaName_TableName`) and uses signatures to generate processing table names:

```
Table: Sales.Customer  →  Signature: "Sales_Customer"
                       →  Processing: SqlSizer_{SessionId}.Sales_Customer

Table: dbo.Product     →  Signature: "dbo_Product"
                       →  Processing: SqlSizer_{SessionId}.dbo_Product
```

Tables starting with `SqlSizer` or lacking a primary key are excluded from processing.

---

## Database Schema Internals

SqlSizer creates three schema categories in the target database:

### `SqlSizer` Schema (Core Infrastructure)

Created by `Install-SqlSizerCore`. Contains metadata that persists across sessions:

```
┌─────────────────────────────────────────────────────────────────────────┐
│  SqlSizer Schema                                                        │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                         │
│  SqlSizer.Tables                                                       │
│  ├── Id (int, identity, PK)                                            │
│  ├── [Schema] (varchar 128)     ── indexed                             │
│  └── TableName (varchar 128)    ── indexed                             │
│                                                                         │
│  SqlSizer.ForeignKeys                                                  │
│  ├── Id (int, identity, PK)                                            │
│  ├── FkTableId (int)            ── references Tables.Id (FK source)    │
│  ├── TableId (int)              ── references Tables.Id (FK target)    │
│  └── Name (varchar 256)         ── FK constraint name                  │
│                                                                         │
│  SqlSizer.Operations                                                   │
│  ├── Id (int, identity, PK)                                            │
│  ├── [Table] (smallint)         ── references Tables.Id                │
│  ├── [State] (int)              ── TraversalState enum value           │
│  ├── ToProcess (int)            ── rows to process in this operation   │
│  ├── Processed (int)            ── rows already processed              │
│  ├── Status (int, nullable)     ── NULL=pending, 0=in-progress, 1=done│
│  ├── Source (int)               ── Tables.Id that created this op      │
│  ├── Fk (int)                   ── ForeignKeys.Id used                 │
│  ├── Depth (int)                ── distance from seed records          │
│  ├── Created (datetime)                                                │
│  ├── ProcessedDate (datetime)                                          │
│  ├── SessionId (varchar 256)    ── session isolation                   │
│  ├── FoundIteration (int)       ── iteration when operation was created│
│  └── ProcessedIteration (int)   ── iteration when completed           │
│  Index: ([Table], [State], [Source], [Depth])                          │
│                                                                         │
│  SqlSizer.Sessions                                                     │
│  ├── Id (int, identity, PK)                                            │
│  └── SessionId (varchar 256)    ── active session registry             │
│                                                                         │
│  SqlSizer.Settings                                                     │
│  ├── Id (int, identity, PK)                                            │
│  ├── Name (varchar 128)         ── e.g., "Version"                     │
│  └── Value (varchar 256)        ── e.g., "2.0.2"                       │
│                                                                         │
│  SqlSizer.Files                                                        │
│  ├── Id (int, identity, PK)                                            │
│  ├── FileId (uniqueidentifier)  ── groups file chunks                  │
│  ├── [Index] (int)              ── chunk order                         │
│  └── Content (nvarchar max)     ── file content chunk                  │
│                                                                         │
└─────────────────────────────────────────────────────────────────────────┘
```

### `SqlSizer_{SessionId}` Schema (Session-Specific)

Created by `Install-SqlSizerSessionTables`. Contains one processing table per source table with a primary key. Isolated per session—multiple concurrent sessions don't interfere.

### `SqlSizerHistory` Schema (Subset History)

Persists across sessions for tracking historical subset operations:

```sql
SqlSizerHistory.Subset
├── Id (int, identity, PK)
├── Guid (uniqueidentifier)
├── Name (varchar 256)
└── Created (datetime, default GETDATE())

SqlSizerHistory.SubsetTable
├── Id (int, identity, PK)
├── SchemaName (varchar 256)
├── TableName (varchar 256)
├── PrimaryKeySize (int)
├── RowCount (int)
└── SubsetId (int, FK → Subset.Id, CASCADE DELETE)
```

### Operations Table: The Work Queue

The `SqlSizer.Operations` table is the central work queue driving both `Find-Subset` and `Find-RemovalSubset`. Each row represents a unit of work: "process N rows from table T at depth D with state S."

**Status lifecycle:**

```
NULL (pending) → 0 (in-progress) → 1 (completed)
                     │
                     └─ If batch limit hit and not all rows processed:
                        reset back to NULL for re-queuing
```

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
│   │ Records │     │(BFS/size-first)  │     │   Pending     │          │
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
| 4 | `Initialize-OperationsTable` | Counts rows per (Table, State) and creates initial Operations entries |

```powershell
# Example: Start with 10 customers named 'John'
$query = New-Object -TypeName SqlSizerQuery
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

The algorithm uses **Breadth-First Search (BFS)** by default. The legacy `UseDfs` switch preserves its historical size-first ordering, which prioritizes the operation with the most remaining rows rather than doing strict depth-first traversal:

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

**Algorithm Loop (Pseudocode):**

```
Build hashtable lookups for tables, FKs (O(1) access)

WHILE unprocessed operations exist:
    1. Get-NextOperation: SELECT TOP 1 from Operations
       - BFS: ORDER BY Depth ASC, RemainingRecords DESC
       - UseDfs legacy ordering: ORDER BY RemainingRecords DESC

    2. Set-OperationInProgress: Mark Status = 0, advance Processed count

    3. Invoke-TraversalOperation:
       a. Test-ShouldTraverseDirection for outgoing
       b. Test-ShouldTraverseDirection for incoming
       c. For each direction enabled:
          - Generate CTE queries for matching FKs
          - Batch all FK queries into single SQL execution
       d. Execute batched SQL (reduces round-trips)

    4. Complete-Operations:
       - If batch fully processed: Status → 1 (complete)
       - If batch limit hit: Status → NULL (re-queue)

    5. Resolve-PendingStates (compatibility/candidate cleanup):
       - UPDATE remaining Pending → Exclude in processing tables

    6. Save checkpoint (every CheckpointInterval iterations)

    7. Increment iteration counter
```

**Traversal order:**
| Algorithm | Parameter | `ORDER BY` | Best For |
|-----------|-----------|------------|----------|
| **BFS** | `UseDfs = $false` | `Depth ASC, RemainingRecords DESC` | Even discovery, predictable progress |
| **Legacy size-first** | `UseDfs = $true` | `RemainingRecords DESC` | Prioritizing the largest queued operation |

### Phase 3: Output Closure

After traversal, output surfaces return only closure states: **Include**, **IncludeFull**, and **InboundOnly**. Any remaining **Pending** records are compatibility/candidate rows and are marked as **Exclude**:

```
┌─────────────────────────────────────────────────────────────────────────┐
│                     PENDING STATE HANDLING                              │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                         │
│   DEFAULT MINIMAL SUBSET:                                              │
│   - Include rows follow outgoing FKs only                              │
│   - Incoming dependents are not discovered as Pending                  │
│                                                                         │
│   FULL CLOSURE / INCLUDEFULL:                                          │
│   - Incoming dependents are included directly                          │
│                                                                         │
│   OUTPUT FILTER:                                                       │
│   - Include, IncludeFull, InboundOnly → visible in subset outputs      │
│   - Pending, Exclude → hidden from subset outputs                      │
│                                                                         │
└─────────────────────────────────────────────────────────────────────────┘
```

---

## The Removal Algorithm

`Find-RemovalSubset` solves a different problem: **given records you want to delete, what other records must be deleted first to maintain referential integrity?**

### How It Differs from Find-Subset

| Aspect | Find-Subset | Find-RemovalSubset |
|--------|-------------|-------------------|
| **Direction** | Outgoing + optionally Incoming | Incoming only |
| **Purpose** | Build a consistent subset | Find deletion dependencies |
| **Starting state** | Usually Include | Usually InboundOnly |
| **Configuration** | TraversalConfiguration supported | No configuration (simpler) |
| **Result usage** | Copy/export discovered rows | Delete discovered rows in order |

### Algorithm Walkthrough

```
┌─────────────────────────────────────────────────────────────────────────┐
│                    REMOVAL ALGORITHM                                     │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                         │
│   Target: Delete Customer #123                                         │
│                                                                         │
│   Depth 0: Customer #123 (seed)                                        │
│            │                                                            │
│            │ incoming FK: Order.CustomerID → Customer.CustomerID       │
│            ▼                                                            │
│   Depth 1: Order #A, Order #B                                          │
│            │                                                            │
│            │ incoming FK: OrderItem.OrderID → Order.OrderID            │
│            ▼                                                            │
│   Depth 2: OrderItem #1, #2, #3, #4                                   │
│            │                                                            │
│            │ incoming FK: Review.OrderItemID → OrderItem.OrderItemID   │
│            ▼                                                            │
│   Depth 3: Review #X, #Y                                              │
│                                                                         │
│   DELETION ORDER (reverse of discovery):                                │
│   1. Delete Reviews (Depth 3)                                          │
│   2. Delete OrderItems (Depth 2)                                       │
│   3. Delete Orders (Depth 1)                                           │
│   4. Delete Customer (Depth 0)                                         │
│                                                                         │
└─────────────────────────────────────────────────────────────────────────┘
```

**Algorithm loop:**

```
WHILE unprocessed operations exist:
    1. Get-NextOperation:
       ORDER BY Depth ASC, Count DESC  (always BFS)

    2. Update-OperationStatus: Mark as in-progress

    3. Invoke-IncomingTraversal:
       For each table that references the current table:
         For each FK pointing to the current table:
           - Build CTE query (with template caching via ##DEPTH## placeholders)
           - Find all rows in FK source table that reference discovered rows
           - INSERT into FK source's processing table
           - CREATE new operation entry for next iteration

    4. Complete-ProcessedOperations:
       - Fully processed → Status = 1
       - Partially processed (batch limit) → Status = NULL
```

**Key differences in implementation:**
- Uses `##DEPTH##` and `##ITERATION##` placeholders in cached queries (replaced at execution time)
- Each FK query is executed individually (not batched like Find-Subset)
- No Pending state resolution needed (no outgoing traversal = no Pending states)

### Using Removal Results

```powershell
# After Find-RemovalSubset completes:

# Preview what will be deleted
Get-SubsetTables -Database $db -SessionId $sid `
    -DatabaseInfo $info -ConnectionInfo $conn | Format-Table

# Delete in correct FK order (deepest first)
Remove-FoundSubsetFromDatabase -Database $db -SessionId $sid `
    -ConnectionInfo $conn
```

---

## SQL Generation (CTE-Based)

The `New-CTETraversalQuery` function in `QueryBuilders.ps1` generates the SQL that drives each traversal step. Understanding this SQL is key to understanding SqlSizer's behavior.

### Actual Generated CTE Structure

For an **outgoing** FK traversal (e.g., Order → Customer via CustomerID):

```sql
-- Traverse OUTGOING FK: FK_Order_Customer
DECLARE @InsertedRows TABLE (Depth INT);

WITH SourceRecords AS (
    -- Get rows being processed in this iteration
    SELECT Key0, Depth, Fk
    FROM SqlSizer_abc123.Sales_Order src
    WHERE src.Iteration IN (
        SELECT FoundIteration
        FROM SqlSizer.Operations
        WHERE Status = 0 AND SessionId = 'abc123'
    )
),
NewRecords AS (
    -- Find referenced Customer records not yet discovered
    SELECT DISTINCT
        CAST(tgt.CustomerID AS INT) AS Key0,
        src.Depth + 1 AS Depth
    FROM Sales.Customer tgt
        INNER JOIN Sales.[Order] srcTable ON srcTable.CustomerID = tgt.CustomerID
        INNER JOIN SourceRecords src ON src.Key0 = srcTable.OrderID
    WHERE tgt.CustomerID IS NOT NULL
        AND NOT EXISTS (
            SELECT 1
            FROM SqlSizer_abc123.Sales_Customer existing
            WHERE existing.Key0 = CAST(tgt.CustomerID AS INT)
        )
)
-- Insert newly found records
INSERT INTO SqlSizer_abc123.Sales_Customer (Key0, [State], Source, Depth, Fk, Iteration)
OUTPUT inserted.Depth INTO @InsertedRows
SELECT Key0, 1, 7, Depth, 42, 5   -- State=Include, Source=TableId, FkId, Iteration
FROM NewRecords;

-- Promote existing Pending records to Include (if this is an Include traversal)
UPDATE existing
SET [State] = 1
FROM SqlSizer_abc123.Sales_Customer existing
WHERE existing.[State] = 3   -- Pending
    AND EXISTS (
        SELECT 1 FROM (
            SELECT DISTINCT CAST(tgt.CustomerID AS INT) AS Key0
            FROM Sales.Customer tgt
                INNER JOIN Sales.[Order] srcTable ON srcTable.CustomerID = tgt.CustomerID
                INNER JOIN SqlSizer_abc123.Sales_Order src ON src.Key0 = srcTable.OrderID
            WHERE src.Iteration IN (
                SELECT FoundIteration FROM SqlSizer.Operations
                WHERE Status = 0 AND SessionId = 'abc123'
            )
                AND tgt.CustomerID IS NOT NULL
        ) nr
        WHERE existing.Key0 = nr.Key0
    );

-- Record new operations for the discovered rows
INSERT INTO SqlSizer.Operations (
    [Table], [State], ToProcess, Processed, Status, Source, Fk, Depth,
    Created, ProcessedDate, SessionId, FoundIteration, ProcessedIteration
)
SELECT
    12,         -- Target table ID (Customer)
    1,          -- Include state
    COUNT(*),
    0,
    NULL,       -- Pending status (ready to process)
    7,          -- Source table ID (Order)
    42,         -- FK ID
    Depth,
    GETDATE(),
    NULL,
    'abc123',
    5,          -- Current iteration
    NULL
FROM @InsertedRows
GROUP BY Depth;
```

### Key SQL Patterns

**`@InsertedRows` table variable**: Captures the Depth of each inserted row via OUTPUT clause. This is used to create granular Operations entries grouped by depth.

**Pending→Include promotion**: The UPDATE query runs after every INSERT when `NewState = Include`. It finds existing Pending records that match the same join conditions, promotes them, refreshes their provenance to the Include path, and queues them as Include work. This is retained for compatibility with explicit Pending/candidate rows.

**Cycle safety**: `NOT EXISTS` against the target processing table prevents inserting the same table key twice. That key-level deduplication is what stops cycles while still allowing valid self-referencing chains to continue until an already-seen row is reached.

**NOT EXISTS deduplication**: Every CTE checks that the target record doesn't already exist in the processing table, ensuring each record is tracked exactly once.

### Incoming vs Outgoing JOIN Differences

**Outgoing FK** (Order → Customer via Order.CustomerID):
```sql
FROM Sales.Customer tgt                              -- target table (referenced)
    INNER JOIN Sales.[Order] srcTable                -- source table (has FK)
        ON srcTable.CustomerID = tgt.CustomerID      -- FK columns → PK columns
    INNER JOIN SourceRecords src                      -- processing table rows
        ON src.Key0 = srcTable.OrderID               -- PK match
```

**Incoming FK** (Customer ← Order via Order.CustomerID):
```sql
FROM Sales.[Order] tgt                               -- target table (FK source)
    INNER JOIN SourceRecords src                      -- processing table rows
        ON src.Key0 = tgt.CustomerID                 -- FK columns direct match
```

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
    [bool]$IsHistoric                # Is a system-versioned temporal table
    [bool]$HasHistory                # Has an associated history table
    [string]$HistoryOwner            # Name of the history table
    [string]$HistoryOwnerSchema      # Schema of the history table
    [List[ColumnInfo]]$PrimaryKey    # Primary key columns
    [List[ColumnInfo]]$Columns       # All columns
    [List[TableFk]]$ForeignKeys      # Outgoing FKs (this table → other tables)
    [List[TableInfo]]$IsReferencedBy # Other tables that reference this table
    [List[ViewInfo]]$Views           # Views depending on this table
    [List[string]]$Triggers          # Trigger names
    [List[TableIndex]]$Indexes       # Index definitions
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
    [ForeignKeyRule]$DeleteRule  # NoAction, Cascade, SetNull, SetDefault
    [ForeignKeyRule]$UpdateRule
    [List[ColumnInfo]]$FkColumns   # Source columns (e.g., CustomerID in Order)
    [List[ColumnInfo]]$Columns     # Referenced columns (e.g., CustomerID in Customer)
}
```

### SqlSizerQuery (Seed Record Definition)

```powershell
class SqlSizerQuery {
    [TraversalState]$State     # Include, Exclude, Pending, InboundOnly, or IncludeFull
    [string]$Schema            # Target table schema
    [string]$Table             # Target table name
    [string[]]$KeyColumns      # PK column names for identification
    [string]$Where             # Filter clause (use $table as table alias)
    [int]$Top                  # Limit number of records (-1 = no limit)
    [string]$OrderBy           # Optional ordering
}
```

### SqlConnectionInfo

```powershell
class SqlConnectionInfo {
    [string]$Server                              # Server instance name
    [PSCredential]$Credential                    # Username/password authentication
    [string]$AccessToken                         # Azure AD / token-based auth
    [bool]$EncryptConnection                     # Enable connection encryption
    [SqlConnectionStatistics]$Statistics         # Tracks logical reads
}
```

### TraversalConfiguration

```powershell
class TraversalConfiguration {
    [TraversalRule[]]$Rules          # Per-table behavior overrides
    [TableInfo2[]]$IgnoredTables     # Tables to skip entirely

    # Methods:
    # GetItemForTable($schema, $table) → TraversalRule  (O(1) cached lookup)
    # AddIgnoredTable($schema, $table) → self
    # AddRule($rule) → self
}
```

### TraversalRule

```powershell
class TraversalRule {
    [string]$SchemaName
    [string]$TableName
    [StateOverride]$StateOverride      # Force a specific TraversalState
    [TraversalConstraints]$Constraints  # MaxDepth, Top, filters
    [string]$Filter                     # Target-row SQL predicate using [$table]

    # Fluent methods:
    # SetStateOverride($state) → self
    # SetMaxDepth($value) → self
    # SetTop($value) → self
    # SetFilter($filter) → self
    # SetSourceFilter($schema, $table) → self
    # SetForeignKeyFilter($fkName) → self
}
```

### TraversalStatistics

```powershell
class TraversalStatistics {
    [long]$TotalOperations
    [long]$CompletedOperations
    [long]$TotalRecordsProcessed
    [long]$TotalRecordsRemaining
    [int]$CurrentIteration
    [int]$MaxDepthReached
    [TimeSpan]$ElapsedTime

    [double] PercentComplete()   # 100 * Processed / (Processed + Remaining)
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
│  │    • Get-SubsetImpactReport → Review impact and traversal state │   │
│  │    • Export-SubsetImpactReport → Write JSON/Markdown/HTML       │   │
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

## Checkpoint & Resume

For long-running traversals, SqlSizer can save progress to a JSON file and resume after crashes or interruptions.

### Enabling Checkpoints

```powershell
# Save progress every 5 iterations (default)
Find-Subset -Database $db -SessionId $sid -DatabaseInfo $info -ConnectionInfo $conn `
    -CheckpointPath "C:\temp\subset_checkpoint.json"

# Save more frequently for critical operations
Find-Subset -Database $db -SessionId $sid -DatabaseInfo $info -ConnectionInfo $conn `
    -CheckpointPath "C:\temp\subset_checkpoint.json" -CheckpointInterval 2
```

### Checkpoint JSON Structure

```json
{
    "Type": "Subset",
    "SessionId": "abc123def456",
    "Database": "MyDatabase",
    "LastCompletedIteration": 15,
    "FullSearch": false,
    "UseDfs": false,
    "MaxBatchSize": -1,
    "Status": "InProgress",
    "CreatedAt": "2026-03-17T10:30:00.0000000+01:00",
    "UpdatedAt": "2026-03-17T10:35:42.0000000+01:00"
}
```

For removal subsets, `Type` is `"RemovalSubset"` and the `FullSearch`/`UseDfs` fields are omitted.

### Resuming After a Crash

```powershell
# Option 1: Direct resume with Find-Subset -Resume
Find-Subset -Database $db -SessionId $sid -DatabaseInfo $info -ConnectionInfo $conn `
    -CheckpointPath "C:\temp\subset_checkpoint.json" -Resume

# Option 2: Inspect checkpoint first
$checkpoint = Get-SubsetCheckpoint -Path "C:\temp\subset_checkpoint.json"
Write-Host "Last completed iteration: $($checkpoint.LastCompletedIteration)"
Write-Host "Status: $($checkpoint.Status)"

# Option 3: Use convenience wrapper
Resume-Subset -Database $db -SessionId $sid -DatabaseInfo $info -ConnectionInfo $conn `
    -CheckpointPath "C:\temp\subset_checkpoint.json"
```

### How Resume Works Internally

```
┌─────────────────────────────────────────────────────────────────────────┐
│                    CHECKPOINT/RESUME FLOW                                │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                         │
│  Normal Start                        Resume                            │
│  ────────────                        ──────                            │
│  Initialize-OperationsTable          Read checkpoint JSON              │
│  Write initial checkpoint            Validate Type + SessionId         │
│  StartIteration = 0                  StartIteration = LastCompleted    │
│       │                                    │                           │
│       │                              Reset abandoned operations:       │
│       │                              UPDATE Status=NULL, Processed=0   │
│       │                              WHERE Status=0 (in-progress)      │
│       │                                    │                           │
│       └──────────────┬─────────────────────┘                           │
│                      │                                                  │
│                      ▼                                                  │
│              Main traversal loop                                        │
│              (continues from StartIteration + 1)                       │
│                      │                                                  │
│                      │ Every CheckpointInterval iterations:            │
│                      │ → Write progress to JSON file                   │
│                      │                                                  │
│                      ▼                                                  │
│              Traversal complete                                         │
│              → Write final checkpoint (Status = "Completed")           │
│                                                                         │
└─────────────────────────────────────────────────────────────────────────┘
```

The critical recovery step is resetting abandoned in-progress operations: if the process crashed mid-iteration, some Operations rows may have `Status = 0` (in-progress) but weren't actually completed. These are reset to `NULL` (pending) so they'll be re-processed.

---

## Subset Impact Reports

Subset impact reports are read-only summaries of an existing SqlSizer session. They are designed for review before a potentially expensive or destructive next step such as copying data to a new database, deleting records, or exporting files.

### What the Report Contains

`Get-SubsetImpactReport` returns a PowerShell object with five top-level sections:

| Section | Contents |
|---------|----------|
| `Summary` | Database, session id, generated time, subset/original table counts, total subset/original rows, estimated data KB, relationship counts, operation completion flag |
| `Tables` | One row per original user table with subset rows, original rows, row reduction, percent of original, primary key size, historic/deletable flags, estimated data KB |
| `Relationships` | Reached, unreached, and all foreign key relationships for the session |
| `Operations` | Traversal progress from `SqlSizer.Operations`, including processed/remaining records and state/depth breakdown |
| `Warnings` | Non-fatal issues such as missing measured table statistics or unfinished traversal work |

The report intentionally does not include row samples or full row data.

### How It Is Built

```
┌─────────────────────────────────────────────────────────────────────────┐
│                    SUBSET IMPACT REPORT                                 │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                         │
│  Get-SubsetTableStatistics                                              │
│       │                                                                 │
│       ├─► Table impact: subset rows + PK size                           │
│       │                                                                 │
│  sys.tables + sys.partitions                                            │
│       │                                                                 │
│       ├─► Original row counts for every user table                      │
│       │                                                                 │
│  DatabaseInfo.Tables                                                    │
│       │                                                                 │
│       ├─► Table data KB, historic/deletable flags                       │
│       │                                                                 │
│  SqlSizer.Operations WHERE SessionId = ...                              │
│       │                                                                 │
│       ├─► Traversal progress, max depth, state/depth breakdown          │
│       │                                                                 │
│  SqlSizer_{SessionId}.* processing tables                               │
│       │                                                                 │
│       └─► Distinct FK ids reached during traversal                      │
│                                                                         │
│  SqlSizer.ForeignKeys + SqlSizer.Tables                                 │
│       │                                                                 │
│       └─► Reached and unreached relationship lists                      │
│                                                                         │
└─────────────────────────────────────────────────────────────────────────┘
```

Table size impact is estimated proportionally from measured `DatabaseInfo` table statistics:

```
EstimatedDataKB = TableDataKB * SubsetRows / OriginalRows
```

Original row counts are read from SQL Server metadata when the report is generated. If `Get-DatabaseInfo` was run without measured table sizes, row impact still works but size fields are `$null` and the report includes a warning.

### Usage

```powershell
$report = Get-SubsetImpactReport -Database $db -SessionId $sid `
    -DatabaseInfo $info -ConnectionInfo $conn

$report.Summary
$report.Tables | Sort-Object EstimatedDataKB -Descending |
    Format-Table SchemaName, TableName, SubsetRows, OriginalRows, RowsExcluded, PercentOfOriginalRows, EstimatedDataKB

$report.Relationships.Unreached |
    Format-Table Name, FromSchema, FromTable, ToSchema, ToTable
```

Export the same report without external dependencies:

```powershell
Export-SubsetImpactReport -Database $db -SessionId $sid `
    -DatabaseInfo $info -ConnectionInfo $conn `
    -Path ".\subset-impact.json" -Format Json

Export-SubsetImpactReport -Database $db -SessionId $sid `
    -DatabaseInfo $info -ConnectionInfo $conn `
    -Path ".\subset-impact.md" -Format Markdown

Export-SubsetImpactReport -Database $db -SessionId $sid `
    -DatabaseInfo $info -ConnectionInfo $conn `
    -Path ".\subset-impact.html" -Format Html
```

`Get-SubsetUnreachableEdges` uses the same relationship analysis and returns only the unreached foreign key edges for a session.

---

## Advanced Features

### Interactive Mode

Run traversal one iteration at a time for debugging or inspection:

```powershell
# Initialize (Iteration = 0)
$result = Find-Subset -Database $db -SessionId $sid -DatabaseInfo $info `
    -ConnectionInfo $conn -Interactive $true -Iteration 0

# Step through iterations
$iteration = 1
while (-not $result.Finished) {
    # Inspect state between iterations
    Get-SubsetTables -Database $db -SessionId $sid `
        -DatabaseInfo $info -ConnectionInfo $conn | Format-Table

    # Run next iteration
    $result = Find-Subset -Database $db -SessionId $sid -DatabaseInfo $info `
        -ConnectionInfo $conn -Interactive $true -Iteration $iteration
    $iteration++
}
```

### Batch Processing (MaxBatchSize)

Controls how many rows are processed per operation:

```powershell
# Process at most 10,000 rows per operation
Find-Subset -Database $db -SessionId $sid -DatabaseInfo $info `
    -ConnectionInfo $conn -MaxBatchSize 10000
```

**How it works:**
- Default is `-1` (unlimited) - process all rows in one operation
- When set, each CTE query includes `TOP ($MaxBatchSize)`
- If an operation has more rows than the batch size, `Set-OperationInProgress` only advances `Processed` by the batch amount
- After execution, `Complete-Operations` resets partially-complete operations to `Status = NULL` for re-queuing
- This bounds memory usage and prevents any single SQL statement from running too long

### Query Caching

Generated SQL is cached to avoid re-generating complex CTE queries:

```
Cache Key Format: "{SchemaName}_{TableName}_{StateInt}_{OUT|IN}"

Example: "Sales_Customer_1_OUT" → cached CTE for Customer outgoing FKs with Include state
```

The cache is keyed by table + state + direction because the generated SQL is identical across iterations—only the `Iteration` column in `SourceRecords` CTE changes, and that's handled by the `WHERE src.Iteration IN (...)` clause.

For `Find-RemovalSubset`, the cache uses `##DEPTH##` and `##ITERATION##` placeholders that are string-replaced at execution time.

### Cycle Safety

Self-referential tables and circular FK chains are handled by key-level deduplication in the target processing table. Every traversal query checks `NOT EXISTS` before inserting a discovered row, so a row can be reached through many paths but only enters the closure once.

This is deliberately based on row identity rather than FK-name suppression. A self-referential chain like `Employee.ManagerID -> Employee.EmployeeID` can keep walking up the hierarchy until it reaches a row already present in the closure.

### Composite Key Support

SqlSizer handles tables with multi-column primary keys transparently. A table with a 3-column composite PK gets `Key0`, `Key1`, `Key2` columns in its processing table:

```sql
-- For table with PK (OrderID, ProductID, LineNumber)
CREATE TABLE SqlSizer_abc123.Sales_OrderDetail (
    Id INT IDENTITY(1,1) PRIMARY KEY,
    Key0 INT NOT NULL,          -- OrderID
    Key1 INT NOT NULL,          -- ProductID
    Key2 SMALLINT NOT NULL,     -- LineNumber
    [State] TINYINT NOT NULL,
    [Source] SMALLINT NULL,
    [Depth] SMALLINT NOT NULL,
    [Fk] SMALLINT,
    [Iteration] INT NOT NULL
);
```

The CTE queries automatically generate the correct number of join conditions and column mappings for any PK size.

### Temporal Tables

SqlSizer recognizes SQL Server's system-versioned temporal tables via `TableInfo` flags:

| Flag | Meaning |
|------|---------|
| `IsHistoric` | This table IS a history table (the "shadow" table) |
| `HasHistory` | This table HAS a history table (it's system-versioned) |
| `HistoryOwner` | Name of the main table (set on history tables) |
| `HistoryOwnerSchema` | Schema of the main table |

When processing temporal tables, SqlSizer includes the main table in the subset. History tables are tracked via the `IsHistoric` flag for appropriate handling during copy operations.

---

## Common Scenarios

### Scenario 1: Create Development Database from Production

**Goal**: Create a small, realistic test database with 50 customers and all their data.

```powershell
# Select 50 random active customers
$query = New-Object -TypeName SqlSizerQuery
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
$query = New-Object -TypeName SqlSizerQuery
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

### Scenario 4: Review Subset Impact Before Copy or Delete

**Goal**: Explain what a session found before moving or removing data.

```powershell
# Find subset or removal subset first
Find-Subset -Database $db -SessionId $sessionId `
    -DatabaseInfo $info -ConnectionInfo $connection

# Review the impact in PowerShell
$report = Get-SubsetImpactReport -Database $db -SessionId $sessionId `
    -DatabaseInfo $info -ConnectionInfo $connection

$report.Summary
$report.Tables | Format-Table SchemaName, TableName, SubsetRows, OriginalRows, RowsExcluded, PercentOfOriginalRows
$report.Relationships.Reached | Format-Table Name, FromSchema, FromTable, ToSchema, ToTable

# Write a shareable report
Export-SubsetImpactReport -Database $db -SessionId $sessionId `
    -DatabaseInfo $info -ConnectionInfo $connection `
    -Path ".\subset-impact.html" -Format Html
```

### Scenario 5: Long-Running Subset with Checkpointing

**Goal**: Extract a large subset that may take hours, with crash recovery.

```powershell
$sessionId = Start-SqlSizerSession -Database $db -ConnectionInfo $conn -DatabaseInfo $info

# Define seed records
$query = New-Object -TypeName SqlSizerQuery
$query.State = [TraversalState]::Include
$query.Schema = "Sales"
$query.Table = "Region"
$query.KeyColumns = @('RegionID')
$query.Where = "[`$table].RegionName = 'North America'"

Initialize-StartSet -Database $db -Queries @($query) -SessionId $sessionId `
    -DatabaseInfo $info -ConnectionInfo $conn

# Run with checkpointing (saves every 3 iterations) and batch limiting
Find-Subset -Database $db -SessionId $sessionId -DatabaseInfo $info -ConnectionInfo $conn `
    -CheckpointPath "C:\temp\na_subset.json" -CheckpointInterval 3 `
    -MaxBatchSize 50000

# If it crashes, resume:
# Find-Subset -Database $db -SessionId $sessionId -DatabaseInfo $info -ConnectionInfo $conn `
#     -CheckpointPath "C:\temp\na_subset.json" -Resume
```

### Scenario 6: Subset with Configuration

**Goal**: Extract data but exclude audit tables and limit depth on history tables.

```powershell
$config = New-Object TraversalConfiguration

# Ignore audit tables entirely
$config.AddIgnoredTable("dbo", "AuditLog")
$config.AddIgnoredTable("dbo", "ChangeHistory")

# Limit traversal depth on large history tables
$historyRule = [TraversalRule]::new("Sales", "OrderStatusHistory")
$historyRule.SetMaxDepth(1)
$config.AddRule($historyRule)

# Force-exclude lookup tables (they'll be populated separately)
$lookupRule = [TraversalRule]::new("dbo", "CountryCode")
$lookupRule.SetStateOverride([TraversalState]::Exclude)
$config.AddRule($lookupRule)

Find-Subset -Database $db -SessionId $sid -DatabaseInfo $info `
    -ConnectionInfo $conn -TraversalConfiguration $config
```

### Scenario 7: Compare Two Subsets

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
    $query = New-Object -TypeName SqlSizerQuery
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
    $query = New-Object -TypeName SqlSizerQuery
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

## Copy-Database

`Copy-Database` creates a full clone of a database using SQL Server's backup/restore mechanism.

### How It Works

```
┌─────────────────────────────────────────────────────────────────────────┐
│                    COPY-DATABASE PROCESS                                │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                         │
│  1. Backup source database                                             │
│     → Queries SQL Server for default backup path                       │
│     → BACKUP DATABASE [Source] TO DISK = '{path}\Source.bak'           │
│                                                                         │
│  2. Read backup metadata                                               │
│     → RESTORE FILELISTONLY FROM DISK = '{path}\Source.bak'             │
│     → Gets logical file names (data file, log file)                    │
│                                                                         │
│  3. Get default data/log paths                                         │
│     → Queries SQL Server for default data directory                    │
│     → Queries SQL Server for default log directory                     │
│                                                                         │
│  4. Restore as new database                                            │
│     → RESTORE DATABASE [NewDB] FROM DISK = '{path}\Source.bak'        │
│       WITH MOVE 'DataFile' TO '{data_path}\NewDB.mdf',                │
│            MOVE 'LogFile'  TO '{log_path}\NewDB_log.ldf',             │
│            REPLACE, RECOVERY                                           │
│     → Reports progress at 25%, 50%, 90%, 100%                         │
│                                                                         │
│  5. Cleanup                                                            │
│     → Deletes backup file                                              │
│                                                                         │
└─────────────────────────────────────────────────────────────────────────┘
```

### Usage

```powershell
Copy-Database -Database "Production" -NewDatabase "Production_Subset" `
    -ConnectionInfo $connection
```

This is typically used before `Copy-DataFromSubset` to create a target database with the same schema, then clear it and populate with only the subset data.

---

## Azure SQL Support

SqlSizer supports Azure SQL Database with token-based authentication and Azure-specific operations.

### Connection with Access Token

```powershell
$connection = New-SqlConnectionInfo -Server "myserver.database.windows.net"
$connection.AccessToken = $azureToken
$connection.EncryptConnection = $true
```

### Azure-Specific Cmdlets

| Cmdlet | Purpose |
|--------|---------|
| `Copy-AzDatabase` | Copy Azure SQL database within Azure |
| `Import-SubsetFromAzStorageContainer` | Import subset data from Azure Blob Storage |

### Invoke-SqlcmdEx Azure Support

The internal `Invoke-SqlcmdEx` function handles Azure transparently:
- Passes `-AccessToken` to `Invoke-Sqlcmd` when set
- Configures `-Encrypt` and `-TrustServerCertificate` based on `EncryptConnection`
- Compatible with both `SqlServer` module (v22+) and legacy `SQLPS`

---

## Performance Considerations

### Memory Efficiency

| Feature | Benefit |
|---------|---------|
| **Server-side processing** | All heavy lifting done in SQL Server, not PowerShell |
| **Streaming results** | Results paged, not loaded entirely into memory |
| **No record duplication** | Each record tracked once regardless of discovery paths |
| **O(1) lookups** | Hashtable-based table/FK lookups instead of linear search |

### Query Optimization

| Optimization | Description |
|--------------|-------------|
| **CTE-based queries** | Better query plan optimization by SQL Server |
| **Batch processing** | Configurable `MaxBatchSize` for controlled resource usage |
| **Batched FK queries** | Multiple FK relationships processed in single SQL execution |
| **Indexed processing tables** | Key columns + State (or Depth) indexed for fast lookups |
| **Iteration-based filtering** | SourceRecords CTE only reads current iteration's rows |

### Best Practices

| Scenario | Recommendation |
|----------|----------------|
| Large databases (>1M rows) | Set `MaxBatchSize` to 10000-50000 |
| Complex schemas (>100 tables) | Start with `FullSearch = $false`, expand if needed |
| Slow performance | Check for missing indexes on FK columns |
| Azure SQL | Connection already optimized for cloud |
| Large queued operations | Use `UseDfs = $true` to prioritize the largest remaining operation |
| Long-running traversals | Enable checkpointing with `-CheckpointPath` |
| High-fanout tables | Use `TraversalConfiguration` with `MaxDepth` or `Top` limits |

### Index Recommendations

```powershell
# Check for missing FK indexes
$info = Get-DatabaseInfo -Database $db -ConnectionInfo $connection

# This cmdlet creates indexes on FK columns that lack them
Install-ForeignKeyIndexes -Database $db -ConnectionInfo $connection -DatabaseInfo $info
```

**Critical indexes to verify:**
- All primary key columns (usually automatic)
- All foreign key columns (often missing!)
- Columns in WHERE clauses of your seed queries

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
| **Checkpoint resume fails** | SessionId mismatch | Ensure same SessionId as original run |
| **Traversal seems stuck** | High-fanout table exploding | Add `TraversalConfiguration` with `Top` or `MaxDepth` limits |

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

**Check Operations Status:**
```powershell
$sql = @"
SELECT
    t.[Schema] + '.' + t.TableName AS [Table],
    o.[State], o.Depth, o.ToProcess, o.Processed,
    CASE o.Status WHEN 0 THEN 'In Progress' WHEN 1 THEN 'Complete' ELSE 'Pending' END AS Status
FROM SqlSizer.Operations o
INNER JOIN SqlSizer.Tables t ON o.[Table] = t.Id
WHERE o.SessionId = '$sessionId'
ORDER BY o.Depth, t.[Schema], t.TableName
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
| **Seed Record** | Starting point for traversal - records you explicitly specify via `SqlSizerQuery` |
| **Processing Table** | Session-specific table tracking discovered records per source table |
| **Session** | Isolated workspace with its own schema and processing tables |
| **SessionId** | Unique identifier for a session (GUID with hyphens removed) |
| **Traversal State** | Classification of a record: Include, Exclude, Pending, InboundOnly, IncludeFull |
| **Outgoing FK** | Following FK from child table to parent (dependency direction) |
| **Incoming FK** | Following FK from parent to child (dependent direction) |
| **FullSearch** | Mode that follows both outgoing and incoming FKs |
| **Depth** | Number of hops from seed records |
| **Iteration** | Processing cycle number when record was discovered |
| **Operation** | A unit of work in `SqlSizer.Operations`: process N rows from one table/state/depth |
| **BFS** | Breadth-First Search - processes all records at same depth before going deeper |
| **UseDfs** | Legacy size-first traversal ordering - processes the queued operation with the most remaining rows |
| **CTE** | Common Table Expression - SQL feature for readable subqueries |
| **TraversalConfiguration** | Object for customizing per-table traversal behavior (rules, constraints, ignores) |
| **StateOverride** | Forces a specific TraversalState for a table, bypassing normal transition logic |
| **TraversalConstraints** | Limits on traversal depth or row count for a specific table |
| **Checkpoint** | JSON file recording traversal progress for crash recovery |
| **Structure** | Internal class mapping tables to their processing table names via signatures |
| **Signature** | A table's `SchemaName_TableName` string, used to name its processing table |

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
| `Get-SubsetImpactReport` | Build impact report | PSObject with Summary, Tables, Relationships, Operations, Warnings |
| `Export-SubsetImpactReport` | Export impact report | JSON, Markdown, or HTML file |
| `Copy-DataFromSubset` | Copy to another DB | (side effect) |

### Data Operations

| Cmdlet | Purpose |
|--------|---------|
| `Copy-Database` | Clone database via backup/restore |
| `Clear-Database` | Delete all data from tables |
| `Remove-FoundSubsetFromDatabase` | Delete subset records in FK order |
| `Import-SubsetFromFileSet` | Import from file-based export |

### Checkpoint & Resume

| Cmdlet | Purpose |
|--------|---------|
| `Get-SubsetCheckpoint` | Inspect a checkpoint file |
| `Resume-Subset` | Resume a Find-Subset from checkpoint |
| `Resume-RemovalSubset` | Resume a Find-RemovalSubset from checkpoint |

### Maintenance

| Cmdlet | Purpose |
|--------|---------|
| `Clear-SqlSizerSession` | Remove single session |
| `Clear-SqlSizerSessions` | Remove ALL sessions |
| `Get-SqlSizerInfo` | List active sessions and metadata |
| `Disable-ForeignKeys` | Temporarily disable FK constraints |
| `Enable-ForeignKeys` | Re-enable FK constraints |
| `Test-ForeignKeys` | Validate FK integrity |
| `Install-ForeignKeyIndexes` | Create missing FK indexes |
| `Test-DatabaseOnline` | Check database availability |
| `Test-Queries` | Validate seed queries before execution |

### Azure Operations

| Cmdlet | Purpose |
|--------|---------|
| `Copy-AzDatabase` | Copy Azure SQL database |
| `Import-SubsetFromAzStorageContainer` | Import from Azure Blob Storage |

---

## Further Reading

**In This Repository:**
- [Examples/AdventureWorks2019/Subset/](../Examples/AdventureWorks2019/Subset/) - Working subset examples
- [Examples/AdventureWorks2019/Removal/](../Examples/AdventureWorks2019/Removal/) - Data removal examples
- [Examples/Azure/AzureSQL/](../Examples/Azure/AzureSQL/) - Azure SQL examples
- [README.md](../README.md) - Quick start and feature overview
- [CHANGELOG.md](../CHANGELOG.md) - Version history and migration guides

**Example Scripts:**
- [00-Simple-Find-Subset-Example.ps1](../Examples/AdventureWorks2019/Subset/00-Simple-Find-Subset-Example.ps1) - Basic subset usage
- [02-Create-New-Database-With-Subset.ps1](../Examples/AdventureWorks2019/Subset/02-Create-New-Database-With-Subset.ps1) - Full database creation workflow
- [05-Interactive-Subset-Search.ps1](../Examples/AdventureWorks2019/Subset/05-Interactive-Subset-Search.ps1) - Interactive mode example
- [09-Two-Phase-Search-Strategy.ps1](../Examples/AdventureWorks2019/Subset/09-Two-Phase-Search-Strategy.ps1) - Advanced multi-phase approach
- [01-Basic-Data-Removal.ps1](../Examples/AdventureWorks2019/Removal/01-Basic-Data-Removal.ps1) - Safe deletion workflow

---

*Last updated: March 2026 | SqlSizer-MSSQL v2.0.2*
