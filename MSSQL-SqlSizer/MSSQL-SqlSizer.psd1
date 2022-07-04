#
# Module manifest for module 'MSSQL-SqlSizer'
#
# Generated by: Marcin Gołębiowski
#
# Generated on: 4/21/2022
#

@{

# Script module or binary module file associated with this manifest.
RootModule = '.\MSSQL-SqlSizer.psm1'

# Version number of this module.
ModuleVersion = '1.0.0'

# Supported PSEditions
# CompatiblePSEditions = @()

# ID used to uniquely identify this module
GUID = '71e59d9f-0128-4b74-af81-e8efc2f21b05'

# Author of this module
Author = 'Marcin Gołębiowski'

# Company or vendor of this module
CompanyName = 'SqlSizer'

# Copyright statement for this module
Copyright = '(MIT) 2022 Marcin Gołębiowski'

# Description of the functionality provided by this module
Description = 'A set of PowerShell scripts to make subsets of the data from Microsoft SQL database'

# Minimum version of the Windows PowerShell engine required by this module
# PowerShellVersion = ''

# Name of the Windows PowerShell host required by this module
# PowerShellHostName = ''

# Minimum version of the Windows PowerShell host required by this module
# PowerShellHostVersion = ''

# Minimum version of Microsoft .NET Framework required by this module. This prerequisite is valid for the PowerShell Desktop edition only.
# DotNetFrameworkVersion = ''

# Minimum version of the common language runtime (CLR) required by this module. This prerequisite is valid for the PowerShell Desktop edition only.
# CLRVersion = ''

# Processor architecture (None, X86, Amd64) required by this module
# ProcessorArchitecture = ''

# Modules that must be imported into the global environment prior to importing this module
# RequiredModules = @()

# Assemblies that must be loaded prior to importing this module
# RequiredAssemblies = @()

# Script files (.ps1) that are run in the caller's environment prior to importing this module.
ScriptsToProcess = @(
    '.\Types\Color.ps1'
    '.\Types\ColorMap.ps1'
    '.\Types\SqlConnectionStatistics.ps1',
    '.\Types\SqlConnectionInfo.ps1',
    '.\Types\DatabaseInfo.ps1'
    '.\Types\Query.ps1'
    '.\Types\Structure.ps1'
    '.\Types\TableFile.ps1'
)

# Type files (.ps1xml) to be loaded when importing this module
# TypesToProcess = @()

# Format files (.ps1xml) to be loaded when importing this module
# FormatsToProcess = @()

# Modules to import as nested modules of the module specified in RootModule/ModuleToProcess
# NestedModules = @()

# Functions to export from this module, for best performance, do not use wildcards and do not delete the entry, use an empty array if there are no functions to export.
#FunctionsToExport = @()

# Cmdlets to export from this module, for best performance, do not use wildcards and do not delete the entry, use an empty array if there are no cmdlets to export.
CmdletsToExport = @('Clear-Database','Clear-SqlSizer','Compress-Database','Copy-AzDatabase','Copy-DataFromSubset','Copy-Database','Copy-Sequences','Copy-SubsetToAzStorageContainer  ','Disable-IntegrityChecks','Enable-IntegrityChecks','Find-ReachableTables','Find-Subset','Find-UnreachableTables','Format-Indexes','Get-DatabaseInfo','Get-SubsetTableCsv','Get-SubsetTableJson','Get-SubsetTableRows','Get-SubsetTables','Get-SubsetTableStatistics','Get-SubsetTableXml','Get-SubsetUnreachableEdges','Import-DataFromAzStorageContainer','Initialize-StartSet','Install-ForeignKeyIndexes','Install-SqlSizer','New-DataTableClone','New-DataTableFromSubsetTable','New-DataTableFromView','New-EmptyAzDatabase','New-EmptyDatabase','New-SchemaFromDatabase','New-SchemaFromSubset','New-SqlConnectionInfo','Remove-EmptyTables','Remove-Schema','Remove-SubsetData','Test-DatabaseOnline','Test-ForeignKeys','Test-IgnoredTables','Test-Queries','Test-SchemaExists','Test-TableExists','Uninstall-SqlSizer')

# Variables to export from this module
#VariablesToExport = '*'

# Aliases to export from this module, for best performance, do not use wildcards and do not delete the entry, use an empty array if there are no aliases to export.
#AliasesToExport = @()

# DSC resources to export from this module
# DscResourcesToExport = @()

# List of all modules packaged with this module
# ModuleList = @()

# List of all files packaged with this module
# FileList = @()

# Private data to pass to the module specified in RootModule/ModuleToProcess. This may also contain a PSData hashtable with additional module metadata used by PowerShell.
PrivateData = @{

    PSData = @{
        Prerelease = 'alpha3'

        # Tags applied to this module. These help with module discovery in online galleries.
        Tags = @('SQL', 'database', 'T-SQL', 'MSSQL', 'search', 'subset', 'search')

        # A URL to the license for this module.
        LicenseUri = 'https://github.com/sqlsizer/mssql-sqlsizer/blob/main/LICENSE'

        # A URL to the main website for this project.
        ProjectUri = 'https://github.com/sqlsizer/mssql-sqlsizer'

        # A URL to an icon representing this module.
        IconUri = 'https://avatars.githubusercontent.com/u/96390582?s=100&v=4'

        # ReleaseNotes of this module
        # ReleaseNotes = ''

    } # End of PSData hashtable

} # End of PrivateData hashtable

# HelpInfo URI of this module
# HelpInfoURI = ''

# Default prefix for commands exported from this module. Override the default prefix using Import-Module -Prefix.
# DefaultCommandPrefix = ''

}

