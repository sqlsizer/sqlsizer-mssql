# Changelog

All notable changes to SqlSizer-MSSQL will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [2.0.2] - 2026-02-08

### Breaking Changes
- **Removed legacy types**: `enum Color`, `ColorMap`, `ColorItem`, `ForcedColor`, `Query`, `TableInfo2WithColor`
- Functions now require `Query2[]` instead of `Query[]`: `Find-UnreachableTables`, `Test-Queries`, `Find-ReachableTables`, `Enable-ReachableIndexes`, `Disable-ReachableIndexes`, `Install-ForeignKeyIndexes`
- `Find-UnreachableTables` and `Test-Queries` now use `TraversalConfiguration` instead of `ColorMap`
- Database column `[Color]` renamed to `[State]` in all SQL DDL

### Added
- `TableInfo2WithState` class (replacement for `TableInfo2WithColor`)

### Changed
- All traversal functions now exclusively use `TraversalState` enum instead of `Color`
- SQL views now expose `sqlsizer_state` instead of `sqlsizer_color`

### Removed
- Deprecated example files using `Bidirectional` state (feature discontinued)

## [2.0.1] - 2026-02-07

### Fixed
- `Get-SubsetTableRows`: Fixed swapped SchemaName/TableName labels in SQL output
- `Copy-SubsetToDatabaseFileSet`: Fixed undefined variable `$connection` (now uses `$ConnectionInfo`)
- `Initialize-OperationsTable`: Fixed null check occurring after property access (potential runtime error)
- `Invoke-SqlcmdEx`: Fixed `$Silent` parameter type mismatch (was `[string]`, now `[bool]`)

## [2.0.0] - 2026-02-07

### Breaking Changes
- Removed legacy algorithm files: `Find-Subset.ps1` (old), `Find-RemovalSubset.ps1` (old), `Initialize-StartSet.ps1` (old)
- The refactored algorithms are now the canonical implementations (renamed from `-Refactored` suffix)
- Scripts using the legacy `ColorMap` parameter with `Find-Subset` will need to migrate to `TraversalConfiguration`

### Changed
- `Find-Subset-Refactored` → `Find-Subset` (function renamed, file renamed)
- `Find-RemovalSubset-Refactored` → `Find-RemovalSubset` (function renamed, file renamed)
- `Initialize-StartSet-Refactored` → `Initialize-StartSet` (function renamed, file renamed)
- All examples updated to use new function names
- Documentation updated to remove legacy/refactored distinction

### Removed
- Legacy `Find-Subset.ps1` (787 lines)
- Legacy `Find-RemovalSubset.ps1` (361 lines)
- Legacy `Initialize-StartSet.ps1` (70 lines)

## [1.0.6] - Previous Release

### Added
- Refactored algorithms: `Find-Subset` and `Find-RemovalSubset`
- Comprehensive test suite with 150+ unit tests
- Modular architecture with 16 helper functions in separate modules:
  - `TraversalHelpers.ps1` - State transition and constraint logic
  - `QueryBuilders.ps1` - SQL query generation
  - `ValidationHelpers.ps1` - Input validation
  - `ConfigurationBuilders.ps1` - Configuration builders
- Modern type system: `TraversalConfiguration`, `TraversalState`, etc.
- Dynamic key column generation supporting N-column primary keys
- CI/CD pipeline with GitHub Actions
- 12+ new documentation guides
- Modern examples in `ExamplesNew/` directory
- Test runner with code coverage support (`Tests\Run-Tests.ps1`)

### Changed
- Improved memory efficiency (50% reduction in refactored algorithm)
- Reduced code complexity (45% lower cyclomatic complexity)
- Enhanced error messages with actionable guidance
- Better verbose logging throughout
- Reorganized documentation structure

### Fixed
- Dynamic key column generation in `QueryBuilders.ps1` (removed hardcoded 8-column patterns)
- State transition edge cases in `TraversalHelpers.ps1`
- Configuration validation logic in `ValidationHelpers.ps1`
- Parameter handling in `New-SqlConnectionInfo.ps1`
- Multiple test suite issues for reliable execution
- Type system cleanup to remove duplicates

### Removed
- Authenticode digital signatures from all files (simplifies development)
- Hardcoded 8-column key patterns in SQL queries

## [1.0.6] - Previous Release

### Added
- Session reuse support
- Foreign key management in SqlSizer.Operations
- Multiple query/source support
- Concurrent subsetting capability
- DFS (Depth-First Search) algorithm option
- Interactive search modes
- JSON/CSV import/export capabilities
- Color map for traversal configuration
- Schema management operations
- Integrity check functions
- Trigger management

### Changed
- Improved `Find-RemovalSubset` performance
- Optimized `Remove-Table` speed
- Enhanced `MaxBatchSize` parameter handling
- Better handling of arrays in code
- Improved `Invoke-SqlcmdEx` error details
- Better database schema JSON export

### Fixed
- Bug in `Get-SubsetTableStatistics`
- Issues with `New-DataTableClone`
- Bug in `Clear-SqlSizerSession`
- Typos in various functions

## Version History Summary

### Beta/Alpha Releases (Prior versions)
- alpha16 - alpha1: Initial development and feature additions
- beta1 - beta9: Feature stabilization and bug fixes
- gamma1 - gamma8: Performance improvements
- 1.0.0 - 1.0.6: Production releases

Key milestones in earlier versions:
- Initial PowerShell module structure
- Core subset finding algorithm
- Azure SQL Database support
- Foreign key traversal
- Color map configuration
- Data removal capabilities
- Export/import functionality
- Schema operations
- Performance optimizations

## Migration Notes

### To Version 2.0.2
1. Replace `Query` with `Query2` and use `.State` instead of `.Color`
2. Replace `ColorMap` with `TraversalConfiguration` 
3. Replace `ColorItem` with `TraversalRule`
4. Replace `ForcedColor` with `StateOverride`
5. Replace `TableInfo2WithColor` with `TableInfo2WithState`
6. Update any direct SQL queries: column `[Color]` is now `[State]`

### Color → TraversalState Mapping
| Legacy Color | TraversalState |
|-------------|----------------|
| Green (2)   | Include (1)    |
| Red (1)     | Exclude (2)    |
| Yellow (3)  | Pending (3)    |
| Blue (4)    | InboundOnly (4)|
| Purple (5)  | *Removed*      |

### Backward Compatibility
All original functions remain available but require updated types:
- `Find-Subset` - Uses `Query2` and `TraversalConfiguration`
- `Find-RemovalSubset` - Removal algorithm (still supported)

## Contributing

See [Contributing Guide](CONTRIBUTING.md) for details on:
- Code style guidelines
- Testing requirements
- Pull request process
- Documentation standards

## Support

- **Issues:** [GitHub Issues](https://github.com/sqlsizer/sqlsizer-mssql/issues)
- **Discussions:** [GitHub Discussions](https://github.com/sqlsizer/sqlsizer-mssql/discussions)
- **Documentation:** [docs/](docs/)

---

**Legend:**
- `Added` - New features
- `Changed` - Changes in existing functionality
- `Deprecated` - Soon-to-be removed features
- `Removed` - Removed features
- `Fixed` - Bug fixes
- `Security` - Security fixes
