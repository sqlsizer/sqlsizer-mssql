![logo](https://avatars.githubusercontent.com/u/96390582?s=100&v=4)
# sqlsizer-mssql

A PowerShell module for extracting referentially-consistent data subsets from SQL Server and Azure SQL databases. SqlSizer traverses foreign key relationships from your "seed" records to discover all related data, ensuring your subset maintains full referential integrity.

**[Changelog →](CHANGELOG.md)** | **[How It Works →](docs/HOW-IT-WORKS.md)**

---

## Core Features

| Feature | Description |
|---------|-------------|
| **Referential integrity** | Automatically follows FK relationships to include all required data |
| **No size limits** | Works with any database or subset size |
| **Composite key support** | Handles any PK/FK column count and data types |
| **Server-side processing** | All heavy lifting in SQL Server - minimal PowerShell memory |
| **Graph traversal** | BFS or legacy size-first ordering with set-based deduplication for cycle safety |
| **CTE-based SQL** | Optimized, readable query generation |
| **Checkpoint/resume** | Save progress and recover from crashes on long operations |
| **Traversal configuration** | Per-table state overrides, depth limits, row caps, ignored tables |
| **Subset impact reports** | Review table impact, progress, and reached/unreached relationships before copy/delete/export |
| **Azure SQL support** | Token-based auth, Azure-specific operations |
| **Session isolation** | Multiple concurrent sessions without interference |

## Use Cases

| Scenario | Cmdlet |
|----------|--------|
| Create test databases from production data | `Find-Subset` + `Copy-DataFromSubset` |
| Safely delete records respecting FK constraints | `Find-RemovalSubset` + `Remove-FoundSubsetFromDatabase` |
| Review subset impact before copy/delete/export | `Get-SubsetImpactReport` / `Export-SubsetImpactReport` |
| Export data subsets as JSON/CSV/XML | `Get-SubsetTableJson`, `Get-SubsetTableCsv` |
| Clone databases | `Copy-Database` |
| Compare data across subsets | `Compare-SavedSubsets` |
| Export to Azure Blob Storage | `Copy-SubsetToAzStorageContainer` |

---

## Quick Start

```powershell
# 1. Connect and analyze database
$connection = New-SqlConnectionInfo -Server "localhost" -Username "sa" -Password $password
$info = Get-DatabaseInfo -Database "MyDB" -ConnectionInfo $connection
$sessionId = Start-SqlSizerSession -Database "MyDB" -ConnectionInfo $connection -DatabaseInfo $info

# 2. Define seed records
$query = New-Object -TypeName SqlSizerQuery
$query.State = [TraversalState]::Include
$query.Schema = "Sales"
$query.Table = "Customer"
$query.KeyColumns = @('CustomerID')
$query.Top = 10

# 3. Find subset
Initialize-StartSet -Database "MyDB" -Queries @($query) -SessionId $sessionId -DatabaseInfo $info -ConnectionInfo $connection
Find-Subset -Database "MyDB" -SessionId $sessionId -DatabaseInfo $info -ConnectionInfo $connection

# 4. View results and impact
Get-SubsetTables -Database "MyDB" -SessionId $sessionId -DatabaseInfo $info -ConnectionInfo $connection | Format-Table
Get-SubsetImpactReport -Database "MyDB" -SessionId $sessionId -DatabaseInfo $info -ConnectionInfo $connection

# 5. Cleanup
Clear-SqlSizerSession -Database "MyDB" -SessionId $sessionId -ConnectionInfo $connection
```

---

## Traversal States

Every discovered record is assigned a state that controls its inclusion and how traversal propagates:

| State | Value | Meaning | FK Traversal |
|-------|-------|---------|--------------|
| `Include` | 1 | Record is in the subset | Outgoing + Incoming (if FullSearch) |
| `Exclude` | 2 | Record is excluded | None - stops traversal |
| `Pending` | 3 | Candidate/bookkeeping state | Not returned in subset outputs unless promoted to Include |
| `InboundOnly` | 4 | For removal operations | Incoming only - finds dependents |
| `IncludeFull` | 5 | Include with forced incoming traversal | Outgoing + Incoming (always) |

Subset outputs include only closure states: `Include`, `IncludeFull`, and `InboundOnly`. `Pending` and `Exclude` rows can exist as traversal bookkeeping, but they are filtered from result views, exports, row reads, and table statistics.

### FullSearch Mode

| Mode | Outgoing FKs | Incoming FKs | Use When |
|------|--------------|--------------|----------|
| `FullSearch = $false` (default) | Yes | No | "Give me this record and everything it depends on" |
| `FullSearch = $true` | Yes | Yes | "Give me this record and everything connected to it" |

---

### Whole-Database Detection

`Find-Subset` warns when traversal looks likely to reach too much of the source database:

```powershell
Find-Subset -Database $db -SessionId $sid -DatabaseInfo $info -ConnectionInfo $conn `
    -MaxSubsetPercentOfSource 20 `
    -MaxReachableTablePercent 80 `
    -SubsetGuardCheckInterval 5 `
    -ThrowOnSubsetGuardExceeded $false
```

| Guard | Default | Description |
|-------|---------|-------------|
| `MaxSubsetPercentOfSource` | `20` | Runtime warning when included subset rows exceed this percentage of PK-bearing source rows. Use `0` to disable. |
| `MaxReachableTablePercent` | `80` | Preflight warning when metadata traversal can reach this percentage of PK-bearing user tables. Use `0` to disable. |
| `SubsetGuardCheckInterval` | `5` | Runtime guard check frequency in traversal iterations. |
| `ThrowOnSubsetGuardExceeded` | `$false` | Throw a terminating error instead of warning when the runtime row-ratio guard is exceeded. |

The guard is warn-only by default. Results include a `SubsetSizeGuard` object with preflight and runtime summaries.

---

## Traversal Configuration

Customize behavior per table with `TraversalConfiguration`:

```powershell
$config = New-Object TraversalConfiguration

# Ignore audit tables
$config.AddIgnoredTable("dbo", "AuditLog")

# Limit depth on high-fanout tables
$rule = [TraversalRule]::new("Sales", "OrderHistory")
$rule.SetMaxDepth(2).SetTop(1000)
$config.AddRule($rule)

# Force-exclude lookup tables
$rule = [TraversalRule]::new("dbo", "CountryCode")
$rule.SetStateOverride([TraversalState]::Exclude)
$config.AddRule($rule)

# Apply IncludeFull only to matching rows, then Include the rest
$vip = [TraversalRule]::new("dbo", "Accounts")
$vip.SetFilter("[`$table].[Tier] = 'VIP'").SetStateOverride([TraversalState]::IncludeFull)
$config.AddRule($vip)

$rest = [TraversalRule]::new("dbo", "Accounts")
$rest.SetStateOverride([TraversalState]::Include)
$config.AddRule($rest)

Find-Subset -Database $db -SessionId $sid -DatabaseInfo $info `
    -ConnectionInfo $conn -TraversalConfiguration $config
```

| Constraint | Description |
|------------|-------------|
| `StateOverride` | Force a specific TraversalState for a table |
| `MaxDepth` | Stop traversal after N hops |
| `Top` | Limit discovered rows |
| `IgnoredTables` | Skip tables entirely during traversal |
| `SourceFilter` | Only process when source table matches |
| `ForeignKeyFilter` | Only process via a specific FK |
| `Filter` | Apply a rule only to matching target rows, using `[$table]` as the target alias |

---

## Safe Data Removal

Find and delete records while respecting FK constraints:

```powershell
$query = New-Object -TypeName SqlSizerQuery
$query.State = [TraversalState]::InboundOnly
$query.Schema = "Sales"
$query.Table = "Customer"
$query.KeyColumns = @('CustomerID')
$query.Where = "[`$table].CustomerID = 123"

Initialize-StartSet -Database $db -Queries @($query) -SessionId $sid -DatabaseInfo $info -ConnectionInfo $conn
Find-RemovalSubset -Database $db -SessionId $sid -DatabaseInfo $info -ConnectionInfo $conn

# Preview
Get-SubsetTables -Database $db -SessionId $sid -DatabaseInfo $info -ConnectionInfo $conn | Format-Table

# Delete in correct FK order
Remove-FoundSubsetFromDatabase -Database $db -SessionId $sid -ConnectionInfo $conn
```

---

## Checkpoint & Resume

For long-running operations, save progress and recover from crashes:

```powershell
# Run with checkpointing (saves every 5 iterations)
Find-Subset -Database $db -SessionId $sid -DatabaseInfo $info -ConnectionInfo $conn `
    -CheckpointPath "C:\temp\checkpoint.json"

# Resume after crash
Find-Subset -Database $db -SessionId $sid -DatabaseInfo $info -ConnectionInfo $conn `
    -CheckpointPath "C:\temp\checkpoint.json" -Resume

# Or use convenience wrappers
Resume-Subset -Database $db -SessionId $sid -DatabaseInfo $info -ConnectionInfo $conn `
    -CheckpointPath "C:\temp\checkpoint.json"
```

---

## Subset Impact Reports

Before copying, deleting, or exporting data, generate a read-only report that explains what the current session found:

```powershell
$report = Get-SubsetImpactReport -Database $db -SessionId $sid `
    -DatabaseInfo $info -ConnectionInfo $conn

$report.Summary
$report.Tables | Format-Table SchemaName, TableName, SubsetRows, OriginalRows, RowsExcluded, PercentOfOriginalRows
$report.Relationships.Reached | Format-Table Name, FromSchema, FromTable, ToSchema, ToTable
```

Export the same report for review or audit:

```powershell
Export-SubsetImpactReport -Database $db -SessionId $sid `
    -DatabaseInfo $info -ConnectionInfo $conn `
    -Path ".\subset-impact.html" -Format Html

Export-SubsetImpactReport -Database $db -SessionId $sid `
    -DatabaseInfo $info -ConnectionInfo $conn `
    -Path ".\subset-impact.md" -Format Markdown
```

The report includes every original user table with original row counts, subset row counts, row reduction, estimated data KB when `DatabaseInfo` has measured table statistics, traversal operation progress, and reached/unreached foreign key relationships. It does not include row samples or full row data.

---

## Create Subset Database (Full Workflow)

```powershell
$conn = New-SqlConnectionInfo -Server "localhost" -Username "sa" -Password $password
$info = Get-DatabaseInfo -Database "Production" -ConnectionInfo $conn
$sid = Start-SqlSizerSession -Database "Production" -ConnectionInfo $conn -DatabaseInfo $info

try {
    # Define seeds
    $query = New-Object -TypeName SqlSizerQuery
    $query.State = [TraversalState]::Include
    $query.Schema = "Sales"
    $query.Table = "SalesOrder"
    $query.KeyColumns = @('SalesOrderID')
    $query.Top = 100

    Initialize-StartSet -Database "Production" -Queries @($query) `
        -SessionId $sid -DatabaseInfo $info -ConnectionInfo $conn

    Find-Subset -Database "Production" -SessionId $sid `
        -DatabaseInfo $info -ConnectionInfo $conn

    # Clone and populate
    Copy-Database -Database "Production" -NewDatabase "Production_Dev" -ConnectionInfo $conn
    $devInfo = Get-DatabaseInfo -Database "Production_Dev" -ConnectionInfo $conn

    Disable-ForeignKeys -Database "Production_Dev" -ConnectionInfo $conn -DatabaseInfo $devInfo
    Clear-Database -Database "Production_Dev" -ConnectionInfo $conn -DatabaseInfo $devInfo
    Copy-DataFromSubset -SourceDatabase "Production" -DestinationDatabase "Production_Dev" `
        -SessionId $sid -ConnectionInfo $conn -DatabaseInfo $info
    Enable-ForeignKeys -Database "Production_Dev" -ConnectionInfo $conn -DatabaseInfo $devInfo

    # Validate
    Test-ForeignKeys -Database "Production_Dev" -ConnectionInfo $conn -DatabaseInfo $devInfo
}
finally {
    Clear-SqlSizerSession -Database "Production" -SessionId $sid -ConnectionInfo $conn
}
```

---

## Installation

```powershell
# Prerequisites
Install-Module SqlServer -Scope CurrentUser
Install-Module dbatools -Scope CurrentUser
Install-Module Az -Scope CurrentUser  # Optional: for Azure SQL operations

# Install SqlSizer
Install-Module SqlSizer-MSSQL -Scope CurrentUser

# Import before use
Import-Module SqlSizer-MSSQL
```

---

## Key Cmdlets

### Core Operations

| Cmdlet | Purpose |
|--------|---------|
| `New-SqlConnectionInfo` | Create connection object (supports credentials and Azure tokens) |
| `Get-DatabaseInfo` | Extract database metadata (tables, FKs, columns, indexes) |
| `Start-SqlSizerSession` | Create isolated session with processing tables |
| `Initialize-StartSet` | Define seed records from `SqlSizerQuery` objects |
| `Find-Subset` | Find referentially-consistent subset via graph traversal |
| `Find-RemovalSubset` | Find all dependent records for safe deletion |

### Export & Copy

| Cmdlet | Purpose |
|--------|---------|
| `Get-SubsetTables` | List tables in subset with row counts |
| `Get-SubsetTableRows` | Retrieve actual row data |
| `Get-SubsetTableJson` / `Csv` / `Xml` | Export in various formats |
| `Copy-DataFromSubset` | Copy subset to another database |
| `Copy-Database` | Clone database via backup/restore |

### Reporting & Analysis

| Cmdlet | Purpose |
|--------|---------|
| `Get-SubsetImpactReport` | Return a scriptable report with table impact, traversal progress, and reached/unreached FK relationships |
| `Export-SubsetImpactReport` | Write the subset impact report as JSON, Markdown, or HTML |

### Checkpoint & Resume

| Cmdlet | Purpose |
|--------|---------|
| `Get-SubsetCheckpoint` | Inspect checkpoint file |
| `Resume-Subset` | Resume Find-Subset from checkpoint |
| `Resume-RemovalSubset` | Resume Find-RemovalSubset from checkpoint |

### Maintenance

| Cmdlet | Purpose |
|--------|---------|
| `Clear-SqlSizerSession` / `Sessions` | Remove session(s) |
| `Install-ForeignKeyIndexes` | Create missing FK indexes for performance |
| `Test-ForeignKeys` | Validate FK integrity |
| `Disable-ForeignKeys` / `Enable-ForeignKeys` | Toggle FK constraints |
| `Test-DatabaseOnline` | Check database availability |

### Azure

| Cmdlet | Purpose |
|--------|---------|
| `Copy-AzDatabase` | Copy Azure SQL database |
| `Import-SubsetFromAzStorageContainer` | Import from Azure Blob Storage |
| `Copy-SubsetToAzStorageContainer` | Export to Azure Blob Storage |

---

## Examples

See the [Examples/](Examples/) directory for 35+ complete working scripts:

| Category | Location | Description |
|----------|----------|-------------|
| Subset | [Subset/](Examples/AdventureWorks2019/Subset/) | Basic to advanced subset extraction (11 examples) |
| Removal | [Removal/](Examples/AdventureWorks2019/Removal/) | Safe data deletion strategies (8 examples) |
| Schema | [Schema/](Examples/AdventureWorks2019/Schema/) | Database schema operations |
| JSON | [JSON/](Examples/AdventureWorks2019/JSON/) | Import/export JSON data and schemas |
| Comparison | [Comparison/](Examples/AdventureWorks2019/Comparison/) | Compare databases and subsets |
| Visualization | [Visualization/](Examples/AdventureWorks2019/Visualization/) | Generate relationship color maps |
| Maintenance | [Maintenance/](Examples/AdventureWorks2019/Maintenance/) | Indexes, integrity checks, triggers |
| Azure SQL | [Azure/](Examples/Azure/AzureSQL/) | Azure-specific operations |

### Schema Visualizations

- [Demo01](https://sqlsizer.github.io/sqlsizer-mssql/Visualizations/Demo01/)
- [Demo02](https://sqlsizer.github.io/sqlsizer-mssql/Visualizations/Demo02/)
- [Demo03](https://sqlsizer.github.io/sqlsizer-mssql/Visualizations/Demo03/)

---

## Architecture Overview

```
┌──────────────────────────────────────────────────────────┐
│  PowerShell                                              │
│  ┌────────────────────────────────────────────────────┐  │
│  │  SqlSizer-MSSQL Module                             │  │
│  │  ├── Types (TraversalState, DatabaseInfo, ...)     │  │
│  │  ├── Public/ (100+ cmdlets)                        │  │
│  │  └── Shared/ (QueryBuilders, TraversalHelpers,     │  │
│  │               ValidationHelpers)                   │  │
│  └────────────────────────────────────────────────────┘  │
│                          │                                │
│                    SQL via Invoke-SqlcmdEx                │
│                          │                                │
└──────────────────────────┼───────────────────────────────┘
                           │
┌──────────────────────────┼───────────────────────────────┐
│  SQL Server              │                                │
│                          ▼                                │
│  ┌─────────────────────────────────────────────────────┐ │
│  │  SqlSizer schema        (metadata: tables, FKs)     │ │
│  │  SqlSizer_{SessionId}   (processing tables per      │ │
│  │                          session, one per table)     │ │
│  │  SqlSizerHistory        (saved subset records)      │ │
│  └─────────────────────────────────────────────────────┘ │
│                                                           │
│  All traversal work happens here via CTE-based queries   │
│  ► Minimal data transfer between PS and SQL Server       │
│                                                           │
└───────────────────────────────────────────────────────────┘
```

---

## Testing

```powershell
# Unit tests (no database required)
Invoke-Pester -Path .\Tests\ -Output Detailed

# Integration tests (requires SQL Server)
.\Tests\Run-IntegrationTests.ps1 -DataSize Tiny
```

The test suite includes 150+ tests covering:
- State transition logic (TraversalHelpers)
- SQL query generation (QueryBuilders)
- Input validation (ValidationHelpers)
- End-to-end integration with 32+ test tables (simple chains, diamonds, self-references, circular FKs, deep chains, composite keys, many-to-many)

See [Tests/README.md](Tests/README.md) for details.

---

## Documentation

| Guide | Description |
|-------|-------------|
| **[How It Works](docs/HOW-IT-WORKS.md)** | Complete technical reference: algorithms, state transitions, CTE generation, database schemas, traversal configuration, checkpoint/resume, advanced features, troubleshooting |

---

## License

MIT License - Copyright (c) 2022-2026 Marcin Gołębiowski

[![FOSSA Status](https://app.fossa.com/api/projects/git%2Bgithub.com%2Fsqlsizer%2Fsqlsizer-mssql.svg?type=large)](https://app.fossa.com/projects/git%2Bgithub.com%2Fsqlsizer%2Fsqlsizer-mssql?ref=badge_large)
