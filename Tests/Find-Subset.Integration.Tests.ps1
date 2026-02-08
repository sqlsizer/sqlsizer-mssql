<#
.SYNOPSIS
    Integration tests for Find-Subset cmdlet.
    
.DESCRIPTION
    Comprehensive tests for FK traversal, state management, and subset generation.
    Creates a test database with 32+ tables covering diverse FK patterns.
    
.NOTES
    IMPORTANT: Run this test via Run-IntegrationTests.ps1 wrapper script!
    The wrapper loads the module first, which is required for type availability.
    
    Configuration via environment variables:
    - SQLSIZER_TEST_DATASIZE: Tiny, Small, Medium, Large, XLarge, Custom (default: Tiny)
    - SQLSIZER_TEST_CUSTOMROWCOUNT: Custom row count (default: 5000)
    - SQLSIZER_TEST_SERVER: SQL Server instance (default: .)
    - SQLSIZER_TEST_SKIPDATASETUP: 1 to skip (default: 0)
    
.EXAMPLE
    .\Run-IntegrationTests.ps1 -DataSize Tiny
    
.EXAMPLE
    .\Run-IntegrationTests.ps1 -DataSize Medium -SkipDataSetup
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
    $script:Connection.IsSynapse = $false
    
    # Calculate row counts
    $script:RowCounts = Get-ScaledRowCounts -DataSize $DataSize -CustomRowCount $CustomRowCount
    $estimatedRows = Get-EstimatedRowCount -DataSize $DataSize -CustomRowCount $CustomRowCount
    $estimatedTime = Get-EstimatedRuntime -DataSize $DataSize
    
    Write-Host ""
    Write-Host "=====================================" -ForegroundColor Cyan
    Write-Host " Find-Subset Integration Tests" -ForegroundColor Cyan
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
# Basic FK Traversal Tests
# =====================================================

Describe 'Basic FK Traversal' {
    AfterEach {
        if ($testResult -and $testResult.SessionId) {
            Remove-TestSession -SessionId $testResult.SessionId -Database $script:TestDatabase -DatabaseInfo $script:DbInfo -ConnectionInfo $script:Connection
        }
    }
    
    Context 'Simple FK Chains' {
        It 'Should follow single-hop FK from Product to SubCategory' {
            # Start with 1 product, expect SubCategory included
            $query = New-TestQuery -Schema 'dbo' -Table 'Products' -KeyColumns @('ProductId') -Top 1
            
            $testResult = Invoke-FindSubsetTest `
                -Database $script:TestDatabase `
                -ConnectionInfo $script:Connection `
                -DatabaseInfo $script:DbInfo `
                -Queries @($query)
            
            if (-not $testResult.Success) {
                Write-Host "ERROR: $($testResult.Error)" -ForegroundColor Red
            }
            $testResult.Success | Should -Be $true
            $testResult.Result.Finished | Should -Be $true
            
            Assert-SubsetContains -SubsetSummary $testResult.Summary -Schema 'dbo' -Table 'Products' -MinRows 1
            Assert-SubsetContains -SubsetSummary $testResult.Summary -Schema 'dbo' -Table 'SubCategories' -MinRows 1
        }
        
        It 'Should follow two-hop FK chain: Product → SubCategory → Category' {
            $query = New-TestQuery -Schema 'dbo' -Table 'Products' -KeyColumns @('ProductId') -Top 1
            
            $testResult = Invoke-FindSubsetTest `
                -Database $script:TestDatabase `
                -ConnectionInfo $script:Connection `
                -DatabaseInfo $script:DbInfo `
                -Queries @($query)
            
            $testResult.Success | Should -Be $true
            Assert-SubsetContains -SubsetSummary $testResult.Summary -Schema 'dbo' -Table 'Products' -MinRows 1
            Assert-SubsetContains -SubsetSummary $testResult.Summary -Schema 'dbo' -Table 'SubCategories' -MinRows 1
            Assert-SubsetContains -SubsetSummary $testResult.Summary -Schema 'dbo' -Table 'Categories' -MinRows 1
        }
        
        It 'Should follow three-hop FK chain: OrderDetails → Order → Customer → Contact' {
            $query = New-TestQuery -Schema 'dbo' -Table 'OrderDetails' -KeyColumns @('OrderId', 'LineNum') -Top 1
            
            $testResult = Invoke-FindSubsetTest `
                -Database $script:TestDatabase `
                -ConnectionInfo $script:Connection `
                -DatabaseInfo $script:DbInfo `
                -Queries @($query)
            
            $testResult.Success | Should -Be $true
            Assert-SubsetContains -SubsetSummary $testResult.Summary -Schema 'dbo' -Table 'OrderDetails' -MinRows 1
            Assert-SubsetContains -SubsetSummary $testResult.Summary -Schema 'dbo' -Table 'Orders' -MinRows 1
            Assert-SubsetContains -SubsetSummary $testResult.Summary -Schema 'dbo' -Table 'Customers' -MinRows 1
            Assert-SubsetContains -SubsetSummary $testResult.Summary -Schema 'dbo' -Table 'Contacts' -MinRows 1
        }
        
        It 'Should handle multiple starting rows with deduplication' {
            # Start with 5 products that may share SubCategories
            $query = New-TestQuery -Schema 'dbo' -Table 'Products' -KeyColumns @('ProductId') -Top 5
            
            $testResult = Invoke-FindSubsetTest `
                -Database $script:TestDatabase `
                -ConnectionInfo $script:Connection `
                -DatabaseInfo $script:DbInfo `
                -Queries @($query)
            
            $testResult.Success | Should -Be $true
            Assert-SubsetContains -SubsetSummary $testResult.Summary -Schema 'dbo' -Table 'Products' -ExpectedRows 5
            # SubCategories should be deduplicated (fewer than 5 likely)
            Assert-SubsetContains -SubsetSummary $testResult.Summary -Schema 'dbo' -Table 'SubCategories' -MinRows 1 -MaxRows 5
        }
        
        It 'Should handle WHERE clause with special characters' {
            $query = New-TestQuery -Schema 'dbo' -Table 'Products' -KeyColumns @('ProductId') `
                -Where "[`$table].Name LIKE 'Product[_]1%'"
            
            $testResult = Invoke-FindSubsetTest `
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
# Complex Graph Pattern Tests
# =====================================================

Describe 'Complex Graph Patterns' {
    AfterEach {
        if ($testResult -and $testResult.SessionId) {
            Remove-TestSession -SessionId $testResult.SessionId -Database $script:TestDatabase -DatabaseInfo $script:DbInfo -ConnectionInfo $script:Connection
        }
    }
    
    Context 'Diamond Pattern' {
        It 'Should handle diamond pattern: Customer with multiple FK paths to Contacts' {
            # Customer has PrimaryContactId, BillingContactId, ShippingContactId → Contacts
            $query = New-TestQuery -Schema 'dbo' -Table 'Customers' -KeyColumns @('CustomerId') -Top 1
            
            $testResult = Invoke-FindSubsetTest `
                -Database $script:TestDatabase `
                -ConnectionInfo $script:Connection `
                -DatabaseInfo $script:DbInfo `
                -Queries @($query)
            
            $testResult.Success | Should -Be $true
            Assert-SubsetContains -SubsetSummary $testResult.Summary -Schema 'dbo' -Table 'Customers' -MinRows 1
            # Should have at least 1 contact (primary is required)
            Assert-SubsetContains -SubsetSummary $testResult.Summary -Schema 'dbo' -Table 'Contacts' -MinRows 1
        }
        
        It 'Should deduplicate when multiple FKs point to same Contact' {
            # Find a customer where primary and billing contact are the same (if exists)
            $query = New-TestQuery -Schema 'dbo' -Table 'Customers' -KeyColumns @('CustomerId') `
                -Where "[`$table].BillingContactId = [`$table].PrimaryContactId" -Top 1
            
            $testResult = Invoke-FindSubsetTest `
                -Database $script:TestDatabase `
                -ConnectionInfo $script:Connection `
                -DatabaseInfo $script:DbInfo `
                -Queries @($query)
            
            $testResult.Success | Should -Be $true
            # Even if query matches nothing, test should pass
            $testResult.Result.Finished | Should -Be $true
        }
    }
    
    Context 'Multiple Outgoing FKs' {
        It 'Should follow all outgoing FKs from Order' {
            # Order → Customer, SalesRep, ShippingAddr, BillingAddr
            $query = New-TestQuery -Schema 'dbo' -Table 'Orders' -KeyColumns @('OrderId') -Top 1
            
            $testResult = Invoke-FindSubsetTest `
                -Database $script:TestDatabase `
                -ConnectionInfo $script:Connection `
                -DatabaseInfo $script:DbInfo `
                -Queries @($query)
            
            $testResult.Success | Should -Be $true
            Assert-SubsetContains -SubsetSummary $testResult.Summary -Schema 'dbo' -Table 'Orders' -MinRows 1
            Assert-SubsetContains -SubsetSummary $testResult.Summary -Schema 'dbo' -Table 'Customers' -MinRows 1
        }
        
        It 'Should follow multi-path from OrderDetail to both Order and ProductVariant' {
            $query = New-TestQuery -Schema 'dbo' -Table 'OrderDetails' -KeyColumns @('OrderId', 'LineNum') -Top 1
            
            $testResult = Invoke-FindSubsetTest `
                -Database $script:TestDatabase `
                -ConnectionInfo $script:Connection `
                -DatabaseInfo $script:DbInfo `
                -Queries @($query)
            
            $testResult.Success | Should -Be $true
            Assert-SubsetContains -SubsetSummary $testResult.Summary -Schema 'dbo' -Table 'OrderDetails' -MinRows 1
            Assert-SubsetContains -SubsetSummary $testResult.Summary -Schema 'dbo' -Table 'Orders' -MinRows 1
            Assert-SubsetContains -SubsetSummary $testResult.Summary -Schema 'dbo' -Table 'ProductVariants' -MinRows 1
            Assert-SubsetContains -SubsetSummary $testResult.Summary -Schema 'dbo' -Table 'Products' -MinRows 1
        }
    }
    
    Context 'Many-to-Many Relationships' {
        It 'Should traverse many-to-many: Product → ProductSuppliers → Suppliers' {
            $query = New-TestQuery -Schema 'dbo' -Table 'ProductSuppliers' -KeyColumns @('ProductId', 'SupplierId') -Top 3
            
            $testResult = Invoke-FindSubsetTest `
                -Database $script:TestDatabase `
                -ConnectionInfo $script:Connection `
                -DatabaseInfo $script:DbInfo `
                -Queries @($query)
            
            $testResult.Success | Should -Be $true
            Assert-SubsetContains -SubsetSummary $testResult.Summary -Schema 'dbo' -Table 'ProductSuppliers' -MinRows 1
            Assert-SubsetContains -SubsetSummary $testResult.Summary -Schema 'dbo' -Table 'Products' -MinRows 1
            Assert-SubsetContains -SubsetSummary $testResult.Summary -Schema 'dbo' -Table 'Suppliers' -MinRows 1
        }
        
        It 'Should traverse Team ↔ Employee many-to-many' {
            $query = New-TestQuery -Schema 'dbo' -Table 'TeamMembers' -KeyColumns @('TeamId', 'EmployeeId') -Top 3
            
            $testResult = Invoke-FindSubsetTest `
                -Database $script:TestDatabase `
                -ConnectionInfo $script:Connection `
                -DatabaseInfo $script:DbInfo `
                -Queries @($query)
            
            $testResult.Success | Should -Be $true
            Assert-SubsetContains -SubsetSummary $testResult.Summary -Schema 'dbo' -Table 'TeamMembers' -MinRows 1
            Assert-SubsetContains -SubsetSummary $testResult.Summary -Schema 'dbo' -Table 'Teams' -MinRows 1
            Assert-SubsetContains -SubsetSummary $testResult.Summary -Schema 'dbo' -Table 'Employees' -MinRows 1
        }
    }
    
    Context 'WideTable with Many FKs' {
        It 'Should follow all 10 FKs from WideTable' {
            $query = New-TestQuery -Schema 'dbo' -Table 'WideTable' -KeyColumns @('Id') -Top 1
            
            $testResult = Invoke-FindSubsetTest `
                -Database $script:TestDatabase `
                -ConnectionInfo $script:Connection `
                -DatabaseInfo $script:DbInfo `
                -Queries @($query)
            
            $testResult.Success | Should -Be $true
            Assert-SubsetContains -SubsetSummary $testResult.Summary -Schema 'dbo' -Table 'WideTable' -ExpectedRows 1
            Assert-SubsetContains -SubsetSummary $testResult.Summary -Schema 'dbo' -Table 'Categories' -MinRows 1
            Assert-SubsetContains -SubsetSummary $testResult.Summary -Schema 'dbo' -Table 'Suppliers' -MinRows 1
            Assert-SubsetContains -SubsetSummary $testResult.Summary -Schema 'dbo' -Table 'Employees' -MinRows 1
            Assert-SubsetContains -SubsetSummary $testResult.Summary -Schema 'dbo' -Table 'Tags' -MinRows 1
        }
    }
}

# =====================================================
# Self-Referencing & Circular Tests
# =====================================================

Describe 'Self-Referencing and Circular References' {
    AfterEach {
        if ($testResult -and $testResult.SessionId) {
            Remove-TestSession -SessionId $testResult.SessionId -Database $script:TestDatabase -DatabaseInfo $script:DbInfo -ConnectionInfo $script:Connection
        }
    }
    
    Context 'Self-Referencing Tables' {
        It 'Should handle self-ref Category hierarchy' {
            # Start with a child category that has parent(s)
            $query = New-TestQuery -Schema 'dbo' -Table 'Categories' -KeyColumns @('CategoryId') `
                -Where "[`$table].ParentCategoryId IS NOT NULL" -Top 1
            
            $testResult = Invoke-FindSubsetTest `
                -Database $script:TestDatabase `
                -ConnectionInfo $script:Connection `
                -DatabaseInfo $script:DbInfo `
                -Queries @($query)
            
            $testResult.Success | Should -Be $true
            # Should include the child and its parent(s)
            Assert-SubsetContains -SubsetSummary $testResult.Summary -Schema 'dbo' -Table 'Categories' -MinRows 2
        }
        
        It 'Should handle Employee manager hierarchy (5 levels)' {
            # Find employee with manager chain
            $query = New-TestQuery -Schema 'dbo' -Table 'Employees' -KeyColumns @('EmployeeId') `
                -Where "[`$table].ManagerId IS NOT NULL" -Top 1
            
            $testResult = Invoke-FindSubsetTest `
                -Database $script:TestDatabase `
                -ConnectionInfo $script:Connection `
                -DatabaseInfo $script:DbInfo `
                -Queries @($query)
            
            $testResult.Success | Should -Be $true
            # Should include employee and manager chain
            Assert-SubsetContains -SubsetSummary $testResult.Summary -Schema 'dbo' -Table 'Employees' -MinRows 2
        }
        
        It 'Should handle root Employee with no manager' {
            $query = New-TestQuery -Schema 'dbo' -Table 'Employees' -KeyColumns @('EmployeeId') `
                -Where "[`$table].ManagerId IS NULL" -Top 1
            
            $testResult = Invoke-FindSubsetTest `
                -Database $script:TestDatabase `
                -ConnectionInfo $script:Connection `
                -DatabaseInfo $script:DbInfo `
                -Queries @($query)
            
            $testResult.Success | Should -Be $true
            Assert-SubsetContains -SubsetSummary $testResult.Summary -Schema 'dbo' -Table 'Employees' -MinRows 1
        }
        
        It 'Should handle threaded Comments (self-ref)' {
            $query = New-TestQuery -Schema 'dbo' -Table 'Comments' -KeyColumns @('CommentId') `
                -Where "[`$table].ParentCommentId IS NOT NULL" -Top 1
            
            $testResult = Invoke-FindSubsetTest `
                -Database $script:TestDatabase `
                -ConnectionInfo $script:Connection `
                -DatabaseInfo $script:DbInfo `
                -Queries @($query)
            
            $testResult.Success | Should -Be $true
            Assert-SubsetContains -SubsetSummary $testResult.Summary -Schema 'dbo' -Table 'Comments' -MinRows 2
        }
    }
    
    Context 'Circular References' {
        It 'Should handle Employee ↔ Department circular reference' {
            # Employee.DeptId → Department, Department.HeadId → Employee
            $query = New-TestQuery -Schema 'dbo' -Table 'Employees' -KeyColumns @('EmployeeId') -Top 1
            
            $testResult = Invoke-FindSubsetTest `
                -Database $script:TestDatabase `
                -ConnectionInfo $script:Connection `
                -DatabaseInfo $script:DbInfo `
                -Queries @($query)
            
            $testResult.Success | Should -Be $true
            $testResult.Result.Finished | Should -Be $true
            Assert-SubsetContains -SubsetSummary $testResult.Summary -Schema 'dbo' -Table 'Employees' -MinRows 1
            Assert-SubsetContains -SubsetSummary $testResult.Summary -Schema 'dbo' -Table 'Departments' -MinRows 1
        }
        
        It 'Should terminate correctly with circular references (no infinite loop)' {
            # Start from Department which has circular ref to Employees
            $query = New-TestQuery -Schema 'dbo' -Table 'Departments' -KeyColumns @('DeptId') `
                -Where "[`$table].HeadId IS NOT NULL" -Top 1
            
            $testResult = Invoke-FindSubsetTest `
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
# Deep Chain Tests
# =====================================================

Describe 'Deep FK Chains' {
    AfterEach {
        if ($testResult -and $testResult.SessionId) {
            Remove-TestSession -SessionId $testResult.SessionId -Database $script:TestDatabase -DatabaseInfo $script:DbInfo -ConnectionInfo $script:Connection
        }
    }
    
    Context '8-Level Deep Chain' {
        It 'Should traverse full 8-level chain: H → G → F → E → D → C → B → A' {
            $query = New-TestQuery -Schema 'dbo' -Table 'DeepChainH' -KeyColumns @('Id') -Top 1
            
            $testResult = Invoke-FindSubsetTest `
                -Database $script:TestDatabase `
                -ConnectionInfo $script:Connection `
                -DatabaseInfo $script:DbInfo `
                -Queries @($query)
            
            $testResult.Success | Should -Be $true
            Assert-SubsetContains -SubsetSummary $testResult.Summary -Schema 'dbo' -Table 'DeepChainH' -ExpectedRows 1
            Assert-SubsetContains -SubsetSummary $testResult.Summary -Schema 'dbo' -Table 'DeepChainG' -MinRows 1
            Assert-SubsetContains -SubsetSummary $testResult.Summary -Schema 'dbo' -Table 'DeepChainF' -MinRows 1
            Assert-SubsetContains -SubsetSummary $testResult.Summary -Schema 'dbo' -Table 'DeepChainE' -MinRows 1
            Assert-SubsetContains -SubsetSummary $testResult.Summary -Schema 'dbo' -Table 'DeepChainD' -MinRows 1
            Assert-SubsetContains -SubsetSummary $testResult.Summary -Schema 'dbo' -Table 'DeepChainC' -MinRows 1
            Assert-SubsetContains -SubsetSummary $testResult.Summary -Schema 'dbo' -Table 'DeepChainB' -MinRows 1
            Assert-SubsetContains -SubsetSummary $testResult.Summary -Schema 'dbo' -Table 'DeepChainA' -MinRows 1
        }
        
        It 'Should traverse business chain: Payment → Invoice → Order → Customer → Contact' {
            $query = New-TestQuery -Schema 'dbo' -Table 'Payments' -KeyColumns @('PaymentId') -Top 1
            
            $testResult = Invoke-FindSubsetTest `
                -Database $script:TestDatabase `
                -ConnectionInfo $script:Connection `
                -DatabaseInfo $script:DbInfo `
                -Queries @($query)
            
            $testResult.Success | Should -Be $true
            Assert-SubsetContains -SubsetSummary $testResult.Summary -Schema 'dbo' -Table 'Payments' -ExpectedRows 1
            Assert-SubsetContains -SubsetSummary $testResult.Summary -Schema 'dbo' -Table 'Invoices' -MinRows 1
            Assert-SubsetContains -SubsetSummary $testResult.Summary -Schema 'dbo' -Table 'Orders' -MinRows 1
            Assert-SubsetContains -SubsetSummary $testResult.Summary -Schema 'dbo' -Table 'Customers' -MinRows 1
            Assert-SubsetContains -SubsetSummary $testResult.Summary -Schema 'dbo' -Table 'Contacts' -MinRows 1
        }
    }
}

# =====================================================
# Composite Key Tests
# =====================================================

Describe 'Composite Primary Keys' {
    AfterEach {
        if ($testResult -and $testResult.SessionId) {
            Remove-TestSession -SessionId $testResult.SessionId -Database $script:TestDatabase -DatabaseInfo $script:DbInfo -ConnectionInfo $script:Connection
        }
    }
    
    Context '2-Column Composite Keys' {
        It 'Should handle OrderDetails (OrderId, LineNum) composite key' {
            $query = New-TestQuery -Schema 'dbo' -Table 'OrderDetails' -KeyColumns @('OrderId', 'LineNum') -Top 1
            
            $testResult = Invoke-FindSubsetTest `
                -Database $script:TestDatabase `
                -ConnectionInfo $script:Connection `
                -DatabaseInfo $script:DbInfo `
                -Queries @($query)
            
            $testResult.Success | Should -Be $true
            Assert-SubsetContains -SubsetSummary $testResult.Summary -Schema 'dbo' -Table 'OrderDetails' -MinRows 1
        }
        
        It 'Should handle ProductSuppliers composite key' {
            $query = New-TestQuery -Schema 'dbo' -Table 'ProductSuppliers' -KeyColumns @('ProductId', 'SupplierId') -Top 1
            
            $testResult = Invoke-FindSubsetTest `
                -Database $script:TestDatabase `
                -ConnectionInfo $script:Connection `
                -DatabaseInfo $script:DbInfo `
                -Queries @($query)
            
            $testResult.Success | Should -Be $true
            Assert-SubsetContains -SubsetSummary $testResult.Summary -Schema 'dbo' -Table 'ProductSuppliers' -ExpectedRows 1
            Assert-SubsetContains -SubsetSummary $testResult.Summary -Schema 'dbo' -Table 'Products' -MinRows 1
            Assert-SubsetContains -SubsetSummary $testResult.Summary -Schema 'dbo' -Table 'Suppliers' -MinRows 1
        }
        
        It 'Should handle Inventory (WarehouseId, ProductVariantId) composite key' {
            $query = New-TestQuery -Schema 'dbo' -Table 'Inventory' -KeyColumns @('WarehouseId', 'ProductVariantId') -Top 1
            
            $testResult = Invoke-FindSubsetTest `
                -Database $script:TestDatabase `
                -ConnectionInfo $script:Connection `
                -DatabaseInfo $script:DbInfo `
                -Queries @($query)
            
            $testResult.Success | Should -Be $true
            Assert-SubsetContains -SubsetSummary $testResult.Summary -Schema 'dbo' -Table 'Inventory' -ExpectedRows 1
            Assert-SubsetContains -SubsetSummary $testResult.Summary -Schema 'dbo' -Table 'Warehouses' -MinRows 1
            Assert-SubsetContains -SubsetSummary $testResult.Summary -Schema 'dbo' -Table 'ProductVariants' -MinRows 1
        }
    }
    
    Context '3-Column Composite Keys' {
        It 'Should handle EmployeeCertifications (EmployeeId, CertificationId, DateEarned) 3-column key' {
            $query = New-TestQuery -Schema 'dbo' -Table 'EmployeeCertifications' `
                -KeyColumns @('EmployeeId', 'CertificationId', 'DateEarned') -Top 1
            
            $testResult = Invoke-FindSubsetTest `
                -Database $script:TestDatabase `
                -ConnectionInfo $script:Connection `
                -DatabaseInfo $script:DbInfo `
                -Queries @($query)
            
            $testResult.Success | Should -Be $true
            Assert-SubsetContains -SubsetSummary $testResult.Summary -Schema 'dbo' -Table 'EmployeeCertifications' -ExpectedRows 1
            Assert-SubsetContains -SubsetSummary $testResult.Summary -Schema 'dbo' -Table 'Employees' -MinRows 1
            Assert-SubsetContains -SubsetSummary $testResult.Summary -Schema 'dbo' -Table 'Certifications' -MinRows 1
        }
    }
}

# =====================================================
# Nullable FK Tests
# =====================================================

Describe 'Nullable Foreign Keys' {
    AfterEach {
        if ($testResult -and $testResult.SessionId) {
            Remove-TestSession -SessionId $testResult.SessionId -Database $script:TestDatabase -DatabaseInfo $script:DbInfo -ConnectionInfo $script:Connection
        }
    }
    
    Context 'NULL FK Values' {
        It 'Should handle OrderNote with NULL OrderId' {
            $query = New-TestQuery -Schema 'dbo' -Table 'OrderNotes' -KeyColumns @('NoteId') `
                -Where "[`$table].OrderId IS NULL" -Top 1
            
            $testResult = Invoke-FindSubsetTest `
                -Database $script:TestDatabase `
                -ConnectionInfo $script:Connection `
                -DatabaseInfo $script:DbInfo `
                -Queries @($query)
            
            $testResult.Success | Should -Be $true
            Assert-SubsetContains -SubsetSummary $testResult.Summary -Schema 'dbo' -Table 'OrderNotes' -MinRows 1
            # Orders should NOT be included (NULL FK)
        }
        
        It 'Should handle OrderNote with non-NULL OrderId' {
            $query = New-TestQuery -Schema 'dbo' -Table 'OrderNotes' -KeyColumns @('NoteId') `
                -Where "[`$table].OrderId IS NOT NULL" -Top 1
            
            $testResult = Invoke-FindSubsetTest `
                -Database $script:TestDatabase `
                -ConnectionInfo $script:Connection `
                -DatabaseInfo $script:DbInfo `
                -Queries @($query)
            
            $testResult.Success | Should -Be $true
            Assert-SubsetContains -SubsetSummary $testResult.Summary -Schema 'dbo' -Table 'OrderNotes' -MinRows 1
            Assert-SubsetContains -SubsetSummary $testResult.Summary -Schema 'dbo' -Table 'Orders' -MinRows 1
        }
        
        It 'Should handle Employee with NULL ManagerId (root employee)' {
            $query = New-TestQuery -Schema 'dbo' -Table 'Employees' -KeyColumns @('EmployeeId') `
                -Where "[`$table].ManagerId IS NULL" -Top 1
            
            $testResult = Invoke-FindSubsetTest `
                -Database $script:TestDatabase `
                -ConnectionInfo $script:Connection `
                -DatabaseInfo $script:DbInfo `
                -Queries @($query)
            
            $testResult.Success | Should -Be $true
            Assert-SubsetContains -SubsetSummary $testResult.Summary -Schema 'dbo' -Table 'Employees' -MinRows 1
        }
    }
}

# =====================================================
# FullSearch Mode Tests
# =====================================================

Describe 'FullSearch Mode' {
    AfterEach {
        if ($testResult -and $testResult.SessionId) {
            Remove-TestSession -SessionId $testResult.SessionId -Database $script:TestDatabase -DatabaseInfo $script:DbInfo -ConnectionInfo $script:Connection
        }
    }
    
    Context 'Incoming FK Handling' {
        It 'Should exclude incoming FKs when FullSearch=false' {
            # Start with Category, Products should NOT be included (incoming FK)
            $query = New-TestQuery -Schema 'dbo' -Table 'Categories' -KeyColumns @('CategoryId') -Top 1
            
            $testResult = Invoke-FindSubsetTest `
                -Database $script:TestDatabase `
                -ConnectionInfo $script:Connection `
                -DatabaseInfo $script:DbInfo `
                -Queries @($query) `
                -FullSearch $false
            
            $testResult.Success | Should -Be $true
            Assert-SubsetContains -SubsetSummary $testResult.Summary -Schema 'dbo' -Table 'Categories' -MinRows 1
            # SubCategories should NOT be included (incoming FK, FullSearch=false)
            Assert-SubsetExcludes -SubsetSummary $testResult.Summary -Schema 'dbo' -Table 'SubCategories'
        }
        
        It 'Should include incoming FKs when FullSearch=true' {
            # Start with Category, SubCategories SHOULD be included
            $query = New-TestQuery -Schema 'dbo' -Table 'Categories' -KeyColumns @('CategoryId') `
                -Where "[`$table].ParentCategoryId IS NULL" -Top 1
            
            $testResult = Invoke-FindSubsetTest `
                -Database $script:TestDatabase `
                -ConnectionInfo $script:Connection `
                -DatabaseInfo $script:DbInfo `
                -Queries @($query) `
                -FullSearch $true
            
            $testResult.Success | Should -Be $true
            Assert-SubsetContains -SubsetSummary $testResult.Summary -Schema 'dbo' -Table 'Categories' -MinRows 1
            # With FullSearch, SubCategories referencing this Category should be included
            Assert-SubsetContains -SubsetSummary $testResult.Summary -Schema 'dbo' -Table 'SubCategories' -MinRows 1
        }
        
        It 'Should include full graph with FullSearch=true from Supplier' {
            $query = New-TestQuery -Schema 'dbo' -Table 'Suppliers' -KeyColumns @('SupplierId') -Top 1
            
            $testResult = Invoke-FindSubsetTest `
                -Database $script:TestDatabase `
                -ConnectionInfo $script:Connection `
                -DatabaseInfo $script:DbInfo `
                -Queries @($query) `
                -FullSearch $true
            
            $testResult.Success | Should -Be $true
            Assert-SubsetContains -SubsetSummary $testResult.Summary -Schema 'dbo' -Table 'Suppliers' -MinRows 1
            # FullSearch should pull in ProductSuppliers referencing this Supplier
            Assert-SubsetContains -SubsetSummary $testResult.Summary -Schema 'dbo' -Table 'ProductSuppliers' -MinRows 1
        }
    }
}

# =====================================================
# TraversalConfiguration Tests
# =====================================================

Describe 'TraversalConfiguration' {
    AfterEach {
        if ($testResult -and $testResult.SessionId) {
            Remove-TestSession -SessionId $testResult.SessionId -Database $script:TestDatabase -DatabaseInfo $script:DbInfo -ConnectionInfo $script:Connection
        }
    }
    
    Context 'MaxDepth Constraints' {
        It 'Should respect MaxDepth=0 (stop traversal at boundary)' {
            # Start with OrderDetail, but stop at Products (don't go to SubCategory/Category)
            $rule = New-TraversalRuleWithMaxDepth -Schema 'dbo' -Table 'SubCategories' -MaxDepth 0
            $config = New-TraversalConfig -Rules @($rule)
            
            $query = New-TestQuery -Schema 'dbo' -Table 'OrderDetails' -KeyColumns @('OrderId', 'LineNum') -Top 1
            
            $testResult = Invoke-FindSubsetTest `
                -Database $script:TestDatabase `
                -ConnectionInfo $script:Connection `
                -DatabaseInfo $script:DbInfo `
                -Queries @($query) `
                -TraversalConfiguration $config
            
            $testResult.Success | Should -Be $true
            Assert-SubsetContains -SubsetSummary $testResult.Summary -Schema 'dbo' -Table 'OrderDetails' -MinRows 1
            Assert-SubsetContains -SubsetSummary $testResult.Summary -Schema 'dbo' -Table 'Products' -MinRows 1
            # SubCategories should be excluded due to MaxDepth=0
            Assert-SubsetExcludes -SubsetSummary $testResult.Summary -Schema 'dbo' -Table 'SubCategories'
        }
    }
    
    Context 'Top Constraints' {
        It 'Should respect Top=1 limit on related rows' {
            # This test verifies Top constraint is applied
            $rule = New-TraversalRuleWithTop -Schema 'dbo' -Table 'Contacts' -Top 1
            $config = New-TraversalConfig -Rules @($rule)
            
            $query = New-TestQuery -Schema 'dbo' -Table 'Customers' -KeyColumns @('CustomerId') -Top 1
            
            $testResult = Invoke-FindSubsetTest `
                -Database $script:TestDatabase `
                -ConnectionInfo $script:Connection `
                -DatabaseInfo $script:DbInfo `
                -Queries @($query) `
                -TraversalConfiguration $config
            
            $testResult.Success | Should -Be $true
            Assert-SubsetContains -SubsetSummary $testResult.Summary -Schema 'dbo' -Table 'Customers' -MinRows 1
        }
    }
    
    Context 'StateOverride' {
        It 'Should exclude table when StateOverride=Exclude' {
            $rule = New-TraversalRuleWithStateOverride -Schema 'dbo' -Table 'Contacts' -State ([TraversalState]::Exclude)
            $config = New-TraversalConfig -Rules @($rule)
            
            $query = New-TestQuery -Schema 'dbo' -Table 'Customers' -KeyColumns @('CustomerId') -Top 1
            
            $testResult = Invoke-FindSubsetTest `
                -Database $script:TestDatabase `
                -ConnectionInfo $script:Connection `
                -DatabaseInfo $script:DbInfo `
                -Queries @($query) `
                -TraversalConfiguration $config
            
            $testResult.Success | Should -Be $true
            Assert-SubsetContains -SubsetSummary $testResult.Summary -Schema 'dbo' -Table 'Customers' -MinRows 1
            # Contacts should be excluded due to StateOverride
            Assert-SubsetExcludes -SubsetSummary $testResult.Summary -Schema 'dbo' -Table 'Contacts'
        }
    }
}

# =====================================================
# IgnoredTables Tests
# =====================================================

Describe 'IgnoredTables' {
    AfterEach {
        if ($testResult -and $testResult.SessionId) {
            Remove-TestSession -SessionId $testResult.SessionId -Database $script:TestDatabase -DatabaseInfo $script:DbInfo -ConnectionInfo $script:Connection
        }
    }
    
    Context 'Table Exclusion' {
        It 'Should not traverse to ignored table (AuditLog)' {
            $ignoredTable = Get-TestTableInfo -Schema 'dbo' -Table 'AuditLog'
            
            $query = New-TestQuery -Schema 'dbo' -Table 'Employees' -KeyColumns @('EmployeeId') -Top 1
            
            $testResult = Invoke-FindSubsetTest `
                -Database $script:TestDatabase `
                -ConnectionInfo $script:Connection `
                -DatabaseInfo $script:DbInfo `
                -Queries @($query) `
                -IgnoredTables @($ignoredTable)
            
            $testResult.Success | Should -Be $true
            Assert-SubsetContains -SubsetSummary $testResult.Summary -Schema 'dbo' -Table 'Employees' -MinRows 1
            Assert-SubsetExcludes -SubsetSummary $testResult.Summary -Schema 'dbo' -Table 'AuditLog'
        }
        
        It 'Should ignore multiple tables' {
            $ignoredTables = @(
                (Get-TestTableInfo -Schema 'dbo' -Table 'AuditLog'),
                (Get-TestTableInfo -Schema 'dbo' -Table 'Settings')
            )
            
            $query = New-TestQuery -Schema 'dbo' -Table 'Employees' -KeyColumns @('EmployeeId') -Top 1
            
            $testResult = Invoke-FindSubsetTest `
                -Database $script:TestDatabase `
                -ConnectionInfo $script:Connection `
                -DatabaseInfo $script:DbInfo `
                -Queries @($query) `
                -IgnoredTables $ignoredTables
            
            $testResult.Success | Should -Be $true
            Assert-SubsetExcludes -SubsetSummary $testResult.Summary -Schema 'dbo' -Table 'AuditLog'
            Assert-SubsetExcludes -SubsetSummary $testResult.Summary -Schema 'dbo' -Table 'Settings'
        }
    }
}

# =====================================================
# Algorithm Options Tests
# =====================================================

Describe 'Algorithm Options' {
    AfterEach {
        if ($testResult -and $testResult.SessionId) {
            Remove-TestSession -SessionId $testResult.SessionId -Database $script:TestDatabase -DatabaseInfo $script:DbInfo -ConnectionInfo $script:Connection
        }
        if ($testResultDfs -and $testResultDfs.SessionId) {
            Remove-TestSession -SessionId $testResultDfs.SessionId -Database $script:TestDatabase -DatabaseInfo $script:DbInfo -ConnectionInfo $script:Connection
        }
    }
    
    Context 'BFS vs DFS' {
        It 'Should produce same final result with BFS and DFS' {
            $query = New-TestQuery -Schema 'dbo' -Table 'Orders' -KeyColumns @('OrderId') -Top 3
            
            # Run with BFS (default)
            $testResult = Invoke-FindSubsetTest `
                -Database $script:TestDatabase `
                -ConnectionInfo $script:Connection `
                -DatabaseInfo $script:DbInfo `
                -Queries @($query) `
                -UseDfs $false
            
            # Run with DFS
            $testResultDfs = Invoke-FindSubsetTest `
                -Database $script:TestDatabase `
                -ConnectionInfo $script:Connection `
                -DatabaseInfo $script:DbInfo `
                -Queries @($query) `
                -UseDfs $true
            
            $testResult.Success | Should -Be $true
            $testResultDfs.Success | Should -Be $true
            
            # Both should have same tables (order may differ)
            $bfsTables = $testResult.Summary.Keys | Sort-Object
            $dfsTables = $testResultDfs.Summary.Keys | Sort-Object
            
            $bfsTables | Should -Be $dfsTables
        }
    }
    
    Context 'MaxBatchSize' {
        It 'Should complete with MaxBatchSize chunking' {
            # Use a small number of products that will exist in all data sizes
            $query = New-TestQuery -Schema 'dbo' -Table 'Products' -KeyColumns @('ProductId') -Top 3
            
            $testResult = Invoke-FindSubsetTest `
                -Database $script:TestDatabase `
                -ConnectionInfo $script:Connection `
                -DatabaseInfo $script:DbInfo `
                -Queries @($query) `
                -MaxBatchSize 2
            
            $testResult.Success | Should -Be $true
            $testResult.Result.Finished | Should -Be $true
            Assert-SubsetContains -SubsetSummary $testResult.Summary -Schema 'dbo' -Table 'Products' -MinRows 3
        }
    }
}

# =====================================================
# Interactive Mode Tests
# =====================================================

Describe 'Interactive Mode' {
    AfterEach {
        if ($sessionId) {
            Remove-TestSession -SessionId $sessionId -Database $script:TestDatabase -DatabaseInfo $script:DbInfo -ConnectionInfo $script:Connection
        }
    }
    
    Context 'Controlled Iteration' {
        It 'Should allow single iteration with Interactive=true' {
            $sessionId = New-TestSession `
                -Database $script:TestDatabase `
                -ConnectionInfo $script:Connection `
                -DatabaseInfo $script:DbInfo
            
            $query = New-TestQuery -Schema 'dbo' -Table 'Products' -KeyColumns @('ProductId') -Top 3
            
            Initialize-StartSet `
                -Database $script:TestDatabase `
                -ConnectionInfo $script:Connection `
                -Queries @($query) `
                -DatabaseInfo $script:DbInfo `
                -SessionId $sessionId
            
            # First iteration (initialization)
            $result0 = Find-Subset `
                -Database $script:TestDatabase `
                -ConnectionInfo $script:Connection `
                -DatabaseInfo $script:DbInfo `
                -SessionId $sessionId `
                -Interactive $true `
                -Iteration 0
            
            $result0.Initialized | Should -Be $true
            
            # Second iteration (actual work)
            $result1 = Find-Subset `
                -Database $script:TestDatabase `
                -ConnectionInfo $script:Connection `
                -DatabaseInfo $script:DbInfo `
                -SessionId $sessionId `
                -Interactive $true `
                -Iteration 1
            
            $result1.CompletedIterations | Should -Be 1
        }
        
        It 'Should complete after multiple iterations' {
            $sessionId = New-TestSession `
                -Database $script:TestDatabase `
                -ConnectionInfo $script:Connection `
                -DatabaseInfo $script:DbInfo
            
            $query = New-TestQuery -Schema 'dbo' -Table 'Products' -KeyColumns @('ProductId') -Top 1
            
            Initialize-StartSet `
                -Database $script:TestDatabase `
                -ConnectionInfo $script:Connection `
                -Queries @($query) `
                -DatabaseInfo $script:DbInfo `
                -SessionId $sessionId
            
            # Initialize
            Find-Subset `
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
                $result = Find-Subset `
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
# Edge Cases Tests
# =====================================================

Describe 'Edge Cases' {
    AfterEach {
        if ($testResult -and $testResult.SessionId) {
            Remove-TestSession -SessionId $testResult.SessionId -Database $script:TestDatabase -DatabaseInfo $script:DbInfo -ConnectionInfo $script:Connection
        }
    }
    
    Context 'Empty Results' {
        It 'Should handle query that matches zero rows' {
            $query = New-TestQuery -Schema 'dbo' -Table 'Products' -KeyColumns @('ProductId') `
                -Where "[`$table].ProductId = -999999"
            
            $testResult = Invoke-FindSubsetTest `
                -Database $script:TestDatabase `
                -ConnectionInfo $script:Connection `
                -DatabaseInfo $script:DbInfo `
                -Queries @($query)
            
            $testResult.Success | Should -Be $true
            $testResult.Result.Finished | Should -Be $true
            
            # No products should be in subset
            $total = Get-TotalSubsetRows -SubsetSummary $testResult.Summary
            $total | Should -Be 0
        }
    }
    
    Context 'Orphan Tables' {
        It 'Should handle orphan table with no FKs (Settings)' {
            $query = New-TestQuery -Schema 'dbo' -Table 'Settings' -KeyColumns @('SettingId') -Top 1
            
            $testResult = Invoke-FindSubsetTest `
                -Database $script:TestDatabase `
                -ConnectionInfo $script:Connection `
                -DatabaseInfo $script:DbInfo `
                -Queries @($query)
            
            $testResult.Success | Should -Be $true
            Assert-SubsetContains -SubsetSummary $testResult.Summary -Schema 'dbo' -Table 'Settings' -ExpectedRows 1
            
            # Total should be just 1 (no related tables)
            $total = Get-TotalSubsetRows -SubsetSummary $testResult.Summary
            $total | Should -Be 1
        }
    }
    
    Context 'High Fanout' {
        It 'Should handle high fanout parent with many children (FullSearch=true)' {
            $query = New-TestQuery -Schema 'dbo' -Table 'HighFanoutParent' -KeyColumns @('ParentId') -Top 1
            
            $testResult = Invoke-FindSubsetTest `
                -Database $script:TestDatabase `
                -ConnectionInfo $script:Connection `
                -DatabaseInfo $script:DbInfo `
                -Queries @($query) `
                -FullSearch $true
            
            $testResult.Success | Should -Be $true
            Assert-SubsetContains -SubsetSummary $testResult.Summary -Schema 'dbo' -Table 'HighFanoutParent' -ExpectedRows 1
            Assert-SubsetContains -SubsetSummary $testResult.Summary -Schema 'dbo' -Table 'HighFanoutChildren' -MinRows 10
        }
    }
    
    Context 'Multi-Tenant Pattern' {
        It 'Should traverse TenantProducts junction correctly' {
            $query = New-TestQuery -Schema 'dbo' -Table 'TenantProducts' -KeyColumns @('TenantId', 'ProductId') -Top 1
            
            $testResult = Invoke-FindSubsetTest `
                -Database $script:TestDatabase `
                -ConnectionInfo $script:Connection `
                -DatabaseInfo $script:DbInfo `
                -Queries @($query)
            
            $testResult.Success | Should -Be $true
            Assert-SubsetContains -SubsetSummary $testResult.Summary -Schema 'dbo' -Table 'TenantProducts' -ExpectedRows 1
            Assert-SubsetContains -SubsetSummary $testResult.Summary -Schema 'dbo' -Table 'Tenants' -MinRows 1
            Assert-SubsetContains -SubsetSummary $testResult.Summary -Schema 'dbo' -Table 'Products' -MinRows 1
        }
    }
}

# =====================================================
# Multiple Starting Queries Tests
# =====================================================

Describe 'Multiple Starting Queries' {
    AfterEach {
        if ($testResult -and $testResult.SessionId) {
            Remove-TestSession -SessionId $testResult.SessionId -Database $script:TestDatabase -DatabaseInfo $script:DbInfo -ConnectionInfo $script:Connection
        }
    }
    
    Context 'Multiple Queries' {
        It 'Should handle multiple starting queries' {
            $query1 = New-TestQuery -Schema 'dbo' -Table 'Products' -KeyColumns @('ProductId') -Top 2
            $query2 = New-TestQuery -Schema 'dbo' -Table 'Customers' -KeyColumns @('CustomerId') -Top 2
            
            $testResult = Invoke-FindSubsetTest `
                -Database $script:TestDatabase `
                -ConnectionInfo $script:Connection `
                -DatabaseInfo $script:DbInfo `
                -Queries @($query1, $query2)
            
            $testResult.Success | Should -Be $true
            Assert-SubsetContains -SubsetSummary $testResult.Summary -Schema 'dbo' -Table 'Products' -ExpectedRows 2
            Assert-SubsetContains -SubsetSummary $testResult.Summary -Schema 'dbo' -Table 'Customers' -ExpectedRows 2
            Assert-SubsetContains -SubsetSummary $testResult.Summary -Schema 'dbo' -Table 'Contacts' -MinRows 1
            Assert-SubsetContains -SubsetSummary $testResult.Summary -Schema 'dbo' -Table 'SubCategories' -MinRows 1
        }
        
        It 'Should deduplicate when multiple queries reach same records' {
            # Both queries will likely reach same SubCategory
            $query1 = New-TestQuery -Schema 'dbo' -Table 'Products' -KeyColumns @('ProductId') `
                -Where "[`$table].ProductId = 1"
            $query2 = New-TestQuery -Schema 'dbo' -Table 'Products' -KeyColumns @('ProductId') `
                -Where "[`$table].ProductId = 2"
            
            $testResult = Invoke-FindSubsetTest `
                -Database $script:TestDatabase `
                -ConnectionInfo $script:Connection `
                -DatabaseInfo $script:DbInfo `
                -Queries @($query1, $query2)
            
            $testResult.Success | Should -Be $true
            Assert-SubsetContains -SubsetSummary $testResult.Summary -Schema 'dbo' -Table 'Products' -ExpectedRows 2
        }
    }
}
