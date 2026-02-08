<#
.SYNOPSIS
    Integration tests for Find-RemovalSubset cmdlet.
    
.DESCRIPTION
    Comprehensive tests for incoming FK traversal and deletion dependency discovery.
    Find-RemovalSubset identifies rows that reference target rows and must be deleted
    first to maintain referential integrity.
    
.NOTES
    IMPORTANT: Run this test via Run-RemovalSubsetTests.ps1 wrapper script!
    The wrapper loads the module first, which is required for type availability.
    
    Configuration via environment variables:
    - SQLSIZER_TEST_DATASIZE: Tiny, Small, Medium, Large, XLarge, Custom (default: Tiny)
    - SQLSIZER_TEST_CUSTOMROWCOUNT: Custom row count (default: 5000)
    - SQLSIZER_TEST_SERVER: SQL Server instance (default: .)
    - SQLSIZER_TEST_SKIPDATASETUP: 1 to skip (default: 0)
    
.EXAMPLE
    .\Run-RemovalSubsetTests.ps1 -DataSize Tiny
    
.EXAMPLE
    .\Run-RemovalSubsetTests.ps1 -DataSize Medium -SkipDataSetup
#>

BeforeAll {
    # Import test helpers
    . "$PSScriptRoot\IntegrationTestConfig.ps1"
    . "$PSScriptRoot\IntegrationTestHelpers.ps1"
    . "$PSScriptRoot\IntegrationTestData.ps1"
    
    # Read configuration from environment variables (with defaults)
    $DataSize = if ($env:SQLSIZER_TEST_DATASIZE) { $env:SQLSIZER_TEST_DATASIZE } else { 'Tiny' }
    $CustomRowCount = if ($env:SQLSIZER_TEST_CUSTOMROWCOUNT) { [int]$env:SQLSIZER_TEST_CUSTOMROWCOUNT } else { 5000 }
    $Server = if ($env:SQLSIZER_TEST_SERVER) { $env:SQLSIZER_TEST_SERVER } else { '.' }
    $SkipDataSetup = $env:SQLSIZER_TEST_SKIPDATASETUP -eq '1'
    
    # Test database name
    $script:TestDatabase = 'SqlSizerIntegrationTests'
    $script:Server = $Server
    
    # Create connection info directly (like existing unit tests do for other types)
    $script:Connection = New-Object SqlConnectionInfo
    $script:Connection.Server = $Server
    $script:Connection.EncryptConnection = $false
    $script:Connection.Statistics = New-Object SqlConnectionStatistics
    
    # Calculate row counts
    $script:RowCounts = Get-ScaledRowCounts -DataSize $DataSize -CustomRowCount $CustomRowCount
    $estimatedRows = Get-EstimatedRowCount -DataSize $DataSize -CustomRowCount $CustomRowCount
    $estimatedTime = Get-EstimatedRuntime -DataSize $DataSize
    
    Write-Host ""
    Write-Host "=====================================" -ForegroundColor Cyan
    Write-Host " Find-RemovalSubset Integration Tests" -ForegroundColor Cyan
    Write-Host "=====================================" -ForegroundColor Cyan
    Write-Host " DataSize:      $DataSize" -ForegroundColor White
    Write-Host " Est. Rows:     ~$estimatedRows" -ForegroundColor White
    Write-Host " Est. Runtime:  $estimatedTime" -ForegroundColor White
    Write-Host " Server:        $Server" -ForegroundColor White
    Write-Host "=====================================" -ForegroundColor Cyan
    Write-Host ""
    
    # Initialize database (or reuse)
    if (-not $SkipDataSetup) {
        Initialize-TestDatabase `
            -Database $script:TestDatabase `
            -ConnectionInfo $script:Connection `
            -RowCounts $script:RowCounts `
            -ReuseData:$SkipDataSetup
    }
    
    # Get database info for tests
    $script:DbInfo = Get-DatabaseInfo -Database $script:TestDatabase -ConnectionInfo $script:Connection
    
    # Install SqlSizer schema if needed
    Install-SqlSizer -Database $script:TestDatabase -ConnectionInfo $script:Connection -DatabaseInfo $script:DbInfo
    
    # Clear any existing sessions
    Clear-AllSessions -Database $script:TestDatabase -ConnectionInfo $script:Connection -DatabaseInfo $script:DbInfo
}

AfterAll {
    Write-Host ""
    Write-Host "=====================================" -ForegroundColor Cyan
    Write-Host " Test Complete" -ForegroundColor Cyan
    Write-Host "=====================================" -ForegroundColor Cyan
    Write-Host " Database '$script:TestDatabase' retained for inspection." -ForegroundColor Yellow
    Write-Host " Connection: $script:Server (Windows Auth)" -ForegroundColor White
    Write-Host "=====================================" -ForegroundColor Cyan
}

# =====================================================
# Basic Incoming FK Traversal Tests
# =====================================================

Describe 'Basic Incoming FK Traversal' {
    AfterEach {
        if ($testResult -and $testResult.SessionId) {
            Remove-TestSession -SessionId $testResult.SessionId -Database $script:TestDatabase -DatabaseInfo $script:DbInfo -ConnectionInfo $script:Connection
        }
    }
    
    Context 'Single-Hop Incoming FKs' {
        It 'Should find SubCategories referencing a Category' {
            # Category is referenced by SubCategories via FK
            # To delete a Category, we must first delete SubCategories that reference it
            $query = New-RemovalQuery -Schema 'dbo' -Table 'Categories' -KeyColumns @('CategoryId') `
                -Where "[`$table].ParentCategoryId IS NULL" -Top 1
            
            $testResult = Invoke-FindRemovalSubsetTest `
                -Database $script:TestDatabase `
                -ConnectionInfo $script:Connection `
                -DatabaseInfo $script:DbInfo `
                -Queries @($query)
            
            if (-not $testResult.Success) {
                Write-Host "ERROR: $($testResult.Error)" -ForegroundColor Red
            }
            $testResult.Success | Should -Be $true
            $testResult.Result.Finished | Should -Be $true
            
            # Should include the starting Category
            Assert-SubsetContains -SubsetSummary $testResult.Summary -Schema 'dbo' -Table 'Categories' -MinRows 1
            # Should include SubCategories that reference this Category
            Assert-SubsetContains -SubsetSummary $testResult.Summary -Schema 'dbo' -Table 'SubCategories' -MinRows 1
        }
        
        It 'Should find Products referencing a SubCategory' {
            $query = New-RemovalQuery -Schema 'dbo' -Table 'SubCategories' -KeyColumns @('SubCategoryId') -Top 1
            
            $testResult = Invoke-FindRemovalSubsetTest `
                -Database $script:TestDatabase `
                -ConnectionInfo $script:Connection `
                -DatabaseInfo $script:DbInfo `
                -Queries @($query)
            
            $testResult.Success | Should -Be $true
            Assert-SubsetContains -SubsetSummary $testResult.Summary -Schema 'dbo' -Table 'SubCategories' -MinRows 1
            # Products reference SubCategories
            Assert-SubsetContains -SubsetSummary $testResult.Summary -Schema 'dbo' -Table 'Products' -MinRows 1
        }
        
        It 'Should find ProductVariants referencing a Product' {
            $query = New-RemovalQuery -Schema 'dbo' -Table 'Products' -KeyColumns @('ProductId') -Top 1
            
            $testResult = Invoke-FindRemovalSubsetTest `
                -Database $script:TestDatabase `
                -ConnectionInfo $script:Connection `
                -DatabaseInfo $script:DbInfo `
                -Queries @($query)
            
            $testResult.Success | Should -Be $true
            Assert-SubsetContains -SubsetSummary $testResult.Summary -Schema 'dbo' -Table 'Products' -MinRows 1
            # ProductVariants reference Products
            Assert-SubsetContains -SubsetSummary $testResult.Summary -Schema 'dbo' -Table 'ProductVariants' -MinRows 1
        }
    }
    
    Context 'Multi-Hop Incoming FK Chains' {
        It 'Should traverse Category → SubCategories → Products → ProductVariants' {
            # Starting from Category, should find all dependents down the chain
            $query = New-RemovalQuery -Schema 'dbo' -Table 'Categories' -KeyColumns @('CategoryId') `
                -Where "[`$table].ParentCategoryId IS NULL" -Top 1
            
            $testResult = Invoke-FindRemovalSubsetTest `
                -Database $script:TestDatabase `
                -ConnectionInfo $script:Connection `
                -DatabaseInfo $script:DbInfo `
                -Queries @($query)
            
            $testResult.Success | Should -Be $true
            Assert-SubsetContains -SubsetSummary $testResult.Summary -Schema 'dbo' -Table 'Categories' -MinRows 1
            Assert-SubsetContains -SubsetSummary $testResult.Summary -Schema 'dbo' -Table 'SubCategories' -MinRows 1
            Assert-SubsetContains -SubsetSummary $testResult.Summary -Schema 'dbo' -Table 'Products' -MinRows 1
            Assert-SubsetContains -SubsetSummary $testResult.Summary -Schema 'dbo' -Table 'ProductVariants' -MinRows 1
        }
        
        It 'Should traverse Contact → Customer → Orders → OrderDetails' {
            $query = New-RemovalQuery -Schema 'dbo' -Table 'Contacts' -KeyColumns @('ContactId') -Top 1
            
            $testResult = Invoke-FindRemovalSubsetTest `
                -Database $script:TestDatabase `
                -ConnectionInfo $script:Connection `
                -DatabaseInfo $script:DbInfo `
                -Queries @($query)
            
            $testResult.Success | Should -Be $true
            Assert-SubsetContains -SubsetSummary $testResult.Summary -Schema 'dbo' -Table 'Contacts' -MinRows 1
            Assert-SubsetContains -SubsetSummary $testResult.Summary -Schema 'dbo' -Table 'Customers' -MinRows 1
            Assert-SubsetContains -SubsetSummary $testResult.Summary -Schema 'dbo' -Table 'Orders' -MinRows 1
            Assert-SubsetContains -SubsetSummary $testResult.Summary -Schema 'dbo' -Table 'OrderDetails' -MinRows 1
        }
    }
}

# =====================================================
# Self-Referencing Tables Tests
# =====================================================

Describe 'Self-Referencing Tables in Removal' {
    AfterEach {
        if ($testResult -and $testResult.SessionId) {
            Remove-TestSession -SessionId $testResult.SessionId -Database $script:TestDatabase -DatabaseInfo $script:DbInfo -ConnectionInfo $script:Connection
        }
    }
    
    Context 'Category Hierarchy' {
        It 'Should find child Categories when deleting parent Category' {
            # Find a parent category (one that has children)
            $query = New-RemovalQuery -Schema 'dbo' -Table 'Categories' -KeyColumns @('CategoryId') `
                -Where "[`$table].ParentCategoryId IS NULL" -Top 1
            
            $testResult = Invoke-FindRemovalSubsetTest `
                -Database $script:TestDatabase `
                -ConnectionInfo $script:Connection `
                -DatabaseInfo $script:DbInfo `
                -Queries @($query)
            
            $testResult.Success | Should -Be $true
            # Should find child categories (self-reference)
            Assert-SubsetContains -SubsetSummary $testResult.Summary -Schema 'dbo' -Table 'Categories' -MinRows 1
        }
    }
    
    Context 'Employee Manager Hierarchy' {
        It 'Should find subordinates when deleting manager Employee' {
            # Find a manager (has direct reports)
            $query = New-RemovalQuery -Schema 'dbo' -Table 'Employees' -KeyColumns @('EmployeeId') `
                -Where "[`$table].ManagerId IS NULL" -Top 1
            
            $testResult = Invoke-FindRemovalSubsetTest `
                -Database $script:TestDatabase `
                -ConnectionInfo $script:Connection `
                -DatabaseInfo $script:DbInfo `
                -Queries @($query)
            
            $testResult.Success | Should -Be $true
            # Should include employees who report to this manager (via ManagerId FK)
            Assert-SubsetContains -SubsetSummary $testResult.Summary -Schema 'dbo' -Table 'Employees' -MinRows 1
        }
        
        It 'Should find employees hired by this person (HiredById FK)' {
            $query = New-RemovalQuery -Schema 'dbo' -Table 'Employees' -KeyColumns @('EmployeeId') `
                -Where "[`$table].ManagerId IS NULL" -Top 1
            
            $testResult = Invoke-FindRemovalSubsetTest `
                -Database $script:TestDatabase `
                -ConnectionInfo $script:Connection `
                -DatabaseInfo $script:DbInfo `
                -Queries @($query)
            
            $testResult.Success | Should -Be $true
            $testResult.Result.Finished | Should -Be $true
        }
    }
    
    Context 'Comment Thread Hierarchy' {
        It 'Should find reply Comments when deleting parent Comment' {
            # Find a root comment (no parent)
            $query = New-RemovalQuery -Schema 'dbo' -Table 'Comments' -KeyColumns @('CommentId') `
                -Where "[`$table].ParentCommentId IS NULL" -Top 1
            
            $testResult = Invoke-FindRemovalSubsetTest `
                -Database $script:TestDatabase `
                -ConnectionInfo $script:Connection `
                -DatabaseInfo $script:DbInfo `
                -Queries @($query)
            
            $testResult.Success | Should -Be $true
            # Should include child comments (replies)
            Assert-SubsetContains -SubsetSummary $testResult.Summary -Schema 'dbo' -Table 'Comments' -MinRows 1
        }
    }
}

# =====================================================
# Circular Reference Tests
# =====================================================

Describe 'Circular References in Removal' {
    AfterEach {
        if ($testResult -and $testResult.SessionId) {
            Remove-TestSession -SessionId $testResult.SessionId -Database $script:TestDatabase -DatabaseInfo $script:DbInfo -ConnectionInfo $script:Connection
        }
    }
    
    Context 'Employee-Department Circular Reference' {
        It 'Should terminate correctly with Employee ↔ Department circular reference' {
            # Employee → Department (DeptId), Department → Employee (HeadId)
            $query = New-RemovalQuery -Schema 'dbo' -Table 'Employees' -KeyColumns @('EmployeeId') `
                -Where "[`$table].ManagerId IS NULL" -Top 1
            
            $testResult = Invoke-FindRemovalSubsetTest `
                -Database $script:TestDatabase `
                -ConnectionInfo $script:Connection `
                -DatabaseInfo $script:DbInfo `
                -Queries @($query)
            
            $testResult.Success | Should -Be $true
            $testResult.Result.Finished | Should -Be $true
            # Should not infinite loop
        }
        
        It 'Should handle circular refs starting from Department' {
            $query = New-RemovalQuery -Schema 'dbo' -Table 'Departments' -KeyColumns @('DeptId') -Top 1
            
            $testResult = Invoke-FindRemovalSubsetTest `
                -Database $script:TestDatabase `
                -ConnectionInfo $script:Connection `
                -DatabaseInfo $script:DbInfo `
                -Queries @($query)
            
            $testResult.Success | Should -Be $true
            $testResult.Result.Finished | Should -Be $true
        }
    }
}

# =====================================================
# Many-to-Many Junction Table Tests
# =====================================================

Describe 'Junction Tables in Removal' {
    AfterEach {
        if ($testResult -and $testResult.SessionId) {
            Remove-TestSession -SessionId $testResult.SessionId -Database $script:TestDatabase -DatabaseInfo $script:DbInfo -ConnectionInfo $script:Connection
        }
    }
    
    Context 'ProductSuppliers Junction' {
        It 'Should find ProductSuppliers when deleting Supplier' {
            $query = New-RemovalQuery -Schema 'dbo' -Table 'Suppliers' -KeyColumns @('SupplierId') -Top 1
            
            $testResult = Invoke-FindRemovalSubsetTest `
                -Database $script:TestDatabase `
                -ConnectionInfo $script:Connection `
                -DatabaseInfo $script:DbInfo `
                -Queries @($query)
            
            $testResult.Success | Should -Be $true
            Assert-SubsetContains -SubsetSummary $testResult.Summary -Schema 'dbo' -Table 'Suppliers' -MinRows 1
            # ProductSuppliers junction table references Suppliers
            Assert-SubsetContains -SubsetSummary $testResult.Summary -Schema 'dbo' -Table 'ProductSuppliers' -MinRows 1
        }
        
        It 'Should find ProductSuppliers when deleting Product' {
            $query = New-RemovalQuery -Schema 'dbo' -Table 'Products' -KeyColumns @('ProductId') -Top 1
            
            $testResult = Invoke-FindRemovalSubsetTest `
                -Database $script:TestDatabase `
                -ConnectionInfo $script:Connection `
                -DatabaseInfo $script:DbInfo `
                -Queries @($query)
            
            $testResult.Success | Should -Be $true
            Assert-SubsetContains -SubsetSummary $testResult.Summary -Schema 'dbo' -Table 'Products' -MinRows 1
            # ProductSuppliers junction table references Products
            Assert-SubsetContains -SubsetSummary $testResult.Summary -Schema 'dbo' -Table 'ProductSuppliers' -MinRows 1
        }
    }
    
    Context 'TeamMembers Junction' {
        It 'Should find TeamMembers when deleting Team' {
            $query = New-RemovalQuery -Schema 'dbo' -Table 'Teams' -KeyColumns @('TeamId') -Top 1
            
            $testResult = Invoke-FindRemovalSubsetTest `
                -Database $script:TestDatabase `
                -ConnectionInfo $script:Connection `
                -DatabaseInfo $script:DbInfo `
                -Queries @($query)
            
            $testResult.Success | Should -Be $true
            Assert-SubsetContains -SubsetSummary $testResult.Summary -Schema 'dbo' -Table 'Teams' -MinRows 1
            # TeamMembers junction references Teams
            Assert-SubsetContains -SubsetSummary $testResult.Summary -Schema 'dbo' -Table 'TeamMembers' -MinRows 1
        }
        
        It 'Should find TeamMembers and other refs when deleting Employee' {
            $query = New-RemovalQuery -Schema 'dbo' -Table 'Employees' -KeyColumns @('EmployeeId') -Top 1
            
            $testResult = Invoke-FindRemovalSubsetTest `
                -Database $script:TestDatabase `
                -ConnectionInfo $script:Connection `
                -DatabaseInfo $script:DbInfo `
                -Queries @($query)
            
            $testResult.Success | Should -Be $true
            Assert-SubsetContains -SubsetSummary $testResult.Summary -Schema 'dbo' -Table 'Employees' -MinRows 1
        }
    }
    
    Context 'EmployeeSkills Junction' {
        It 'Should find EmployeeSkills when deleting Skill' {
            $query = New-RemovalQuery -Schema 'dbo' -Table 'Skills' -KeyColumns @('SkillId') -Top 1
            
            $testResult = Invoke-FindRemovalSubsetTest `
                -Database $script:TestDatabase `
                -ConnectionInfo $script:Connection `
                -DatabaseInfo $script:DbInfo `
                -Queries @($query)
            
            $testResult.Success | Should -Be $true
            Assert-SubsetContains -SubsetSummary $testResult.Summary -Schema 'dbo' -Table 'Skills' -MinRows 1
            Assert-SubsetContains -SubsetSummary $testResult.Summary -Schema 'dbo' -Table 'EmployeeSkills' -MinRows 1
        }
    }
}

# =====================================================
# Composite Key Tests
# =====================================================

Describe 'Composite Keys in Removal' {
    AfterEach {
        if ($testResult -and $testResult.SessionId) {
            Remove-TestSession -SessionId $testResult.SessionId -Database $script:TestDatabase -DatabaseInfo $script:DbInfo -ConnectionInfo $script:Connection
        }
    }
    
    Context '2-Column Composite Key Tables' {
        It 'Should handle Inventory with (WarehouseId, ProductVariantId) composite key' {
            # Start from Warehouse, find Inventory rows
            $query = New-RemovalQuery -Schema 'dbo' -Table 'Warehouses' -KeyColumns @('WarehouseId') -Top 1
            
            $testResult = Invoke-FindRemovalSubsetTest `
                -Database $script:TestDatabase `
                -ConnectionInfo $script:Connection `
                -DatabaseInfo $script:DbInfo `
                -Queries @($query)
            
            $testResult.Success | Should -Be $true
            Assert-SubsetContains -SubsetSummary $testResult.Summary -Schema 'dbo' -Table 'Warehouses' -MinRows 1
            # Inventory table has composite PK and references Warehouses
            Assert-SubsetContains -SubsetSummary $testResult.Summary -Schema 'dbo' -Table 'Inventory' -MinRows 1
        }
        
        It 'Should handle OrderDetails with (OrderId, LineNum) composite key' {
            # Start from Order, find OrderDetails
            $query = New-RemovalQuery -Schema 'dbo' -Table 'Orders' -KeyColumns @('OrderId') -Top 1
            
            $testResult = Invoke-FindRemovalSubsetTest `
                -Database $script:TestDatabase `
                -ConnectionInfo $script:Connection `
                -DatabaseInfo $script:DbInfo `
                -Queries @($query)
            
            $testResult.Success | Should -Be $true
            Assert-SubsetContains -SubsetSummary $testResult.Summary -Schema 'dbo' -Table 'Orders' -MinRows 1
            Assert-SubsetContains -SubsetSummary $testResult.Summary -Schema 'dbo' -Table 'OrderDetails' -MinRows 1
        }
    }
    
    Context '3-Column Composite Key Tables' {
        It 'Should find EmployeeCertifications when deleting Certification' {
            # CertificationId=2 is known to have EmployeeCertifications references
            # Use a WHERE clause to pick a certification that has references
            $query = New-RemovalQuery -Schema 'dbo' -Table 'Certifications' `
                -KeyColumns @('CertificationId') `
                -Where "CertificationId IN (SELECT CertificationId FROM dbo.EmployeeCertifications)" `
                -Top 1
            
            $testResult = Invoke-FindRemovalSubsetTest `
                -Database $script:TestDatabase `
                -ConnectionInfo $script:Connection `
                -DatabaseInfo $script:DbInfo `
                -Queries @($query)
            
            $testResult.Success | Should -Be $true
            Assert-SubsetContains -SubsetSummary $testResult.Summary -Schema 'dbo' -Table 'Certifications' -MinRows 1
            # EmployeeCertifications has 3-column composite key
            Assert-SubsetContains -SubsetSummary $testResult.Summary -Schema 'dbo' -Table 'EmployeeCertifications' -MinRows 1
        }
    }
}

# =====================================================
# High Fanout Tests
# =====================================================

Describe 'High Fanout Patterns in Removal' {
    AfterEach {
        if ($testResult -and $testResult.SessionId) {
            Remove-TestSession -SessionId $testResult.SessionId -Database $script:TestDatabase -DatabaseInfo $script:DbInfo -ConnectionInfo $script:Connection
        }
    }
    
    Context 'Parent with Many Children' {
        It 'Should find all HighFanoutChildren when deleting HighFanoutParent' {
            $query = New-RemovalQuery -Schema 'dbo' -Table 'HighFanoutParent' -KeyColumns @('ParentId') -Top 1
            
            $testResult = Invoke-FindRemovalSubsetTest `
                -Database $script:TestDatabase `
                -ConnectionInfo $script:Connection `
                -DatabaseInfo $script:DbInfo `
                -Queries @($query)
            
            $testResult.Success | Should -Be $true
            Assert-SubsetContains -SubsetSummary $testResult.Summary -Schema 'dbo' -Table 'HighFanoutParent' -ExpectedRows 1
            # Should find all children referencing this parent
            Assert-SubsetContains -SubsetSummary $testResult.Summary -Schema 'dbo' -Table 'HighFanoutChildren' -MinRows 10
        }
    }
}

# =====================================================
# Deep Chain Tests
# =====================================================

Describe 'Deep FK Chains in Removal' {
    AfterEach {
        if ($testResult -and $testResult.SessionId) {
            Remove-TestSession -SessionId $testResult.SessionId -Database $script:TestDatabase -DatabaseInfo $script:DbInfo -ConnectionInfo $script:Connection
        }
    }
    
    Context '8-Level Deep Chain' {
        It 'Should traverse A → B → C → D → E → F → G → H (all dependents)' {
            # Starting from DeepChainA, should find all tables that eventually depend on it
            $query = New-RemovalQuery -Schema 'dbo' -Table 'DeepChainA' -KeyColumns @('Id') -Top 1
            
            $testResult = Invoke-FindRemovalSubsetTest `
                -Database $script:TestDatabase `
                -ConnectionInfo $script:Connection `
                -DatabaseInfo $script:DbInfo `
                -Queries @($query)
            
            $testResult.Success | Should -Be $true
            # All 8 tables should be included as they form a chain of dependencies
            Assert-SubsetContains -SubsetSummary $testResult.Summary -Schema 'dbo' -Table 'DeepChainA' -ExpectedRows 1
            Assert-SubsetContains -SubsetSummary $testResult.Summary -Schema 'dbo' -Table 'DeepChainB' -MinRows 1
            Assert-SubsetContains -SubsetSummary $testResult.Summary -Schema 'dbo' -Table 'DeepChainC' -MinRows 1
            Assert-SubsetContains -SubsetSummary $testResult.Summary -Schema 'dbo' -Table 'DeepChainD' -MinRows 1
            Assert-SubsetContains -SubsetSummary $testResult.Summary -Schema 'dbo' -Table 'DeepChainE' -MinRows 1
            Assert-SubsetContains -SubsetSummary $testResult.Summary -Schema 'dbo' -Table 'DeepChainF' -MinRows 1
            Assert-SubsetContains -SubsetSummary $testResult.Summary -Schema 'dbo' -Table 'DeepChainG' -MinRows 1
            Assert-SubsetContains -SubsetSummary $testResult.Summary -Schema 'dbo' -Table 'DeepChainH' -MinRows 1
        }
    }
}

# =====================================================
# Edge Cases Tests
# =====================================================

Describe 'Edge Cases in Removal' {
    AfterEach {
        if ($testResult -and $testResult.SessionId) {
            Remove-TestSession -SessionId $testResult.SessionId -Database $script:TestDatabase -DatabaseInfo $script:DbInfo -ConnectionInfo $script:Connection
        }
    }
    
    Context 'Empty Results' {
        It 'Should handle query that matches zero rows' {
            $query = New-RemovalQuery -Schema 'dbo' -Table 'Products' -KeyColumns @('ProductId') `
                -Where "[`$table].ProductId = -999999"
            
            $testResult = Invoke-FindRemovalSubsetTest `
                -Database $script:TestDatabase `
                -ConnectionInfo $script:Connection `
                -DatabaseInfo $script:DbInfo `
                -Queries @($query)
            
            $testResult.Success | Should -Be $true
            $testResult.Result.Finished | Should -Be $true
            
            # No rows should be in subset
            $total = Get-TotalSubsetRows -SubsetSummary $testResult.Summary
            $total | Should -Be 0
        }
    }
    
    Context 'Orphan Tables' {
        It 'Should handle orphan table with no incoming FKs (Settings)' {
            # Settings table has no foreign keys pointing to it
            $query = New-RemovalQuery -Schema 'dbo' -Table 'Settings' -KeyColumns @('SettingId') -Top 1
            
            $testResult = Invoke-FindRemovalSubsetTest `
                -Database $script:TestDatabase `
                -ConnectionInfo $script:Connection `
                -DatabaseInfo $script:DbInfo `
                -Queries @($query)
            
            $testResult.Success | Should -Be $true
            Assert-SubsetContains -SubsetSummary $testResult.Summary -Schema 'dbo' -Table 'Settings' -ExpectedRows 1
            
            # Total should be just 1 (no dependent tables)
            $total = Get-TotalSubsetRows -SubsetSummary $testResult.Summary
            $total | Should -Be 1
        }
    }
    
    Context 'Multiple Starting Queries' {
        It 'Should handle multiple removal queries' {
            $query1 = New-RemovalQuery -Schema 'dbo' -Table 'Categories' -KeyColumns @('CategoryId') `
                -Where "[`$table].ParentCategoryId IS NULL" -Top 1
            $query2 = New-RemovalQuery -Schema 'dbo' -Table 'Contacts' -KeyColumns @('ContactId') -Top 1
            
            $testResult = Invoke-FindRemovalSubsetTest `
                -Database $script:TestDatabase `
                -ConnectionInfo $script:Connection `
                -DatabaseInfo $script:DbInfo `
                -Queries @($query1, $query2)
            
            $testResult.Success | Should -Be $true
            Assert-SubsetContains -SubsetSummary $testResult.Summary -Schema 'dbo' -Table 'Categories' -MinRows 1
            Assert-SubsetContains -SubsetSummary $testResult.Summary -Schema 'dbo' -Table 'Contacts' -MinRows 1
        }
    }
}

# =====================================================
# MaxBatchSize Tests
# =====================================================

Describe 'MaxBatchSize in Removal' {
    AfterEach {
        if ($testResult -and $testResult.SessionId) {
            Remove-TestSession -SessionId $testResult.SessionId -Database $script:TestDatabase -DatabaseInfo $script:DbInfo -ConnectionInfo $script:Connection
        }
    }
    
    Context 'Batch Processing' {
        It 'Should complete with MaxBatchSize chunking' {
            $query = New-RemovalQuery -Schema 'dbo' -Table 'Categories' -KeyColumns @('CategoryId') `
                -Where "[`$table].ParentCategoryId IS NULL" -Top 1
            
            $testResult = Invoke-FindRemovalSubsetTest `
                -Database $script:TestDatabase `
                -ConnectionInfo $script:Connection `
                -DatabaseInfo $script:DbInfo `
                -Queries @($query) `
                -MaxBatchSize 2
            
            $testResult.Success | Should -Be $true
            $testResult.Result.Finished | Should -Be $true
        }
    }
}

# =====================================================
# Interactive Mode Tests
# =====================================================

Describe 'Interactive Mode in Removal' {
    AfterEach {
        if ($sessionId) {
            Remove-TestSession -SessionId $sessionId -Database $script:TestDatabase -DatabaseInfo $script:DbInfo -ConnectionInfo $script:Connection
        }
    }
    
    Context 'Controlled Iteration' {
        It 'Should allow single iteration with Interactive=true' {
            $sessionId = Start-SqlSizerSession `
                -Database $script:TestDatabase `
                -ConnectionInfo $script:Connection `
                -DatabaseInfo $script:DbInfo `
                -Removal $true
            
            $query = New-RemovalQuery -Schema 'dbo' -Table 'Products' -KeyColumns @('ProductId') -Top 1
            
            Initialize-StartSet `
                -Database $script:TestDatabase `
                -ConnectionInfo $script:Connection `
                -Queries @($query) `
                -DatabaseInfo $script:DbInfo `
                -SessionId $sessionId
            
            # First iteration (initialization)
            $result0 = Find-RemovalSubset `
                -Database $script:TestDatabase `
                -ConnectionInfo $script:Connection `
                -DatabaseInfo $script:DbInfo `
                -SessionId $sessionId `
                -Interactive $true `
                -Iteration 0
            
            $result0.Initialized | Should -Be $true
            
            # Second iteration (actual work)
            $result1 = Find-RemovalSubset `
                -Database $script:TestDatabase `
                -ConnectionInfo $script:Connection `
                -DatabaseInfo $script:DbInfo `
                -SessionId $sessionId `
                -Interactive $true `
                -Iteration 1
            
            $result1.CompletedIterations | Should -Be 1
        }
        
        It 'Should complete after multiple iterations' {
            $sessionId = Start-SqlSizerSession `
                -Database $script:TestDatabase `
                -ConnectionInfo $script:Connection `
                -DatabaseInfo $script:DbInfo `
                -Removal $true
            
            $query = New-RemovalQuery -Schema 'dbo' -Table 'Products' -KeyColumns @('ProductId') -Top 1
            
            Initialize-StartSet `
                -Database $script:TestDatabase `
                -ConnectionInfo $script:Connection `
                -Queries @($query) `
                -DatabaseInfo $script:DbInfo `
                -SessionId $sessionId
            
            # Initialize
            Find-RemovalSubset `
                -Database $script:TestDatabase `
                -ConnectionInfo $script:Connection `
                -DatabaseInfo $script:DbInfo `
                -SessionId $sessionId `
                -Interactive $true `
                -Iteration 0
            
            # Run until finished
            $iteration = 1
            $maxIterations = 50
            $finished = $false
            
            while (-not $finished -and $iteration -lt $maxIterations) {
                $result = Find-RemovalSubset `
                    -Database $script:TestDatabase `
                    -ConnectionInfo $script:Connection `
                    -DatabaseInfo $script:DbInfo `
                    -SessionId $sessionId `
                    -Interactive $true `
                    -Iteration $iteration
                
                $finished = $result.Finished
                $iteration++
            }
            
            $finished | Should -Be $true
        }
    }
}

# =====================================================
# Diamond Pattern Tests (Multiple FK paths to same table)
# =====================================================

Describe 'Diamond Pattern in Removal' {
    AfterEach {
        if ($testResult -and $testResult.SessionId) {
            Remove-TestSession -SessionId $testResult.SessionId -Database $script:TestDatabase -DatabaseInfo $script:DbInfo -ConnectionInfo $script:Connection
        }
    }
    
    Context 'Multiple Incoming FKs' {
        It 'Should find Customers with multiple contact FKs when deleting Contact' {
            # Customers have PrimaryContactId, BillingContactId, ShippingContactId → Contacts
            $query = New-RemovalQuery -Schema 'dbo' -Table 'Contacts' -KeyColumns @('ContactId') -Top 1
            
            $testResult = Invoke-FindRemovalSubsetTest `
                -Database $script:TestDatabase `
                -ConnectionInfo $script:Connection `
                -DatabaseInfo $script:DbInfo `
                -Queries @($query)
            
            $testResult.Success | Should -Be $true
            Assert-SubsetContains -SubsetSummary $testResult.Summary -Schema 'dbo' -Table 'Contacts' -MinRows 1
            # Customers reference Contacts via multiple FKs
            Assert-SubsetContains -SubsetSummary $testResult.Summary -Schema 'dbo' -Table 'Customers' -MinRows 1
        }
    }
}

# =====================================================
# Multi-Tenant Pattern Tests
# =====================================================

Describe 'Multi-Tenant Pattern in Removal' {
    AfterEach {
        if ($testResult -and $testResult.SessionId) {
            Remove-TestSession -SessionId $testResult.SessionId -Database $script:TestDatabase -DatabaseInfo $script:DbInfo -ConnectionInfo $script:Connection
        }
    }
    
    Context 'Tenant Deletion' {
        It 'Should find TenantProducts when deleting Tenant' {
            $query = New-RemovalQuery -Schema 'dbo' -Table 'Tenants' -KeyColumns @('TenantId') -Top 1
            
            $testResult = Invoke-FindRemovalSubsetTest `
                -Database $script:TestDatabase `
                -ConnectionInfo $script:Connection `
                -DatabaseInfo $script:DbInfo `
                -Queries @($query)
            
            $testResult.Success | Should -Be $true
            Assert-SubsetContains -SubsetSummary $testResult.Summary -Schema 'dbo' -Table 'Tenants' -MinRows 1
            Assert-SubsetContains -SubsetSummary $testResult.Summary -Schema 'dbo' -Table 'TenantProducts' -MinRows 1
        }
    }
}

# =====================================================
# Wide Table Tests (Table with Many Incoming FKs)
# =====================================================

Describe 'Wide Table Pattern (Many Incoming FKs)' {
    AfterEach {
        if ($testResult -and $testResult.SessionId) {
            Remove-TestSession -SessionId $testResult.SessionId -Database $script:TestDatabase -DatabaseInfo $script:DbInfo -ConnectionInfo $script:Connection
        }
    }
    
    Context 'Employee with Many References' {
        It 'Should find all tables referencing Employee via incoming FKs' {
            # Employee is referenced by: Teams (LeaderId), Warehouses (ManagerId), 
            # EmployeeJobHistory, EmployeeSkills, TeamMembers, etc.
            $query = New-RemovalQuery -Schema 'dbo' -Table 'Employees' -KeyColumns @('EmployeeId') `
                -Where "[`$table].ManagerId IS NULL" -Top 1
            
            $testResult = Invoke-FindRemovalSubsetTest `
                -Database $script:TestDatabase `
                -ConnectionInfo $script:Connection `
                -DatabaseInfo $script:DbInfo `
                -Queries @($query)
            
            $testResult.Success | Should -Be $true
            Assert-SubsetContains -SubsetSummary $testResult.Summary -Schema 'dbo' -Table 'Employees' -MinRows 1
            # Should find some or all of the referencing tables
        }
    }
}
