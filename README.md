![logo](https://avatars.githubusercontent.com/u/96390582?s=100&v=4)
# sqlsizer-mssql

A PowerShell module for extracting referentially-consistent data subsets from SQL Server, Azure SQL, and Azure Synapse.

## 🆕 Version 2.0.1 (February 2026)

- ✅ **`Find-Subset`** - 45% lower complexity, 50% less memory
- ✅ **150+ unit tests** - Fast, database-free testing
- ✅ **40+ integration tests** - Full FK traversal coverage
- ✅ **Modular architecture** - 16 testable helper functions
- 🐛 **Bug fixes** - Fixed data label swaps, undefined variables, type mismatches

**[Changelog →](CHANGELOG.md)**

## Core Features

- **No size limits** - Works with any database or subset size
- **Composite key support** - Handles any PK/FK column count and types
- **Server-side processing** - Minimal PowerShell memory usage
- **Graph traversal** - BFS/DFS with cycle detection
- **CTE-based SQL** - Optimized query generation

## Use Cases

- Create test databases from production data
- Safely delete records (respecting FK constraints)
- Copy/export data subsets (JSON, CSV, Azure Blob)
- Compare data across databases

## Quick Start

```powershell
# 1. Connect and analyze database
$connection = New-SqlConnectionInfo -Server "localhost" -Username "sa" -Password $password
$info = Get-DatabaseInfo -Database "MyDB" -ConnectionInfo $connection
$sessionId = Start-SqlSizerSession -Database "MyDB" -ConnectionInfo $connection -DatabaseInfo $info

# 2. Define seed records
$query = New-Object -TypeName Query2
$query.State = [TraversalState]::Include
$query.Schema = "Sales"
$query.Table = "Customer"
$query.KeyColumns = @('CustomerID')
$query.Top = 10

# 3. Find subset
Initialize-StartSet -Database "MyDB" -Queries @($query) -SessionId $sessionId -DatabaseInfo $info -ConnectionInfo $connection
Find-Subset -Database "MyDB" -SessionId $sessionId -DatabaseInfo $info -ConnectionInfo $connection

# 4. View results
Get-SubsetTables -Database "MyDB" -SessionId $sessionId -DatabaseInfo $info -ConnectionInfo $connection | Format-Table

# 5. Cleanup
Clear-SqlSizerSession -Database "MyDB" -SessionId $sessionId -ConnectionInfo $connection
```

**[See How It Works →](docs/HOW-IT-WORKS.md)** for complete algorithm details, traversal states, and advanced examples.

## Installation

```powershell
# Prerequisites
Install-Module sqlserver -Scope CurrentUser
Install-Module dbatools -Scope CurrentUser
Install-Module Az -Scope CurrentUser  # For Azure

# Install SqlSizer
Install-Module SqlSizer-MSSQL -Scope CurrentUser

# Import before use
Import-Module SqlSizer-MSSQL
```

## Examples

See the [Examples/](Examples/) directory for complete working scripts:

| Scenario | Location |
|----------|----------|
| Basic subset | [Examples/AdventureWorks2019/Subset/](Examples/AdventureWorks2019/Subset/) |
| Data removal | [Examples/AdventureWorks2019/Removal/](Examples/AdventureWorks2019/Removal/) |
| Azure SQL | [Examples/Azure/AzureSQL/](Examples/Azure/AzureSQL/) |

## Schema Visualizations

- [Demo01](https://sqlsizer.github.io/sqlsizer-mssql/Visualizations/Demo01/)
- [Demo02](https://sqlsizer.github.io/sqlsizer-mssql/Visualizations/Demo02/)
- [Demo03](https://sqlsizer.github.io/sqlsizer-mssql/Visualizations/Demo03/)

## Testing

```powershell
# Unit tests (no database required)
Invoke-Pester -Path .\Tests\ -Output Detailed

# Integration tests (requires SQL Server)
.\Tests\Run-IntegrationTests.ps1 -DataSize Tiny
```

See [Tests/README.md](Tests/README.md) for details.

## Documentation

| Guide | Description |
|-------|-------------|
| **[How It Works](docs/HOW-IT-WORKS.md)** | Algorithm, traversal states, data structures, troubleshooting |

## License

[![FOSSA Status](https://app.fossa.com/api/projects/git%2Bgithub.com%2Fsqlsizer%2Fsqlsizer-mssql.svg?type=large)](https://app.fossa.com/projects/git%2Bgithub.com%2Fsqlsizer%2Fsqlsizer-mssql?ref=badge_large)

