#
# Module manifest for module 'SqlSizer-MSSQL'
#
# Generated by: Marcin Gołębiowski
#
# Generated on: 8/29/2022
#

@{

# Script module or binary module file associated with this manifest.
RootModule = ".\SqlSizer-MSSQL.psm1"

# Version number of this module.
ModuleVersion = '1.0.6'

# Supported PSEditions
# CompatiblePSEditions = @()

# ID used to uniquely identify this module
GUID = '596dd772-d4a9-4c81-9362-8107ed7f36e5'

# Author of this module
Author = 'Marcin Gołębiowski'

# Company or vendor of this module
CompanyName = 'SqlSizer'

# Copyright statement for this module
Copyright = 'Copyright (c) 2022-2023 Marcin Gołębiowski (licensed under MIT)'

# Description of the functionality provided by this module
Description = 'A PowerShell module for managing data in Microsoft SQL Server, Azure SQL databases and Azure Synapse Analytics SQL Pool.'

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
    ".\Types\SqlSizer-MSSQL-Types.ps1"
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
CmdletsToExport = @('Disable-ReachableIndexes', 'Enable-ReachableIndexes', 'Enable-Indexes', 'Disable-Indexes', 'Remove-FoundSubsetsFromDatabase', 'Find-RemovalSubset', 'Clear-SqlSizerSessions', 'Test-FoundSubsetIsEmpty', 'Get-SubsetHashSummary', 'Get-SubsetSchemaJson', 'Import-TableJson', 'Clear-SqlSizerSession', 'Start-SqlSizerSession', 'Update-DatabaseInfo', 'Install-PrimaryKeys', 'Restore-View', 'Remove-View', 'Remove-ForeignKeys', 'Restore-ForeignKeys', 'Remove-Table', 'Get-SqlSizerInfo', 'Invoke-SqlcmdEx', 'Compare-SavedSubsets', 'Get-SavedSubsetTables', 'Remove-SavedSubset', 'Get-SavedSubsets', 'Save-Subset', 'Get-DatabaseSchemaJson', 'Disable-AllTablesTriggers', 'Enable-AllTablesTriggers', 'Edit-ForeignKey', 'Enable-DatabaseTriggers','Enable-TableTrigger','Enable-TableTriggers','Disable-DatabaseTriggers','Disable-TableTrigger','Disable-TableTriggers','Clear-Database','Compress-Database','Copy-AzDatabase','Copy-Constraints','Copy-Database','Copy-DataFromSubset','Copy-FileToDatabase','Copy-Functions','Copy-Sequences','Copy-StoredProcedures','Copy-SubsetToAzStorageContainer','Copy-SubsetToDatabaseFileSet','Copy-UserTypes','Disable-ForeignKeys','Enable-ForeignKeys','Find-ReachableTables','Find-Subset','Find-UnreachableTables','Format-Indexes','Get-DatabaseInfo','Get-SubsetTableCsv','Get-SubsetTableJson','Get-SubsetTableRows','Get-SubsetTables','Get-SubsetTableStatistics','Get-SubsetTableXml','Get-SubsetUnreachableEdges','Import-SubsetFromAzStorageContainer','Import-SubsetFromFileSet','Initialize-StartSet','Install-ForeignKeyIndexes','Install-SqlSizer','New-DataTableClone','New-DataTableFromSubsetTable','New-DataTableFromView','New-EmptyAzDatabase','New-EmptyCompactDatabase','New-EmptyDatabase','New-SchemaFromDatabase','New-SchemaFromSubset','New-SqlConnectionInfo','Compare-Tables','Remove-DataFromFileSet','Remove-EmptyTables','Remove-FileFromDatabase','Remove-Schema','Remove-FoundSubsetFromDatabase','Test-DatabaseOnline','Test-ForeignKeys','Test-IgnoredTables','Test-Queries','Test-SchemaExists','Test-TableExists','Uninstall-SqlSizer')

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
        # Tags applied to this module. These help with module discovery in online galleries.
        Tags = @('SQL', 'database', 'T-SQL', 'MSSQL', 'search', 'subset')

        # A URL to the license for this module.
        LicenseUri = 'https://github.com/sqlsizer/sqlsizer-mssql/blob/main/LICENSE'

        # A URL to the main website for this project.
        ProjectUri = 'https://github.com/sqlsizer/sqlsizer-mssql'

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


# SIG # Begin signature block
# MIIoigYJKoZIhvcNAQcCoIIoezCCKHcCAQExDzANBglghkgBZQMEAgEFADB5Bgor
# BgEEAYI3AgEEoGswaTA0BgorBgEEAYI3AgEeMCYCAwEAAAQQH8w7YFlLCE63JNLG
# KX7zUQIBAAIBAAIBAAIBAAIBADAxMA0GCWCGSAFlAwQCAQUABCAuROzzHKVXpy1U
# AaVACGD7DXVLTm+uoeVVcEEFy2T32aCCIL4wggXJMIIEsaADAgECAhAbtY8lKt8j
# AEkoya49fu0nMA0GCSqGSIb3DQEBDAUAMH4xCzAJBgNVBAYTAlBMMSIwIAYDVQQK
# ExlVbml6ZXRvIFRlY2hub2xvZ2llcyBTLkEuMScwJQYDVQQLEx5DZXJ0dW0gQ2Vy
# dGlmaWNhdGlvbiBBdXRob3JpdHkxIjAgBgNVBAMTGUNlcnR1bSBUcnVzdGVkIE5l
# dHdvcmsgQ0EwHhcNMjEwNTMxMDY0MzA2WhcNMjkwOTE3MDY0MzA2WjCBgDELMAkG
# A1UEBhMCUEwxIjAgBgNVBAoTGVVuaXpldG8gVGVjaG5vbG9naWVzIFMuQS4xJzAl
# BgNVBAsTHkNlcnR1bSBDZXJ0aWZpY2F0aW9uIEF1dGhvcml0eTEkMCIGA1UEAxMb
# Q2VydHVtIFRydXN0ZWQgTmV0d29yayBDQSAyMIICIjANBgkqhkiG9w0BAQEFAAOC
# Ag8AMIICCgKCAgEAvfl4+ObVgAxknYYblmRnPyI6HnUBfe/7XGeMycxca6mR5rlC
# 5SBLm9qbe7mZXdmbgEvXhEArJ9PoujC7Pgkap0mV7ytAJMKXx6fumyXvqAoAl4Va
# qp3cKcniNQfrcE1K1sGzVrihQTib0fsxf4/gX+GxPw+OFklg1waNGPmqJhCrKtPQ
# 0WeNG0a+RzDVLnLRxWPa52N5RH5LYySJhi40PylMUosqp8DikSiJucBb+R3Z5yet
# /5oCl8HGUJKbAiy9qbk0WQq/hEr/3/6zn+vZnuCYI+yma3cWKtvMrTscpIfcRnNe
# GWJoRVfkkIJCu0LW8GHgwaM9ZqNd9BjuiMmNF0UpmTJ1AjHuKSbIawLmtWJFfzcV
# WiNoidQ+3k4nsPBADLxNF8tNorMe0AZa3faTz1d1mfX6hhpneLO/lv403L3nUlbl
# s+V1e9dBkQXcXWnjlQ1DufyDljmVe2yAWk8TcsbXfSl6RLpSpCrVQUYJIP4ioLZb
# MI28iQzV13D4h1L92u+sUS4Hs07+0AnacO+Y+lbmbdu1V0vc5SwlFcieLnhO+Nqc
# noYsylfzGuXIkosagpZ6w7xQEmnYDlpGizrrJvojybawgb5CAKT41v4wLsfSRvbl
# jnX98sy50IdbzAYQYLuDNbdeZ95H7JlI8aShFf6tjGKOOVVPORa5sWOd/7cCAwEA
# AaOCAT4wggE6MA8GA1UdEwEB/wQFMAMBAf8wHQYDVR0OBBYEFLahVDkCw6A/joq8
# +tT4HKbROg79MB8GA1UdIwQYMBaAFAh2zcsH/yT2xc3tu5C84oQ3RnX3MA4GA1Ud
# DwEB/wQEAwIBBjAvBgNVHR8EKDAmMCSgIqAghh5odHRwOi8vY3JsLmNlcnR1bS5w
# bC9jdG5jYS5jcmwwawYIKwYBBQUHAQEEXzBdMCgGCCsGAQUFBzABhhxodHRwOi8v
# c3ViY2Eub2NzcC1jZXJ0dW0uY29tMDEGCCsGAQUFBzAChiVodHRwOi8vcmVwb3Np
# dG9yeS5jZXJ0dW0ucGwvY3RuY2EuY2VyMDkGA1UdIAQyMDAwLgYEVR0gADAmMCQG
# CCsGAQUFBwIBFhhodHRwOi8vd3d3LmNlcnR1bS5wbC9DUFMwDQYJKoZIhvcNAQEM
# BQADggEBAFHCoVgWIhCL/IYx1MIy01z4S6Ivaj5N+KsIHu3V6PrnCA3st8YeDrJ1
# BXqxC/rXdGoABh+kzqrya33YEcARCNQOTWHFOqj6seHjmOriY/1B9ZN9DbxdkjuR
# mmW60F9MvkyNaAMQFtXx0ASKhTP5N+dbLiZpQjy6zbzUeulNndrnQ/tjUoCFBMQl
# lVXwfqefAcVbKPjgzoZwpic7Ofs4LphTZSJ1Ldf23SIikZbr3WjtP6MZl9M7JYjs
# NhI9qX7OAo0FmpKnJ25FspxihjcNpDOO16hO0EoXQ0zF8ads0h5YbBRRfopUofbv
# n3l6XYGaFpAP4bvxSgD5+d2+7arszgowggaUMIIEfKADAgECAhAr1K5wudBjWyrp
# hMjWdKowMA0GCSqGSIb3DQEBDAUAMFYxCzAJBgNVBAYTAlBMMSEwHwYDVQQKExhB
# c3NlY28gRGF0YSBTeXN0ZW1zIFMuQS4xJDAiBgNVBAMTG0NlcnR1bSBUaW1lc3Rh
# bXBpbmcgMjAyMSBDQTAeFw0yMjA3MjgwODU2MjZaFw0zMzA3MjcwODU2MjZaMFAx
# CzAJBgNVBAYTAlBMMSEwHwYDVQQKDBhBc3NlY28gRGF0YSBTeXN0ZW1zIFMuQS4x
# HjAcBgNVBAMMFUNlcnR1bSBUaW1lc3RhbXAgMjAyMjCCAiIwDQYJKoZIhvcNAQEB
# BQADggIPADCCAgoCggIBAMrFXu0fCUbwRMtqXliGb6KwhLCeP4vySHEqQBI78xFc
# jqQae26x7v21UvkWS+X0oTh61yTcdoZaQAg5hNcBqWbGn7b8OOEXkGwUvGZ65MWK
# l2lXBjisc6d1GWVI5fXkP9+ddLVX4G/pP7eIdAtI5Fh4rGC/x9/vNan9C8C4I56N
# 525HwiKzqPSz6Z5N2XYM0+bT4VdYsZxyPRwLkjhcqdzg2tCB2+YP6ld+uBOkcfCr
# hFCeeTB4Y/ZalrZXaCGFIlBWjIyXb9UGspAaoDvP2LCSSRcnvrP49qIIGD7TqHbD
# oYumubWDgx8/YE7M5Bfd7F14mQOqnr7ImCFS5Ty/nfSO7XVSQ6TrlIYX8rLA4BSj
# nOu0WoYZTLOWyaekWPraAAhvzJQ3mXt6ruGa6VEljyzDTUfgEmSDpnxP6OFSOOc4
# xBOXbkV8OO4ivGf0pIff+IOsysOwvuSSHfF1FxSerNZb3VcUneyQaT+omC+kaGTP
# pvsyly53V/MUKuHVhgRIrGiWIJgN9Tr73oZXHk6mbuzkXiHhao/1AQrQ35q+mtGK
# vnXtf62dsJFztYf/XceELTw/KJd1YL7hlQ9zGR/fFE+fx9pvLd2yZ3Y1PCtpaNzq
# 6i7JZ2mRldC1XwikBtjoQ6GT2T3kyRn0lAU8Y4/TdN/4pptwouFk+75JsdToPQ6B
# AgMBAAGjggFiMIIBXjAMBgNVHRMBAf8EAjAAMB0GA1UdDgQWBBQjwTzMUzMZVo7Y
# 4/POPPyoc0dW6jAfBgNVHSMEGDAWgBS+VAIvv0Bsc0POrAklTp5DRBru4DAOBgNV
# HQ8BAf8EBAMCB4AwFgYDVR0lAQH/BAwwCgYIKwYBBQUHAwgwMwYDVR0fBCwwKjAo
# oCagJIYiaHR0cDovL2NybC5jZXJ0dW0ucGwvY3RzY2EyMDIxLmNybDBvBggrBgEF
# BQcBAQRjMGEwKAYIKwYBBQUHMAGGHGh0dHA6Ly9zdWJjYS5vY3NwLWNlcnR1bS5j
# b20wNQYIKwYBBQUHMAKGKWh0dHA6Ly9yZXBvc2l0b3J5LmNlcnR1bS5wbC9jdHNj
# YTIwMjEuY2VyMEAGA1UdIAQ5MDcwNQYLKoRoAYb2dwIFAQswJjAkBggrBgEFBQcC
# ARYYaHR0cDovL3d3dy5jZXJ0dW0ucGwvQ1BTMA0GCSqGSIb3DQEBDAUAA4ICAQBr
# xvc9Iz4vV5D57BeApm1pfVgBjTKWgflb1htxJA9HSvXneq/j/+5kohu/1p0j6IJM
# YTpSbT7oHAtg59m0wM0HnmrjcN43qMNo5Ts/gX/SBmY0qMzdlO6m1D9egn7U49Eg
# GO+IZFAnmMH1hLx+pse6dgtThZ4aqr+zRfRNoTFNSUxyOSo6cmVKfRbZgTiLEcMe
# hGJTeM5CQs1AmDpF+hqyq0X6Mv0BMtHU2wPoVlI3xrRQ167lM64/gl8dCYzMPF8l
# 8W89ds2Rfro9Y1p5dI0L8x60opb1f8n5Hf4ayW9Kc7rgUdlnfJc4cYdvV0JxWYpS
# ZPN5LJM54xSKrveXnYq1NNIuovqJOM9mixVMJ2TTWPkfQ2pl0H/ZokxxXB4qEKAy
# Sa6bfcijoQiOaR5wKQR+0yrc7KIdqt+hOVhl5uUti9cZxA8JMiNdX6SaasglnJ9o
# lTSMJ4BRO6tCASEvJeeCzX6ZViKRDHbFQCaMZ1XdxlwR6Cqkfa2p5EN1DKQSjxI1
# p6lddQmc9PTVGWM8dpbRKtHHBoOQvfWEdigP3EI7RGZqWTonwr8AaMCgTzYbFpuZ
# ed3lG7yi0jwUJo9/ryUNFA82m9CpzLcaAKaLQ0s1uboR6zaWSt9fqUASNz9zD+8I
# iGlyUqKIAFViQMqqyHej0vK7G2gPqEy5GDdxL/DBaTCCBrkwggShoAMCAQICEQCZ
# o4AKJlU7ZavcboSms+o5MA0GCSqGSIb3DQEBDAUAMIGAMQswCQYDVQQGEwJQTDEi
# MCAGA1UEChMZVW5pemV0byBUZWNobm9sb2dpZXMgUy5BLjEnMCUGA1UECxMeQ2Vy
# dHVtIENlcnRpZmljYXRpb24gQXV0aG9yaXR5MSQwIgYDVQQDExtDZXJ0dW0gVHJ1
# c3RlZCBOZXR3b3JrIENBIDIwHhcNMjEwNTE5MDUzMjE4WhcNMzYwNTE4MDUzMjE4
# WjBWMQswCQYDVQQGEwJQTDEhMB8GA1UEChMYQXNzZWNvIERhdGEgU3lzdGVtcyBT
# LkEuMSQwIgYDVQQDExtDZXJ0dW0gQ29kZSBTaWduaW5nIDIwMjEgQ0EwggIiMA0G
# CSqGSIb3DQEBAQUAA4ICDwAwggIKAoICAQCdI88EMCM7wUYs5zNzPmNdenW6vlxN
# ur3rLfi+5OZ+U3iZIB+AspO+CC/bj+taJUbMbFP1gQBJUzDUCPx7BNLgid1TyztV
# Ln52NKgxxu8gpyTr6EjWyGzKU/gnIu+bHAse1LCitX3CaOE13rbuHbtrxF2tPU8f
# 253QgX6eO8yTbGps1Mg+yda3DcTsOYOhSYNCJiL+5wnjZ9weoGRtvFgMHtJg6i67
# 1OPXIciiHO4Lwo2p9xh/tnj+JmCQEn5QU0NxzrOiRna4kjFaA9ZcwSaG7WAxeC/x
# oZSxF1oK1UPZtKVt+yrsGKqWONoK6f5EmBOAVEK2y4ATDSkb34UD7JA32f+Rm0ws
# r5ajzftDhA5mBipVZDjHpwzv8bTKzCDUSUuUmPo1govD0RwFcTtMXcfJtm1i+P2U
# NXadPyYVKRxKQATHN3imsfBiNRdN5kiVVeqP55piqgxOkyt+HkwIA4gbmSc3hD8k
# e66t9MjlcNg73rZZlrLHsAIV/nJ0mmgSjBI/TthoGJDydekOQ2tQD2Dup/+sKQpt
# alDlui59SerVSJg8gAeV7N/ia4mrGoiez+SqV3olVfxyLFt3o/OQOnBmjhKUANoK
# LYlKmUpKEFI0PfoT8Q1W/y6s9LTI6ekbi0igEbFUIBE8KDUGfIwnisEkBw5KcBZ3
# XwnHmfznwlKo8QIDAQABo4IBVTCCAVEwDwYDVR0TAQH/BAUwAwEB/zAdBgNVHQ4E
# FgQU3XRdTADbe5+gdMqxbvc8wDLAcM0wHwYDVR0jBBgwFoAUtqFUOQLDoD+Oirz6
# 1PgcptE6Dv0wDgYDVR0PAQH/BAQDAgEGMBMGA1UdJQQMMAoGCCsGAQUFBwMDMDAG
# A1UdHwQpMCcwJaAjoCGGH2h0dHA6Ly9jcmwuY2VydHVtLnBsL2N0bmNhMi5jcmww
# bAYIKwYBBQUHAQEEYDBeMCgGCCsGAQUFBzABhhxodHRwOi8vc3ViY2Eub2NzcC1j
# ZXJ0dW0uY29tMDIGCCsGAQUFBzAChiZodHRwOi8vcmVwb3NpdG9yeS5jZXJ0dW0u
# cGwvY3RuY2EyLmNlcjA5BgNVHSAEMjAwMC4GBFUdIAAwJjAkBggrBgEFBQcCARYY
# aHR0cDovL3d3dy5jZXJ0dW0ucGwvQ1BTMA0GCSqGSIb3DQEBDAUAA4ICAQB1iFgP
# 5Y9QKJpTnxDsQ/z0O23JmoZifZdEOEmQvo/79PQg9nLF/GJe6ZiUBEyDBHMtFRK0
# mXj3Qv3gL0sYXe+PPMfwmreJHvgFGWQ7XwnfMh2YIpBrkvJnjwh8gIlNlUl4KENT
# K5DLqsYPEtRQCw7R6p4s2EtWyDDr/M58iY2UBEqfUU/ujR9NuPyKk0bEcEi62JGx
# auFYzZ/yld13fHaZskIoq2XazjaD0pQkcQiIueL0HKiohS6XgZuUtCKA7S6CHttZ
# EsObQJ1j2s0urIDdqF7xaXFVaTHKtAuMfwi0jXtF3JJphrJfc+FFILgCbX/uYBPB
# lbBIP4Ht4xxk2GmfzMn7oxPITpigQFJFWuzTMUUgdRHTxaTSKRJ/6Uh7ki/pFjf9
# sUASWgxT69QF9Ki4JF5nBIujxZ2sOU9e1HSCJwOfK07t5nnzbs1LbHuAIGJsRJiQ
# 6HX/DW1XFOlXY1rc9HufFhWU+7Uk+hFkJsfzqBz3pRO+5aI6u5abI4Qws4YaeJH7
# H7M8X/YNoaArZbV4Ql+jarKsE0+8XvC4DJB+IVcvC9Ydqahi09mjQse4fxfef0L7
# E3hho2O3bLDM6v60rIRUCi2fJT2/IRU5ohgyTch4GuYWefSBsp5NPJh4QRTP9DC3
# gc5QEKtbrTY0Ka87Web7/zScvLmvQBm8JDFpDjCCBrkwggShoAMCAQICEQDn/2nH
# OzXOS5Em2HR8aKWHMA0GCSqGSIb3DQEBDAUAMIGAMQswCQYDVQQGEwJQTDEiMCAG
# A1UEChMZVW5pemV0byBUZWNobm9sb2dpZXMgUy5BLjEnMCUGA1UECxMeQ2VydHVt
# IENlcnRpZmljYXRpb24gQXV0aG9yaXR5MSQwIgYDVQQDExtDZXJ0dW0gVHJ1c3Rl
# ZCBOZXR3b3JrIENBIDIwHhcNMjEwNTE5MDUzMjA3WhcNMzYwNTE4MDUzMjA3WjBW
# MQswCQYDVQQGEwJQTDEhMB8GA1UEChMYQXNzZWNvIERhdGEgU3lzdGVtcyBTLkEu
# MSQwIgYDVQQDExtDZXJ0dW0gVGltZXN0YW1waW5nIDIwMjEgQ0EwggIiMA0GCSqG
# SIb3DQEBAQUAA4ICDwAwggIKAoICAQDpEh8ENe25XXrFppVBvoplf0530W0lddNm
# jtv4YSh/f7eDQKFaIqc7tHj7ox+u8vIsJZlroakUeMS3i3T8aJRC+eQs4FF0Gqvk
# M6+WZO8kmzZfxmZaBYmMLs8FktgFYCzywmXeQ1fEExflee2OpbHVk665eXRHjH7M
# YZIzNnjl2m8Hy8ulB9mR8wL/W0v0pjKNT6G0sfrx1kk+3OGosFUb7yWNnVkWKU4q
# SxLv16kJ6oVJ4BSbZ4xMak6JLeB8szrK9vwGDpvGDnKCUMYL3NuviwH1x4gZG0JA
# XU3x2pOAz91JWKJSAmRy/l0s0l5bEYKolg+DMqVhlOANd8Yh5mkQWaMEvBRE/kAG
# zIqgWhwzN2OsKIVtO8mf5sPWSrvyplSABAYa13rMYnzwfg08nljZHghquCJYCa/x
# HK9acev9UD7Y+usr15d7mrszzxhF1JOr1Mpup2chNSBlyOObhlSO16rwrffVrg/S
# zaKfSndS5swRhr8bnDqNJY9TNyEYvBYpgF95K7p0g4LguR4A++Z1nFIHWVY5v0fN
# VZmgzxD9uVo/gta3onGOQj3JCxgYx0KrCXu4yc9QiVwTFLWbNdHFSjBCt5/8Q9pL
# uRhVocdCunhcHudMS1CGQ/Rn0+7P+fzMgWdRKfEOh/hjLrnQ8BdJiYrZNxvIOhM2
# aa3zEDHNwwIDAQABo4IBVTCCAVEwDwYDVR0TAQH/BAUwAwEB/zAdBgNVHQ4EFgQU
# vlQCL79AbHNDzqwJJU6eQ0Qa7uAwHwYDVR0jBBgwFoAUtqFUOQLDoD+Oirz61Pgc
# ptE6Dv0wDgYDVR0PAQH/BAQDAgEGMBMGA1UdJQQMMAoGCCsGAQUFBwMIMDAGA1Ud
# HwQpMCcwJaAjoCGGH2h0dHA6Ly9jcmwuY2VydHVtLnBsL2N0bmNhMi5jcmwwbAYI
# KwYBBQUHAQEEYDBeMCgGCCsGAQUFBzABhhxodHRwOi8vc3ViY2Eub2NzcC1jZXJ0
# dW0uY29tMDIGCCsGAQUFBzAChiZodHRwOi8vcmVwb3NpdG9yeS5jZXJ0dW0ucGwv
# Y3RuY2EyLmNlcjA5BgNVHSAEMjAwMC4GBFUdIAAwJjAkBggrBgEFBQcCARYYaHR0
# cDovL3d3dy5jZXJ0dW0ucGwvQ1BTMA0GCSqGSIb3DQEBDAUAA4ICAQC4k1l3yUwV
# /ZQHCKCneqAs8EGTnwEUJLdDpokN/dMhKjK0rR5qX8nIIHzxpQR3TAw2IRw1Uxsr
# 2PliG3bCFqSdQTUbfaTq6V3vBzEebDru9QFjqlKnxCF2h1jhLNFFplbPJiW+JSnJ
# Th1fKEqEdKdxgl9rVTvlxfEJ7exOn25MGbd/wGPwuSmMxRJVO0wnqgS7kmoJjNF9
# zqeehFSDDP8ZVkWg4EZ2tIS0M3uZmByRr+1Lkwjjt8AtW83mVnZTyTsOb+FNfwJY
# 7DS4FmWhkRbgcHRetreoTirPOr/ozyDKhT8MTSTf6Lttg6s6T/u08mDWw6HK04ZR
# DfQ9sb77QV8mKgO44WGP31vXnVKoWVJpFBjPvjL8/Zck/5wXX2iqjOaLStFOR/IQ
# ki+Ehn4zlcgVm22ZVCBPF+l8nAwUUShCtKuSU7GmZLKCmmxQMkSiWILTm8EtVD6A
# xnJhoq8EnhjEEyUoflkeRF2WhFiVQOmWTwZRr44IxWGkNJC6tTorW5rl2Zl+2e9J
# LPYf3pStAPMDoPKIjVXd6NW2+fZrNUBeDo2eOa5Fn7Brs/HLQff5Xgris5MeUbdV
# gDrF8uxO6cLPvZPo63j62SsNg55pTWk9fUIF9iPoRbb4QurjoY/woI1RAOKtYtTi
# c6aAJq3u83RIPpGXBSJKwx4KJAOZnCDCtTCCBtswggTDoAMCAQICEGKUqNjbtPSE
# Tu16moosTdUwDQYJKoZIhvcNAQELBQAwVjELMAkGA1UEBhMCUEwxITAfBgNVBAoT
# GEFzc2VjbyBEYXRhIFN5c3RlbXMgUy5BLjEkMCIGA1UEAxMbQ2VydHVtIENvZGUg
# U2lnbmluZyAyMDIxIENBMB4XDTIyMDcwNjE3NTkxOFoXDTIzMDcwNjE3NTkxN1ow
# gYAxCzAJBgNVBAYTAlBMMRIwEAYDVQQIDAlwb21vcnNraWUxHTAbBgNVBAoMFE1h
# cmNpbiBHb8WCxJliaW93c2tpMR0wGwYDVQQDDBRNYXJjaW4gR2/FgsSZYmlvd3Nr
# aTEfMB0GCSqGSIb3DQEJARYQeG9ybXVzQGdtYWlsLmNvbTCCAiIwDQYJKoZIhvcN
# AQEBBQADggIPADCCAgoCggIBAKr2WuURfyFgf3jRzAxUJ8B4MGl2pgHcGnvTjeiB
# L6xwGlWzYiF1ucSUW8MkgulVc+WT2yNXK+Sm2F8IyZzskB0R+vZfp5hPMl8GoyB7
# oEtuwunEJDIoUCWatRMvVPCT7+TlL0+fZuPnQ3oqnY+AqT/ET8Im8oVO0McJndqa
# Rfto1k7ak3No4u1W/274hu4DelYAxeb9mpNeFnYfkAruoYsgN9NVhD9FMOrdcwG8
# ic7tQGPoMXa9C8qdgyeXESSrgSkcHXq62TwEVoK7Hv2A73e/hlxzPqX5VwUkZkV1
# jwCwQwj0kGIPFzVUpx4gruYWuJ5btHwHtZlB7IhpQBwuQkF0XtWmJ6IWzR2RKyyx
# GHt2BYbBCTDEMVwpM5mLP4KkuwOcpJL2sgKCVquX29X9oPpqqQzeIHhsbyvAmlrf
# xQFUz690JeDYLr3d2HpxD7jzniJcDaq4sf/bxdtqU1ZIAXAI1KErB6B6VWQoesWx
# dPDXSTbmhw/7d8adUYGhxWicUY0Vp9N7r2oEsL7hA73hsccveJBeHovUDUt2yVYZ
# xMNfBA+a94d2gXDy4dPfZ1CmT7ifQ38ClgkDWZUxekjhtx+1WPnYT4F4SuGneKDI
# l9JnRztt6xG0UTIMcLgzE5NrLlaKdILPXG/qP4VRJRyjEJgdD1IwvAfTdAYGaXLX
# z6O9AgMBAAGjggF4MIIBdDAMBgNVHRMBAf8EAjAAMD0GA1UdHwQ2MDQwMqAwoC6G
# LGh0dHA6Ly9jY3NjYTIwMjEuY3JsLmNlcnR1bS5wbC9jY3NjYTIwMjEuY3JsMHMG
# CCsGAQUFBwEBBGcwZTAsBggrBgEFBQcwAYYgaHR0cDovL2Njc2NhMjAyMS5vY3Nw
# LWNlcnR1bS5jb20wNQYIKwYBBQUHMAKGKWh0dHA6Ly9yZXBvc2l0b3J5LmNlcnR1
# bS5wbC9jY3NjYTIwMjEuY2VyMB8GA1UdIwQYMBaAFN10XUwA23ufoHTKsW73PMAy
# wHDNMB0GA1UdDgQWBBSbo4Vic2BmodM1NmsAW4N1/N0VlDBLBgNVHSAERDBCMAgG
# BmeBDAEEATA2BgsqhGgBhvZ3AgUBBDAnMCUGCCsGAQUFBwIBFhlodHRwczovL3d3
# dy5jZXJ0dW0ucGwvQ1BTMBMGA1UdJQQMMAoGCCsGAQUFBwMDMA4GA1UdDwEB/wQE
# AwIHgDANBgkqhkiG9w0BAQsFAAOCAgEADZ14LtIisUdnaERD8OHOpbMMZY7zloi7
# aVuP0euezvciM5l0S/1y6LdwQKyC8EoLm8ImdSW5HL9rgLmdDhAZlmFqDf+OrscM
# 3rOIvOY/Zs0VmRY5cOn6Ht760PvPsdBSHodPhZ3zCTASWUaakf+AI3cRBkEqzqtY
# R4L4+9RhLyDTkCIAKdRYzBhmNAGWziI6iW9EwnxxNR8JxVsYdspcgb7wVKI0IFDZ
# 0JzXIotahi1+tAHgS+PXWXrffC6jG3Zr7ZdNanxYTDn4wyT11fNuT1MJDMCOpuvt
# IsnXQexxVsVovSzf/4wtaKQp4nyckgjrSQQUkFRTT5ynyEALBhEs42o8zY61WaKI
# 2jWjZeLAALFBooIiEK0hye/UqcxEc2q76Diub8H7HFMO3+fIsFDZMaXB3JBmoZW4
# X8CX45nv76Vdt6ldlH/6WzS1J3LdfW51kbOwby8ZLZkyz6cawcsfmeiHMzY9w3aL
# 459i7xeLEn57BfDZMvi3F24LoAEA6D2CM/vvCK2+KL5nzbNhaq1Ksfl7QDDdhg88
# tz8qsHjY6PEEcwedcB9YEc9yEuMaLNmxTjga0hi5yIL7FsXZ/tqf5kmLwUSyO7r5
# azilEYS1PQ4O5y+UWURDQ7tKH6CbPE5QuQ35kDfGaVMQziExOW1QQKwf0N0R393c
# 184HgEAr0bUxggciMIIHHgIBATBqMFYxCzAJBgNVBAYTAlBMMSEwHwYDVQQKExhB
# c3NlY28gRGF0YSBTeXN0ZW1zIFMuQS4xJDAiBgNVBAMTG0NlcnR1bSBDb2RlIFNp
# Z25pbmcgMjAyMSBDQQIQYpSo2Nu09IRO7XqaiixN1TANBglghkgBZQMEAgEFAKCB
# hDAYBgorBgEEAYI3AgEMMQowCKACgAChAoAAMBkGCSqGSIb3DQEJAzEMBgorBgEE
# AYI3AgEEMBwGCisGAQQBgjcCAQsxDjAMBgorBgEEAYI3AgEVMC8GCSqGSIb3DQEJ
# BDEiBCCUKWUiIWk6Xq9C1e7siQm3VtFHbFKVV4fOq2eTokBI+DANBgkqhkiG9w0B
# AQEFAASCAgCbOZvzRzsFtRjafpTfA29FYycw2Sie2S/Ckqf6V3U3NjbLvZwTNTbc
# 7HZCo+0nZKu2SSP9VpUfoFgtmE41mdItgigZU7XqikLoEx4vZA3Ixajb54sjz/u0
# hV6PdULd6oRQT7CK0T+iLSjj9hfFsZ/SiOPA8qKFBtHP9V+ZGM4HPb1sjsqJh0m2
# srLtMKhrncGRFTJdVaXF5nsPtMuEQvlw7gYyV7XfR0/ms6KsAfd1Q9pJPQvDiDhj
# N99bEMAbJ9HfrezMXQjxQL00Dk81kMetNlKszKPVdhJizSTnYC3bK6z5OJUZloZj
# jNXKYFiJdgFFyR6TPHqxNuHqMJykIoHFxZ5IsKl3ICT7ZtNriFnGDHeRsU6ENchl
# xXyA65WZaznZkE4bentYFGCu3VimG7LJjaQmGVmICB8eEpCzY8Xip/PukRSfISfG
# +mJeXQX5aDmcvR2+Sm2C1ADLJhHJONZaei1dsuss3avjglJqHfsWyLs4caZNkfVr
# vzP/UrrvUErMsS2EPHntErkStgFVCRZfp4m38SMHViZu1aB8+bhhK4NE+X38W6eQ
# v9++cBY+AudhFFFc4RA6/OjKXq+bdwSgyNkCIgn0c0tcxKKQgMI6vk9oY3CIXAH+
# EGQINw5TJr2lVVu73yndoghQKyAEQFHEAFb0VmQY8Q8RaWvJVk/MWaGCBAIwggP+
# BgkqhkiG9w0BCQYxggPvMIID6wIBATBqMFYxCzAJBgNVBAYTAlBMMSEwHwYDVQQK
# ExhBc3NlY28gRGF0YSBTeXN0ZW1zIFMuQS4xJDAiBgNVBAMTG0NlcnR1bSBUaW1l
# c3RhbXBpbmcgMjAyMSBDQQIQK9SucLnQY1sq6YTI1nSqMDANBglghkgBZQMEAgIF
# AKCCAVYwGgYJKoZIhvcNAQkDMQ0GCyqGSIb3DQEJEAEEMBwGCSqGSIb3DQEJBTEP
# Fw0yMzAyMTgyMjU5NDlaMDcGCyqGSIb3DQEJEAIvMSgwJjAkMCIEIAO5mmRJdJhK
# lbbMXYDTRNB0+972yiQEhCvmzw5EIgeKMD8GCSqGSIb3DQEJBDEyBDBAgVYLLf7I
# yrik4I5hTtr+NYeW2lUrhkhvx1XBJGdtNT3YOM3p/8QxyaXVqDg5CxQwgZ8GCyqG
# SIb3DQEJEAIMMYGPMIGMMIGJMIGGBBS/T2vEmC3eFQWo78jHp51NFDUAzjBuMFqk
# WDBWMQswCQYDVQQGEwJQTDEhMB8GA1UEChMYQXNzZWNvIERhdGEgU3lzdGVtcyBT
# LkEuMSQwIgYDVQQDExtDZXJ0dW0gVGltZXN0YW1waW5nIDIwMjEgQ0ECECvUrnC5
# 0GNbKumEyNZ0qjAwDQYJKoZIhvcNAQEBBQAEggIAuK8Lta4LDMeYIlJeEkUMH96+
# ryW1l+l8PKnociuSi1yylsStr71yA13gSMXUoH2oESmII0eLLjb+l/ljiMChl9lO
# 9eM7IhTHAiP1FKoikyBb5TbXmsgxb8t5yx6uTIhbwIKlMLU4x0IbjyCfDLeZqUzK
# tu6Uehh1IiGB0sJ32JtP+m2nQfgDy3eoDIzA1iuLZwF3jW4OalskIVNT53GcS/E8
# BAdFaxPrrqHWdG5Fn2vjTq57N5WyCEOqqgR7VR9jXwG7QCu9ZwMNROVXX9Lu1b3W
# pcnaJez1dqugwB2ermcvfBa0qL5xZsfVBWlmDythPF9JU7BxiEe0S9MV5R0JkJtd
# PGUIIifGVZGO8OMgSf+JKgYxcDZcqhBAc1pOLKLUInZ93QpWihXayODQOR4gdEVj
# ZN4Llahz51J+lirZU0UDU+Di1G7BV6IvqAAMT6/6ghzExf1UgqU+FkoaIQz+CGsg
# SvHpCQDRSbUbLDsoRnJyVyePTOU82amUANj0BrZ8eIwWo0bZoGHnH7P2LrJNgk/u
# iKDJ/4VPo+qy1Orc+C6I4T2scSL19y+NfydLTWolc5fa4b4qvMAubQ+lMRPS6hFe
# /l3sBC2hTlN0cIaEv691crh/Z2PNx9P2VuUPQBR+CG5B+9C251UQT11pbtKL/ZmY
# rZ+2SX0omFm8D0Hvdg0=
# SIG # End signature block
