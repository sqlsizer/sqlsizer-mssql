# ExamplesNew Filename Improvements

This document summarizes the filename improvements made to the ExamplesNew folder structure.

## Naming Convention Changes

### Previous Convention
- Long redundant prefixes: `AdventureWorks2019_example_`
- Inconsistent numbering and naming patterns
- Database name repeated in every filename despite being in categorized folders

### New Convention
- **Numbered prefixes** (01-, 02-, etc.) for clear ordering
- **Descriptive action-based names** using kebab-case
- **Removed redundant prefixes** since files are already in categorized folders
- **Clearer intent** - filenames now clearly describe what the example demonstrates

## Changes by Category

### AdventureWorks2019/Subset
| Old Filename | New Filename |
|-------------|--------------|
| AdventureWorks2019_example_Find_Two_Subsets.ps1 | 01-Find-Multiple-Subsets.ps1 |
| AdventureWorks2019_example_NewDatabase_Subset.ps1 | 02-Create-New-Database-With-Subset.ps1 |
| AdventureWorks2019_example_NewDatabase_Subset_2.ps1 | 03-Create-New-Database-Alternative-Approach.ps1 |
| AdventureWorks2019_example_NewDatabase_Subset_Without_Restore.ps1 | 04-Create-Subset-Without-Backup-Restore.ps1 |
| AdventureWorks2019_example_Search_Interactive.ps1 | 05-Interactive-Subset-Search.ps1 |
| AdventureWorks2019_example_Search_Interactive_2.ps1 | 06-Interactive-Search-Alternative.ps1 |
| AdventureWorks2019_example_Subset_NewSchema.ps1 | 07-Create-Subset-In-New-Schema.ps1 |
| AdventureWorks2019_example_Subset_NewTable.ps1 | 08-Create-Subset-In-New-Table.ps1 |
| AdventureWorks2019_example_TwoPhaseSearch_01.ps1 | 09-Two-Phase-Search-Strategy.ps1 |

### AdventureWorks2019/Removal
| Old Filename | New Filename |
|-------------|--------------|
| AdventureWorks2019_example_Removal.ps1 | 01-Basic-Data-Removal.ps1 |
| AdventureWorks2019_example_Removal_2.ps1 | 02-Data-Removal-Alternative-Method.ps1 |
| AdventureWorks2019_example_Removal_3.ps1 | 03-Data-Removal-Advanced.ps1 |
| AdventureWorks2019_example_Removal_4.ps1 | 04-Data-Removal-Complex-Scenario.ps1 |
| AdventureWorks2019_example_Removal_In_Loop_Slow.ps1 | 05-Iterative-Removal-Slow-Method.ps1 |
| AdventureWorks2019_example_Removal_In_Loop_Slow_2.ps1 | 06-Iterative-Removal-Alternative-1.ps1 |
| AdventureWorks2019_example_Removal_In_Loop_Slow_3.ps1 | 07-Iterative-Removal-Alternative-2.ps1 |
| AdventureWorks2019_example_Removal_In_Loop_Slow_4.ps1 | 08-Iterative-Removal-Alternative-3.ps1 |

### AdventureWorks2019/Schema
| Old Filename | New Filename |
|-------------|--------------|
| AdventureWorks2019_example_Remove_Schema.ps1 | 01-Remove-Database-Schema.ps1 |
| AdventureWorks2019_example_Schema_Copy.ps1 | 02-Copy-Database-Schema.ps1 |

### AdventureWorks2019/Comparison
| Old Filename | New Filename |
|-------------|--------------|
| AdventureWorks2019_example_Compare_Subsets.ps1 | 01-Compare-Database-Subsets.ps1 |
| AdventureWorks2019_example_Compare_Tables.ps1 | 02-Compare-Table-Data.ps1 |

### AdventureWorks2019/JSON
| Old Filename | New Filename |
|-------------|--------------|
| AdventureWorks2019_example_JSON_import_export.ps1 | 01-Import-Export-JSON-Data.ps1 |
| AdventureWorks2019_example_JSON_schema.ps1 | 02-Export-JSON-Schema.ps1 |

### AdventureWorks2019/Visualization
| Old Filename | New Filename |
|-------------|--------------|
| AdventureWorks2019_example_Color_map.ps1 | 01-Generate-Relationship-Color-Map.ps1 |
| AdventureWorks2019_example_Color_map_2.ps1 | 02-Alternative-Color-Map-Approach.ps1 |

### AdventureWorks2019/Maintenance
| Old Filename | New Filename |
|-------------|--------------|
| AdventureWorks2019_example_Install_Indexes_FK.ps1 | 01-Install-Indexes-And-Foreign-Keys.ps1 |
| AdventureWorks2019_example_IntegrityChecks.ps1 | 02-Run-Data-Integrity-Checks.ps1 |
| AdventureWorks2019_example_Test_Queries.ps1 | 03-Run-Test-Queries.ps1 |
| AdventureWorks2019_example_Triggers.ps1 | 04-Manage-Database-Triggers.ps1 |

### Azure/AzureSQL
| Old Filename | New Filename |
|-------------|--------------|
| AzureAdventureWorksLT_AzureSQL_example_01.ps1 | 01-Basic-Azure-SQL-Operations.ps1 |
| AzureAdventureWorksLT_AzureSQL_example_02.ps1 | 02-Advanced-Azure-SQL-Features.ps1 |
| AzureAdventureWorksLT_AzureSQL_example_03.ps1 | 03-Complex-Azure-SQL-Scenarios.ps1 |

## Benefits of New Naming Convention

1. **Easier to Navigate** - Numbered prefixes make it clear which examples to start with
2. **Better Discoverability** - Descriptive names help users find relevant examples quickly
3. **Reduced Redundancy** - Removed unnecessary prefixes since folder structure already provides context
4. **Professional Appearance** - Consistent kebab-case formatting looks more polished
5. **Improved Maintainability** - Clear naming makes it easier to add new examples in logical order
6. **Better Sorting** - Numbered prefixes ensure examples display in intended learning order

## Documentation Updates

The `README.md` file in the ExamplesNew folder has been updated to reflect all new filenames.

## Date
October 19, 2025
