<#
.SYNOPSIS
    Integration tests for Find-Subset using AdventureWorks2019 database.

.DESCRIPTION
    Tests Find-Subset with complex multi-schema initial sets against the real
    AdventureWorks2019 database. Exercises cross-schema traversal, shared PK
    patterns, deep FK chains, junction tables, history tables, and more.

.NOTES
    PREREQUISITE: AdventureWorks2019 database must be installed on the target SQL Server.

    Configuration via environment variables:
    - SQLSIZER_TEST_SERVER: SQL Server instance (default: .)

.EXAMPLE
    Import-Module ./SqlSizer-MSSQL/SqlSizer-MSSQL.psd1 -Force
    Invoke-Pester -Path ./Tests/Find-Subset.AdventureWorks2019.Integration.Tests.ps1 -Output Detailed
#>

BeforeAll {
    # Import test helpers
    . "$PSScriptRoot\IntegrationTestHelpers.ps1"

    $script:TestDatabase = 'AdventureWorks2019'
    $script:Server = if ($env:SQLSIZER_TEST_SERVER) { $env:SQLSIZER_TEST_SERVER } else { '.' }

    # Create connection info (Windows Auth)
    $script:Connection = New-Object SqlConnectionInfo
    $script:Connection.Server = $script:Server
    $script:Connection.EncryptConnection = $false
    $script:Connection.Statistics = New-Object SqlConnectionStatistics

    # Configure dbatools for unencrypted local connections
    if (Get-Module -Name dbatools -ErrorAction SilentlyContinue) {
        Set-DbatoolsConfig -FullName sql.connection.trustcert -Value $true -PassThru | Register-DbatoolsConfig
        Set-DbatoolsConfig -FullName sql.connection.encrypt -Value $false -PassThru | Register-DbatoolsConfig
    }

    # Verify AdventureWorks2019 exists
    $dbExists = Test-DatabaseExists -Database $script:TestDatabase -ConnectionInfo $script:Connection
    if (-not $dbExists) {
        throw "AdventureWorks2019 database not found on server '$($script:Server)'. Please install it before running these tests."
    }

    Write-Host ""
    Write-Host "=====================================" -ForegroundColor Cyan
    Write-Host " AdventureWorks2019 Integration Tests" -ForegroundColor Cyan
    Write-Host "=====================================" -ForegroundColor Cyan
    Write-Host " Database:  $($script:TestDatabase)" -ForegroundColor White
    Write-Host " Server:    $($script:Server)" -ForegroundColor White
    Write-Host "=====================================" -ForegroundColor Cyan
    Write-Host ""

    # Get database metadata
    $script:DbInfo = Get-DatabaseInfo -Database $script:TestDatabase -ConnectionInfo $script:Connection

    # Install SqlSizer schema (Force to handle version mismatches in non-interactive mode)
    Install-SqlSizer -Database $script:TestDatabase -ConnectionInfo $script:Connection -DatabaseInfo $script:DbInfo -Force $true

    # Refresh database info after SqlSizer schema installation
    $script:DbInfo = Get-DatabaseInfo -Database $script:TestDatabase -ConnectionInfo $script:Connection

    # Clear any leftover sessions
    Clear-AllSessions -Database $script:TestDatabase -ConnectionInfo $script:Connection -DatabaseInfo $script:DbInfo
}

AfterAll {
    # Clean up SqlSizer from AdventureWorks2019
    try {
        Clear-AllSessions -Database $script:TestDatabase -ConnectionInfo $script:Connection -DatabaseInfo $script:DbInfo
        Uninstall-SqlSizer -Database $script:TestDatabase -ConnectionInfo $script:Connection -DatabaseInfo $script:DbInfo
    }
    catch {
        Write-Warning "Failed to clean up SqlSizer from AdventureWorks2019: $_"
    }

    Write-Host ""
    Write-Host "=====================================" -ForegroundColor Cyan
    Write-Host " AdventureWorks2019 Tests Complete" -ForegroundColor Cyan
    Write-Host "=====================================" -ForegroundColor Cyan
    Write-Host " SqlSizer schema removed from database." -ForegroundColor Yellow
    Write-Host "=====================================" -ForegroundColor Cyan
}

# =====================================================
# Cross-Schema Multi-Table Initial Sets
# =====================================================

Describe 'Cross-Schema Multi-Table Initial Sets' {
    AfterEach {
        if ($testResult -and $testResult.SessionId) {
            Remove-TestSession -SessionId $testResult.SessionId -Database $script:TestDatabase -DatabaseInfo $script:DbInfo -ConnectionInfo $script:Connection
        }
    }

    Context 'Sales + Person + Production convergence' {
        It 'Should traverse cross-schema graph from SalesOrderDetail + Person + Product seeds' {
            $queries = @(
                (New-TestQuery -Schema 'Sales' -Table 'SalesOrderDetail' `
                    -KeyColumns @('SalesOrderID', 'SalesOrderDetailID') -Top 5)
                (New-TestQuery -Schema 'Person' -Table 'Person' `
                    -KeyColumns @('BusinessEntityID') `
                    -Where "[`$table].BusinessEntityID = 1" -Top 1)
                (New-TestQuery -Schema 'Production' -Table 'Product' `
                    -KeyColumns @('ProductID') `
                    -Where "[`$table].Name = 'Mountain-100 Black, 42'" -Top 1)
            )

            $testResult = Invoke-FindSubsetTest `
                -Database $script:TestDatabase `
                -ConnectionInfo $script:Connection `
                -DatabaseInfo $script:DbInfo `
                -Queries $queries

            $testResult.Success | Should -Be $true
            $testResult.Result.Finished | Should -Be $true

            # Sales chain
            Assert-SubsetContains -SubsetSummary $testResult.Summary -Schema 'Sales' -Table 'SalesOrderDetail' -MinRows 1
            Assert-SubsetContains -SubsetSummary $testResult.Summary -Schema 'Sales' -Table 'SalesOrderHeader' -MinRows 1
            Assert-SubsetContains -SubsetSummary $testResult.Summary -Schema 'Sales' -Table 'Customer' -MinRows 1

            # Person chain
            Assert-SubsetContains -SubsetSummary $testResult.Summary -Schema 'Person' -Table 'Person' -MinRows 1
            Assert-SubsetContains -SubsetSummary $testResult.Summary -Schema 'Person' -Table 'BusinessEntity' -MinRows 1

            # Address chain (from SalesOrderHeader BillTo/ShipTo)
            Assert-SubsetContains -SubsetSummary $testResult.Summary -Schema 'Person' -Table 'Address' -MinRows 1
            Assert-SubsetContains -SubsetSummary $testResult.Summary -Schema 'Person' -Table 'StateProvince' -MinRows 1

            # Product chain
            Assert-SubsetContains -SubsetSummary $testResult.Summary -Schema 'Production' -Table 'Product' -MinRows 1
        }

        It 'Should unify HumanResources, Sales, and Purchasing graphs from multi-schema seeds' {
            $queries = @(
                (New-TestQuery -Schema 'HumanResources' -Table 'Employee' `
                    -KeyColumns @('BusinessEntityID') `
                    -Where "[`$table].JobTitle = 'Chief Executive Officer'" -Top 1)
                (New-TestQuery -Schema 'Sales' -Table 'SalesOrderHeader' `
                    -KeyColumns @('SalesOrderID') `
                    -Where "[`$table].SalesOrderID = 43659" -Top 1)
                (New-TestQuery -Schema 'Purchasing' -Table 'Vendor' `
                    -KeyColumns @('BusinessEntityID') -Top 1)
            )

            $testResult = Invoke-FindSubsetTest `
                -Database $script:TestDatabase `
                -ConnectionInfo $script:Connection `
                -DatabaseInfo $script:DbInfo `
                -Queries $queries

            $testResult.Success | Should -Be $true
            $testResult.Result.Finished | Should -Be $true

            # All three schema seeds present
            Assert-SubsetContains -SubsetSummary $testResult.Summary -Schema 'HumanResources' -Table 'Employee' -MinRows 1
            Assert-SubsetContains -SubsetSummary $testResult.Summary -Schema 'Sales' -Table 'SalesOrderHeader' -MinRows 1
            Assert-SubsetContains -SubsetSummary $testResult.Summary -Schema 'Purchasing' -Table 'Vendor' -MinRows 1

            # Shared PK hub: Employee and Vendor both FK to BusinessEntity
            Assert-SubsetContains -SubsetSummary $testResult.Summary -Schema 'Person' -Table 'BusinessEntity' -MinRows 2
        }
    }
}

# =====================================================
# Shared BusinessEntity Pattern
# =====================================================

Describe 'Shared BusinessEntity Pattern' {
    AfterEach {
        if ($testResult -and $testResult.SessionId) {
            Remove-TestSession -SessionId $testResult.SessionId -Database $script:TestDatabase -DatabaseInfo $script:DbInfo -ConnectionInfo $script:Connection
        }
    }

    Context 'Multiple entity types sharing BusinessEntity PK' {
        It 'Should deduplicate BusinessEntity rows with FullSearch=false' {
            $queries = @(
                (New-TestQuery -Schema 'HumanResources' -Table 'Employee' `
                    -KeyColumns @('BusinessEntityID') `
                    -Where "[`$table].BusinessEntityID = 1")
                (New-TestQuery -Schema 'Sales' -Table 'Store' `
                    -KeyColumns @('BusinessEntityID') `
                    -Where "[`$table].Name LIKE 'A%'" -Top 2)
                (New-TestQuery -Schema 'Person' -Table 'Person' `
                    -KeyColumns @('BusinessEntityID') `
                    -Where "[`$table].PersonType = 'SC'" -Top 3)
            )

            $testResult = Invoke-FindSubsetTest `
                -Database $script:TestDatabase `
                -ConnectionInfo $script:Connection `
                -DatabaseInfo $script:DbInfo `
                -Queries $queries `
                -FullSearch $false

            $testResult.Success | Should -Be $true
            $testResult.Result.Finished | Should -Be $true

            # All seeds present
            Assert-SubsetContains -SubsetSummary $testResult.Summary -Schema 'HumanResources' -Table 'Employee' -MinRows 1
            Assert-SubsetContains -SubsetSummary $testResult.Summary -Schema 'Sales' -Table 'Store' -MinRows 1
            Assert-SubsetContains -SubsetSummary $testResult.Summary -Schema 'Person' -Table 'Person' -MinRows 3
            Assert-SubsetContains -SubsetSummary $testResult.Summary -Schema 'Person' -Table 'BusinessEntity' -MinRows 3

            # Incoming FK tables should be EXCLUDED with FullSearch=false
            Assert-SubsetExcludes -SubsetSummary $testResult.Summary -Schema 'Person' -Table 'EmailAddress'
            Assert-SubsetExcludes -SubsetSummary $testResult.Summary -Schema 'Person' -Table 'PersonPhone'
        }

        It 'Should include incoming FKs from BusinessEntity with FullSearch=true' {
            $queries = @(
                (New-TestQuery -Schema 'HumanResources' -Table 'Employee' `
                    -KeyColumns @('BusinessEntityID') `
                    -Where "[`$table].BusinessEntityID = 1")
                (New-TestQuery -Schema 'Sales' -Table 'Store' `
                    -KeyColumns @('BusinessEntityID') `
                    -Where "[`$table].Name LIKE 'A%'" -Top 2)
                (New-TestQuery -Schema 'Person' -Table 'Person' `
                    -KeyColumns @('BusinessEntityID') `
                    -Where "[`$table].PersonType = 'SC'" -Top 3)
            )

            $testResult = Invoke-FindSubsetTest `
                -Database $script:TestDatabase `
                -ConnectionInfo $script:Connection `
                -DatabaseInfo $script:DbInfo `
                -Queries $queries `
                -FullSearch $true

            $testResult.Success | Should -Be $true
            $testResult.Result.Finished | Should -Be $true

            # All seeds present
            Assert-SubsetContains -SubsetSummary $testResult.Summary -Schema 'Person' -Table 'Person' -MinRows 3
            Assert-SubsetContains -SubsetSummary $testResult.Summary -Schema 'Person' -Table 'BusinessEntity' -MinRows 3

            # Incoming FK tables should now be PRESENT
            Assert-SubsetContains -SubsetSummary $testResult.Summary -Schema 'Person' -Table 'EmailAddress' -MinRows 1
            Assert-SubsetContains -SubsetSummary $testResult.Summary -Schema 'Person' -Table 'BusinessEntityAddress' -MinRows 1
        }
    }
}

# =====================================================
# Deep Real-World Chains with TraversalConfiguration
# =====================================================

Describe 'Deep Real-World Chains with TraversalConfiguration' {
    AfterEach {
        if ($testResult -and $testResult.SessionId) {
            Remove-TestSession -SessionId $testResult.SessionId -Database $script:TestDatabase -DatabaseInfo $script:DbInfo -ConnectionInfo $script:Connection
        }
    }

    Context 'Controlled depth on deep chains' {
        It 'Should respect MaxDepth constraint to stop chain before CountryRegion' {
            $query = New-TestQuery -Schema 'Sales' -Table 'SalesOrderDetail' `
                -KeyColumns @('SalesOrderID', 'SalesOrderDetailID') -Top 3

            $config = New-TraversalConfig -Rules @(
                (New-TraversalRuleWithMaxDepth -Schema 'Person' -Table 'CountryRegion' -MaxDepth 0)
            )

            $testResult = Invoke-FindSubsetTest `
                -Database $script:TestDatabase `
                -ConnectionInfo $script:Connection `
                -DatabaseInfo $script:DbInfo `
                -Queries @($query) `
                -TraversalConfiguration $config

            $testResult.Success | Should -Be $true
            $testResult.Result.Finished | Should -Be $true

            # Chain should include Address and StateProvince
            Assert-SubsetContains -SubsetSummary $testResult.Summary -Schema 'Sales' -Table 'SalesOrderDetail' -MinRows 1
            Assert-SubsetContains -SubsetSummary $testResult.Summary -Schema 'Sales' -Table 'SalesOrderHeader' -MinRows 1
            Assert-SubsetContains -SubsetSummary $testResult.Summary -Schema 'Person' -Table 'Address' -MinRows 1
            Assert-SubsetContains -SubsetSummary $testResult.Summary -Schema 'Person' -Table 'StateProvince' -MinRows 1

            # CountryRegion should be EXCLUDED due to MaxDepth=0
            Assert-SubsetExcludes -SubsetSummary $testResult.Summary -Schema 'Person' -Table 'CountryRegion'
        }

        It 'Should exclude Production tables via StateOverride while keeping Sales/Person graph' {
            $queries = @(
                (New-TestQuery -Schema 'Sales' -Table 'SalesOrderDetail' `
                    -KeyColumns @('SalesOrderID', 'SalesOrderDetailID') -Top 5)
                (New-TestQuery -Schema 'Sales' -Table 'Customer' `
                    -KeyColumns @('CustomerID') -Top 3)
            )

            $config = New-TraversalConfig -Rules @(
                (New-TraversalRuleWithStateOverride -Schema 'Production' -Table 'Product' -State ([TraversalState]::Exclude))
                (New-TraversalRuleWithStateOverride -Schema 'Production' -Table 'ProductSubcategory' -State ([TraversalState]::Exclude))
            )

            $testResult = Invoke-FindSubsetTest `
                -Database $script:TestDatabase `
                -ConnectionInfo $script:Connection `
                -DatabaseInfo $script:DbInfo `
                -Queries $queries `
                -TraversalConfiguration $config

            $testResult.Success | Should -Be $true
            $testResult.Result.Finished | Should -Be $true

            # Sales/Person graph should be present
            Assert-SubsetContains -SubsetSummary $testResult.Summary -Schema 'Sales' -Table 'SalesOrderDetail' -MinRows 1
            Assert-SubsetContains -SubsetSummary $testResult.Summary -Schema 'Sales' -Table 'SalesOrderHeader' -MinRows 1
            Assert-SubsetContains -SubsetSummary $testResult.Summary -Schema 'Sales' -Table 'Customer' -MinRows 1

            # Production tables should be EXCLUDED
            Assert-SubsetExcludes -SubsetSummary $testResult.Summary -Schema 'Production' -Table 'Product'
            Assert-SubsetExcludes -SubsetSummary $testResult.Summary -Schema 'Production' -Table 'ProductSubcategory'
        }
    }
}

# =====================================================
# Many-to-Many and Junction Table Patterns
# =====================================================

Describe 'Many-to-Many and Junction Table Patterns' {
    AfterEach {
        if ($testResult -and $testResult.SessionId) {
            Remove-TestSession -SessionId $testResult.SessionId -Database $script:TestDatabase -DatabaseInfo $script:DbInfo -ConnectionInfo $script:Connection
        }
    }

    Context 'Product + Vendor through ProductVendor junction' {
        It 'Should NOT include ProductVendor junction with FullSearch=false' {
            $queries = @(
                (New-TestQuery -Schema 'Production' -Table 'Product' `
                    -KeyColumns @('ProductID') `
                    -Where "[`$table].Name = 'Blade'" -Top 1)
                (New-TestQuery -Schema 'Purchasing' -Table 'Vendor' `
                    -KeyColumns @('BusinessEntityID') -Top 1)
            )

            $testResult = Invoke-FindSubsetTest `
                -Database $script:TestDatabase `
                -ConnectionInfo $script:Connection `
                -DatabaseInfo $script:DbInfo `
                -Queries $queries `
                -FullSearch $false

            $testResult.Success | Should -Be $true
            $testResult.Result.Finished | Should -Be $true

            # Both seeds present
            Assert-SubsetContains -SubsetSummary $testResult.Summary -Schema 'Production' -Table 'Product' -MinRows 1
            Assert-SubsetContains -SubsetSummary $testResult.Summary -Schema 'Purchasing' -Table 'Vendor' -MinRows 1

            # Junction table should NOT appear (incoming FK from both sides)
            Assert-SubsetExcludes -SubsetSummary $testResult.Summary -Schema 'Purchasing' -Table 'ProductVendor'
        }

        It 'Should include ProductVendor junction with FullSearch=true' {
            $queries = @(
                (New-TestQuery -Schema 'Production' -Table 'Product' `
                    -KeyColumns @('ProductID') `
                    -Where "[`$table].Name = 'Blade'" -Top 1)
                (New-TestQuery -Schema 'Purchasing' -Table 'Vendor' `
                    -KeyColumns @('BusinessEntityID') -Top 1)
            )

            $testResult = Invoke-FindSubsetTest `
                -Database $script:TestDatabase `
                -ConnectionInfo $script:Connection `
                -DatabaseInfo $script:DbInfo `
                -Queries $queries `
                -FullSearch $true

            $testResult.Success | Should -Be $true
            $testResult.Result.Finished | Should -Be $true

            # Both seeds present
            Assert-SubsetContains -SubsetSummary $testResult.Summary -Schema 'Production' -Table 'Product' -MinRows 1
            Assert-SubsetContains -SubsetSummary $testResult.Summary -Schema 'Purchasing' -Table 'Vendor' -MinRows 1

            # Junction table should now appear via incoming FKs
            Assert-SubsetContains -SubsetSummary $testResult.Summary -Schema 'Purchasing' -Table 'ProductVendor' -MinRows 1
        }
    }
}

# =====================================================
# History Tables and Complex Composite Keys
# =====================================================

Describe 'History Tables and Complex Composite Keys' {
    AfterEach {
        if ($testResult -and $testResult.SessionId) {
            Remove-TestSession -SessionId $testResult.SessionId -Database $script:TestDatabase -DatabaseInfo $script:DbInfo -ConnectionInfo $script:Connection
        }
    }

    Context 'Employee with department and pay history' {
        It 'Should include history tables via IncludeFull state' {
            $query = New-TestQuery -Schema 'HumanResources' -Table 'Employee' `
                -KeyColumns @('BusinessEntityID') `
                -Where "[`$table].JobTitle = 'Chief Executive Officer'" -Top 1 `
                -State ([TraversalState]::IncludeFull)

            $testResult = Invoke-FindSubsetTest `
                -Database $script:TestDatabase `
                -ConnectionInfo $script:Connection `
                -DatabaseInfo $script:DbInfo `
                -Queries @($query) `
                -FullSearch $false

            $testResult.Success | Should -Be $true
            $testResult.Result.Finished | Should -Be $true

            # Employee seed
            Assert-SubsetContains -SubsetSummary $testResult.Summary -Schema 'HumanResources' -Table 'Employee' -MinRows 1

            # History tables via incoming FKs (IncludeFull forces incoming traversal)
            Assert-SubsetContains -SubsetSummary $testResult.Summary -Schema 'HumanResources' -Table 'EmployeeDepartmentHistory' -MinRows 1
            Assert-SubsetContains -SubsetSummary $testResult.Summary -Schema 'HumanResources' -Table 'EmployeePayHistory' -MinRows 1

            # Outgoing FKs from history tables
            Assert-SubsetContains -SubsetSummary $testResult.Summary -Schema 'HumanResources' -Table 'Department' -MinRows 1
            Assert-SubsetContains -SubsetSummary $testResult.Summary -Schema 'HumanResources' -Table 'Shift' -MinRows 1

            # Shared PK chain
            Assert-SubsetContains -SubsetSummary $testResult.Summary -Schema 'Person' -Table 'BusinessEntity' -MinRows 1
            Assert-SubsetContains -SubsetSummary $testResult.Summary -Schema 'Person' -Table 'Person' -MinRows 1
        }

        It 'Should limit history rows via Top constraint' {
            $query = New-TestQuery -Schema 'HumanResources' -Table 'Employee' `
                -KeyColumns @('BusinessEntityID') `
                -Where "[`$table].SalariedFlag = 1" -Top 5

            $config = New-TraversalConfig -Rules @(
                (New-TraversalRuleWithTop -Schema 'HumanResources' -Table 'EmployeeDepartmentHistory' -Top 2)
                (New-TraversalRuleWithTop -Schema 'HumanResources' -Table 'EmployeePayHistory' -Top 1)
            )

            $testResult = Invoke-FindSubsetTest `
                -Database $script:TestDatabase `
                -ConnectionInfo $script:Connection `
                -DatabaseInfo $script:DbInfo `
                -Queries @($query) `
                -FullSearch $true `
                -TraversalConfiguration $config

            $testResult.Success | Should -Be $true
            $testResult.Result.Finished | Should -Be $true

            # Employees present
            Assert-SubsetContains -SubsetSummary $testResult.Summary -Schema 'HumanResources' -Table 'Employee' -MinRows 5

            # History tables present but limited by Top constraint
            Assert-SubsetContains -SubsetSummary $testResult.Summary -Schema 'HumanResources' -Table 'EmployeeDepartmentHistory' -MinRows 1
            Assert-SubsetContains -SubsetSummary $testResult.Summary -Schema 'HumanResources' -Table 'EmployeePayHistory' -MinRows 1

            # Department and Shift pulled in from history
            Assert-SubsetContains -SubsetSummary $testResult.Summary -Schema 'HumanResources' -Table 'Department' -MinRows 1
            Assert-SubsetContains -SubsetSummary $testResult.Summary -Schema 'HumanResources' -Table 'Shift' -MinRows 1
        }
    }
}

# =====================================================
# Algorithm Equivalence and IgnoredTables
# =====================================================

Describe 'BFS vs DFS Equivalence on Real-World Schema' {
    AfterEach {
        if ($testResultBfs -and $testResultBfs.SessionId) {
            Remove-TestSession -SessionId $testResultBfs.SessionId -Database $script:TestDatabase -DatabaseInfo $script:DbInfo -ConnectionInfo $script:Connection
        }
        if ($testResultDfs -and $testResultDfs.SessionId) {
            Remove-TestSession -SessionId $testResultDfs.SessionId -Database $script:TestDatabase -DatabaseInfo $script:DbInfo -ConnectionInfo $script:Connection
        }
    }

    Context 'Algorithm equivalence with complex initial sets' {
        It 'Should produce same table set with BFS and DFS from multi-schema seeds' {
            $queries = @(
                (New-TestQuery -Schema 'Sales' -Table 'SalesOrderDetail' `
                    -KeyColumns @('SalesOrderID', 'SalesOrderDetailID') -Top 3)
                (New-TestQuery -Schema 'HumanResources' -Table 'Employee' `
                    -KeyColumns @('BusinessEntityID') `
                    -Where "[`$table].BusinessEntityID = 1")
                (New-TestQuery -Schema 'Person' -Table 'Person' `
                    -KeyColumns @('BusinessEntityID') `
                    -Where "[`$table].FirstName = 'Ken'" -Top 2)
            )

            # BFS run
            $testResultBfs = Invoke-FindSubsetTest `
                -Database $script:TestDatabase `
                -ConnectionInfo $script:Connection `
                -DatabaseInfo $script:DbInfo `
                -Queries $queries `
                -UseDfs $false

            # DFS run
            $testResultDfs = Invoke-FindSubsetTest `
                -Database $script:TestDatabase `
                -ConnectionInfo $script:Connection `
                -DatabaseInfo $script:DbInfo `
                -Queries $queries `
                -UseDfs $true

            $testResultBfs.Success | Should -Be $true
            $testResultDfs.Success | Should -Be $true
            $testResultBfs.Result.Finished | Should -Be $true
            $testResultDfs.Result.Finished | Should -Be $true

            # Both should produce the same set of table keys
            $bfsKeys = ($testResultBfs.Summary.Keys | Sort-Object)
            $dfsKeys = ($testResultDfs.Summary.Keys | Sort-Object)
            $bfsKeys | Should -Be $dfsKeys
        }
    }
}

Describe 'IgnoredTables Across Schemas' {
    AfterEach {
        if ($testResult -and $testResult.SessionId) {
            Remove-TestSession -SessionId $testResult.SessionId -Database $script:TestDatabase -DatabaseInfo $script:DbInfo -ConnectionInfo $script:Connection
        }
    }

    Context 'Cross-schema ignored tables with multi-schema seeds' {
        It 'Should correctly ignore tables across schemas during traversal' {
            $queries = @(
                (New-TestQuery -Schema 'Sales' -Table 'SalesOrderHeader' `
                    -KeyColumns @('SalesOrderID') `
                    -Where "[`$table].SalesOrderID BETWEEN 43659 AND 43665")
                (New-TestQuery -Schema 'Production' -Table 'Product' `
                    -KeyColumns @('ProductID') `
                    -Where "[`$table].ProductID = 680")
            )

            $ignoredTables = @(
                (Get-TestTableInfo -Schema 'Production' -Table 'TransactionHistory')
                (Get-TestTableInfo -Schema 'Production' -Table 'ProductReview')
            )

            $testResult = Invoke-FindSubsetTest `
                -Database $script:TestDatabase `
                -ConnectionInfo $script:Connection `
                -DatabaseInfo $script:DbInfo `
                -Queries $queries `
                -FullSearch $false `
                -IgnoredTables $ignoredTables

            $testResult.Success | Should -Be $true
            $testResult.Result.Finished | Should -Be $true

            # Seeds and their FK chains present
            Assert-SubsetContains -SubsetSummary $testResult.Summary -Schema 'Sales' -Table 'SalesOrderHeader' -MinRows 1
            Assert-SubsetContains -SubsetSummary $testResult.Summary -Schema 'Production' -Table 'Product' -MinRows 1
            Assert-SubsetContains -SubsetSummary $testResult.Summary -Schema 'Person' -Table 'Person' -MinRows 1

            # Ignored tables should be EXCLUDED
            Assert-SubsetExcludes -SubsetSummary $testResult.Summary -Schema 'Production' -Table 'TransactionHistory'
            Assert-SubsetExcludes -SubsetSummary $testResult.Summary -Schema 'Production' -Table 'ProductReview'
        }
    }
}
