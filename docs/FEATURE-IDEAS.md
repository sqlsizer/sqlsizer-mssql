# Feature Ideas & Improvement Roadmap

> Generated: March 2026. A prioritized list of bugs, quick wins, and strategic features to make SqlSizer-MSSQL more valuable.

---

## Table of Contents

1. [Bugs to Fix First](#bugs-to-fix-first)
2. [High-Impact Quick Wins (< 1 day)](#high-impact-quick-wins--1-day)
3. [Medium-Effort, High-Value (1–3 days)](#medium-effort-high-value-13-days)
4. [Strategic / Large Effort (> 3 days)](#strategic--large-effort--3-days)
5. [Test Coverage Gaps](#test-coverage-gaps)

---

## Bugs to Fix First

| # | Bug | Details | Effort |
|---|-----|---------|--------|
| 1 | **`Get-SubsetTableXml` missing `$SessionId` parameter** | The function references `$SessionId` but never declares it as a parameter. It will produce incorrect SQL at runtime. | 15 min |
| 2 | **Module manifest version mismatch** | `SqlSizer-MSSQL.psd1` says `ModuleVersion = '2.0.1'` but CHANGELOG documents version `2.0.2`. | 5 min |
| 3 | **`CmdletsToExport` incomplete** | Several public functions (`Install-SqlSizerCore`, `Install-SqlSizerExportViews`, `Install-SqlSizerResultViews`, `Install-SqlSizerSecureViews`, `Install-SqlSizerSessionTables`, `New-ForeignKey`) exist in `Public/` but are missing from `CmdletsToExport` in the manifest. | 15 min |
| 4 | **`Write-Host` in public functions** | `Remove-Table` and `Remove-Schema` use `Write-Host` for messages like "Schema doesn't exist" — this breaks automation, piping, and transcript capture. Should use `Write-Warning` or `Write-Verbose`. | 30 min |

---

## High-Impact Quick Wins (< 1 day)

| # | Feature | Details | Effort |
|---|---------|---------|--------|
| 5 | **`New-SqlSizerQuery` convenience function** | Replace the verbose `New-Object -TypeName SqlSizerQuery` + property-setting pattern with `New-SqlSizerQuery -Schema "Sales" -Table "Customer" -State Include -Top 10 -Where "..."`. Much better developer experience. | 2 hrs |
| 6 | **`New-TraversalConfiguration` convenience function** | Same builder pattern — a single function call instead of manual object construction. | 2 hrs |
| 7 | **Configurable query timeout** | `Invoke-SqlcmdEx` hardcodes `QueryTimeout = 65535`. Should accept a parameter or read from `SqlConnectionInfo`. | 1 hr |
| 8 | **SQL INSERT script export** | Add `Get-SubsetTableSql` that generates `INSERT INTO` statements — useful for applying subsets without SqlSizer installed on the target. | 4–6 hrs |

---

## Medium-Effort, High-Value (1–3 days)

| # | Feature | Details | Effort |
|---|---------|---------|--------|
| 9 | **`-WhatIf` / `-Confirm` on destructive operations** | `Remove-FoundSubsetFromDatabase`, `Remove-Table`, `Clear-Database`, `Remove-ForeignKeys`, `Remove-Schema`, `Uninstall-SqlSizer` have zero `SupportsShouldProcess`. Users can accidentally delete data with no safety net. This is a PowerShell best practice gap. | 2 days |
| 10 | **Pipeline support** | Zero functions use `ValueFromPipeline`. `Get-SubsetTables` output should naturally pipe into `Get-SubsetTableJson`, `Get-SubsetTableRows`, `Get-SubsetTableCsv`, etc. Currently every downstream function requires manual parameter passing. | 2 days |
| 11 | **Comment-based help** | Only 3 of ~98 public functions have `.SYNOPSIS`/`.PARAMETER`/`.EXAMPLE` blocks. `Get-Help` returns nothing useful for almost everything. | 5+ days (can be incremental) |
| 12 | **Configuration file support** | `Export-SubsetConfiguration` / `Import-SubsetConfiguration` to save/load query definitions, traversal settings, and ignored tables as JSON. Makes operations repeatable and version-controllable. | 2 days |
| 13 | **Session auto-cleanup** | Sessions can be orphaned if scripts crash. Add session expiration metadata and a `Clear-ExpiredSqlSizerSessions -OlderThan (Get-Date).AddHours(-24)` function. | 1 day |
| 14 | **Dry-run / preview mode** | A `-Preview` parameter on `Find-Subset` that traverses the schema graph without executing SQL against data. Would show which FK paths would be traversed. Or an `-EstimateOnly` mode that does `COUNT(*)` queries instead of full traversal. | 2–3 days |
| 15 | **Structured logging** | Configurable log levels, log-to-file option, structured output showing which FK was traversed, how many rows discovered, which tables skipped. Currently only sparse `Write-Verbose` usage. | 2 days |
| 16 | **Excel export** | Add `Get-SubsetTableExcel` using the `ImportExcel` module. Commonly requested for business users. | 1 day |
| 17 | **Cancellation support** | `Find-Subset` loop has no clean cancellation mechanism. Should support graceful interruption for long-running traversals. | 1–2 days |
| 18 | **Parquet export** | Add export to Parquet format using the `Parquet.Net` library — increasingly standard for data engineering and analytics workloads. | 2 days |
| 19 | **Better SQL injection protection** | While `Initialize-StartSet` validates WHERE clauses, other functions like `Save-Subset` interpolate user input directly into SQL. A defense-in-depth approach with parameterized queries would be safer. | 3 days |
| 20 | **Per-table batch size control** | `MaxBatchSize` is global. For databases with some very large tables and some small ones, per-table batch sizes (via `TraversalConstraints`) would allow fine-tuning. | 1–2 days |
| 21 | **Inconsistent parameter naming** | `Copy-DataFromSubset` uses `-Source`/`-Destination` while all others use `-Database`. Standardize for a consistent API. | 2–3 hrs |
| 22 | **Session listing improvements** | `Get-SqlSizerInfo` exists but doesn't show session creation time, associated queries, or size. Add a `Get-SqlSizerSessions` that returns structured objects with metadata. | 4 hrs |

---

## Strategic / Large Effort (> 3 days)

| # | Feature | Details | Effort |
|---|---------|---------|--------|
| 23 | **Data masking / anonymization** | GDPR compliance is a top concern when creating test databases from production. Built-in masking rules (email → fake, names → randomized, SSN → zeroed) applied during subset export would be extremely valuable. Could integrate with the existing "Secure" view concept. This is the single biggest differentiator opportunity. | 5–7 days |
| 24 | **Comprehensive error handling** | Most public functions (e.g., `Copy-DataFromSubset`, `Copy-Database`, `Remove-Schema`, `Save-Subset`, `Enable-ForeignKeys`) have zero `try/catch` blocks. A failed SQL call mid-operation leaves the database in an inconsistent state with no recovery guidance. | 5+ days |
| 25 | **Checkpoint/resume for long traversals** | For large databases, `Find-Subset` can run for hours. No way to save progress and resume after failure. Could leverage the existing `Iteration` tracking and `StartIteration` parameter. | 2–3 days |
| 26 | **Expand unit test coverage** | Code coverage only covers `TraversalHelpers.ps1` and `QueryBuilders.ps1`. No unit tests for: `Get-DatabaseInfo` (531 lines), `Invoke-SqlcmdEx`, `Copy-DataFromSubset`, session management, export functions, Azure functions, FK management functions. ~90 untested public functions. | 10+ days |
| 27 | **Azure enhanced features** | Missing: Managed Identity auth, Azure Key Vault integration for credentials, Azure DevOps pipeline tasks, support for Azure SQL Elastic Pools, Azure Synapse compatibility, retry policies for transient Azure errors. | Varies (1–2 days each) |
| 28 | **Parallel traversal** | `Find-Subset` processes one operation at a time. For databases with many independent FK chains, parallel processing of non-conflicting operations could significantly reduce traversal time. | 5+ days |
| 29 | **Web UI / dashboard** | A simple web dashboard showing session progress, table counts, FK graph visualization (building on the existing `Get-SubsetSchemaJson` / `Get-DatabaseSchemaJson` functions that already emit graph data). | 10+ days |

---

## Test Coverage Gaps

| Area | Current State | Gap |
|------|--------------|-----|
| TraversalHelpers | 589 lines of unit tests | Well covered |
| QueryBuilders | 522 lines of unit tests | Well covered |
| ValidationHelpers | 454 lines of unit tests | Well covered |
| Find-Subset (integration) | 1,458 lines | Good coverage for core algorithm |
| Find-RemovalSubset (integration) | 800 lines | Good coverage |
| Get-DatabaseInfo | No tests | 531 lines untested |
| Invoke-SqlcmdEx | No tests | Core SQL execution untested |
| Copy-DataFromSubset | No tests | Critical data path untested |
| Session management (Start/Clear) | No tests | Lifecycle untested |
| Export functions (JSON/CSV/XML) | No tests | Output correctness unverified |
| Azure functions (Copy-AzDatabase, etc.) | No tests | Cloud operations untested |
| FK management (Enable/Disable/Edit/Remove) | No tests | Schema operations untested |
| Install/Uninstall-SqlSizer | No tests | Installation correctness unverified |
| Save-Subset / Compare-SavedSubsets | No tests | Historical features untested |

---

## Recommended Priority

**Phase 1 — Quick fixes (1 day):**
Fix bugs #1–4, add convenience functions #5–6, make timeout configurable #7.

**Phase 2 — PowerShell best practices (1 week):**
Add `-WhatIf`/`-Confirm` (#9), pipeline support (#10), comment-based help for top 20 functions (#11).

**Phase 3 — Usability & operations (2 weeks):**
Configuration files (#12), session auto-cleanup (#13), dry-run mode (#14), SQL INSERT export (#8), structured logging (#15).

**Phase 4 — Strategic differentiation (ongoing):**
Data masking (#23), comprehensive error handling (#24), expanded test coverage (#26), checkpoint/resume (#25).
