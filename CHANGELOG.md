# Changelog

All notable changes to SqlSizer-MSSQL will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- New refactored algorithms: `Find-Subset-Refactored` and `Find-RemovalSubset-Refactored`
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
- Azure Synapse SQL Pool support (limited)
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

### To Refactored Algorithms
1. Replace `Find-Subset` with `Find-Subset-Refactored`
2. Replace `Find-RemovalSubset` with `Find-RemovalSubset-Refactored`
3. All parameters remain the same (100% backward compatible)
4. Optionally migrate from `ColorMap` to `TraversalConfiguration` (recommended)

### Backward Compatibility
All original functions remain available:
- `Find-Subset` - Original algorithm (still supported)
- `Find-RemovalSubset` - Original removal algorithm (still supported)
- Legacy types (`Color`, `ColorMap`, etc.) continue to work

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
