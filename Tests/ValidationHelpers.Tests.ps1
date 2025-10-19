<#
.SYNOPSIS
    Unit tests for ValidationHelpers module.
    
.DESCRIPTION
    Comprehensive tests for all validation functions to ensure
    proper error handling and validation logic.
#>

BeforeAll {
    $modulePath = Split-Path -Parent $PSScriptRoot
    Import-Module "$modulePath\SqlSizer-MSSQL\SqlSizer-MSSQL.psd1" -Force
}

Describe 'Assert-NotNull Tests' {
    It 'Returns value when not null' {
        $result = Assert-NotNull "test" "param"
        $result | Should -Be "test"
    }
    
    It 'Throws ArgumentNullException when null' {
        { Assert-NotNull $null "param" } | Should -Throw -ExceptionType ([System.ArgumentNullException])
    }
    
    It 'Includes parameter name in error' {
        try {
            Assert-NotNull $null "myParameter"
            throw "Should have thrown"
        }
        catch [System.ArgumentNullException] {
            $_.Exception.ParamName | Should -Be "myParameter"
        }
    }
    
    It 'Uses custom message when provided' {
        try {
            Assert-NotNull $null "param" "Custom error message"
            throw "Should have thrown"
        }
        catch [System.ArgumentNullException] {
            $_.Exception.Message | Should -Match "Custom error message"
        }
    }
}

Describe 'Assert-NotNullOrEmpty Tests' {
    It 'Returns value when not empty' {
        $result = Assert-NotNullOrEmpty "test" "param"
        $result | Should -Be "test"
    }
    
    It 'Throws when null' {
        { Assert-NotNullOrEmpty $null "param" } | Should -Throw
    }
    
    It 'Throws when empty string' {
        { Assert-NotNullOrEmpty "" "param" } | Should -Throw
    }
    
    It 'Throws when whitespace only' {
        { Assert-NotNullOrEmpty "   " "param" } | Should -Throw
    }
    
    It 'Includes parameter name in exception' {
        try {
            Assert-NotNullOrEmpty "" "testParam"
            throw "Should have thrown"
        }
        catch {
            $_.Exception.ParamName | Should -Be "testParam"
        }
    }
}

Describe 'Assert-GreaterThan Tests' {
    It 'Returns value when greater than minimum' {
        $result = Assert-GreaterThan 10 5 "param"
        $result | Should -Be 10
    }
    
    It 'Throws when equal to minimum' {
        { Assert-GreaterThan 5 5 "param" } | Should -Throw -ExceptionType ([System.ArgumentOutOfRangeException])
    }
    
    It 'Throws when less than minimum' {
        { Assert-GreaterThan 3 5 "param" } | Should -Throw -ExceptionType ([System.ArgumentOutOfRangeException])
    }
    
    It 'Includes actual value in error message' {
        try {
            Assert-GreaterThan 3 5 "param"
            throw "Should have thrown"
        }
        catch [System.ArgumentOutOfRangeException] {
            $_.Exception.Message | Should -Match "3"
            $_.Exception.Message | Should -Match "5"
        }
    }
}

Describe 'Assert-GreaterThanOrEqual Tests' {
    It 'Returns value when greater than minimum' {
        $result = Assert-GreaterThanOrEqual 10 5 "param"
        $result | Should -Be 10
    }
    
    It 'Returns value when equal to minimum' {
        $result = Assert-GreaterThanOrEqual 5 5 "param"
        $result | Should -Be 5
    }
    
    It 'Throws when less than minimum' {
        { Assert-GreaterThanOrEqual 3 5 "param" } | Should -Throw -ExceptionType ([System.ArgumentOutOfRangeException])
    }
}

Describe 'Assert-InRange Tests' {
    It 'Returns value when in range' {
        $result = Assert-InRange 5 1 10 "param"
        $result | Should -Be 5
    }
    
    It 'Returns value at minimum boundary' {
        $result = Assert-InRange 1 1 10 "param"
        $result | Should -Be 1
    }
    
    It 'Returns value at maximum boundary' {
        $result = Assert-InRange 10 1 10 "param"
        $result | Should -Be 10
    }
    
    It 'Throws when below minimum' {
        { Assert-InRange 0 1 10 "param" } | Should -Throw -ExceptionType ([System.ArgumentOutOfRangeException])
    }
    
    It 'Throws when above maximum' {
        { Assert-InRange 11 1 10 "param" } | Should -Throw -ExceptionType ([System.ArgumentOutOfRangeException])
    }
}

Describe 'Assert-ValidEnum Tests' {
    It 'Returns value when valid enum member' {
        $result = Assert-ValidEnum ([TraversalState]::Include) ([TraversalState]) "state"
        $result | Should -Be ([TraversalState]::Include)
    }
    
    It 'Throws when invalid enum value' {
        { Assert-ValidEnum 999 ([TraversalState]) "state" } | Should -Throw
    }
    
    It 'Lists valid enum values in error' {
        try {
            Assert-ValidEnum 999 ([TraversalState]) "state"
            throw "Should have thrown"
        }
        catch {
            $_.Exception.Message | Should -Match "Include"
            $_.Exception.Message | Should -Match "Exclude"
            $_.Exception.Message | Should -Match "Pending"
        }
    }
}

Describe 'Assert-ValidSessionId Tests' {
    It 'Returns valid session ID' {
        $result = Assert-ValidSessionId "TEST-SESSION-123"
        $result | Should -Be "TEST-SESSION-123"
    }
    
    It 'Throws when null' {
        { Assert-ValidSessionId $null } | Should -Throw
    }
    
    It 'Throws when empty' {
        { Assert-ValidSessionId "" } | Should -Throw
    }
    
    It 'Throws when contains semicolon' {
        { Assert-ValidSessionId "TEST;DROP TABLE" } | Should -Throw
    }
    
    It 'Throws when contains quote' {
        { Assert-ValidSessionId "TEST'SESSION" } | Should -Throw
    }
    
    It 'Throws when too long' {
        $longId = "A" * 101
        { Assert-ValidSessionId $longId } | Should -Throw
    }
    
    It 'Accepts 100 character session ID' {
        $longId = "A" * 100
        $result = Assert-ValidSessionId $longId
        $result | Should -Be $longId
    }
}

Describe 'Assert-ValidConnectionInfo Tests' {
    It 'Returns valid connection info' {
        $conn = New-Object SqlConnectionInfo
        $conn.Server = "localhost"
        
        $result = Assert-ValidConnectionInfo $conn
        $result.Server | Should -Be "localhost"
    }
    
    It 'Throws when connection info is null' {
        { Assert-ValidConnectionInfo $null } | Should -Throw
    }
    
    It 'Throws when server is null' {
        $conn = New-Object SqlConnectionInfo
        { Assert-ValidConnectionInfo $conn } | Should -Throw
    }
    
    It 'Throws when server is empty' {
        $conn = New-Object SqlConnectionInfo
        $conn.Server = ""
        { Assert-ValidConnectionInfo $conn } | Should -Throw
    }
    
    It 'Accepts connection with AccessToken' {
        $conn = New-Object SqlConnectionInfo
        $conn.Server = "myserver.database.windows.net"
        $conn.AccessToken = "fake-token"
        
        $result = Assert-ValidConnectionInfo $conn
        $result | Should -Not -BeNullOrEmpty
    }
}

Describe 'Get-ValidatedTableInfo Tests' {
    BeforeAll {
        # Mock DatabaseInfo with test tables
        $script:mockDatabaseInfo = New-Object DatabaseInfo
        $script:mockDatabaseInfo.Tables = New-Object "System.Collections.Generic.List[TableInfo]"
        
        $table1 = New-Object TableInfo
        $table1.SchemaName = "dbo"
        $table1.TableName = "Orders"
        $table1.PrimaryKey = New-Object "System.Collections.Generic.List[ColumnInfo]"
        $table1.PrimaryKey.Add([PSCustomObject]@{ Name = "OrderID" })
        
        $table2 = New-Object TableInfo
        $table2.SchemaName = "dbo"
        $table2.TableName = "NoPKTable"
        $table2.PrimaryKey = New-Object "System.Collections.Generic.List[ColumnInfo]"
        
        $script:mockDatabaseInfo.Tables.Add($table1)
        $script:mockDatabaseInfo.Tables.Add($table2)
    }
    
    It 'Returns table when found' {
        $result = Get-ValidatedTableInfo `
            -SchemaName "dbo" `
            -TableName "Orders" `
            -DatabaseInfo $script:mockDatabaseInfo
        
        $result.TableName | Should -Be "Orders"
    }
    
    It 'Throws when table not found and ThrowIfNotFound is true' {
        { 
            Get-ValidatedTableInfo `
                -SchemaName "dbo" `
                -TableName "NonExistent" `
                -DatabaseInfo $script:mockDatabaseInfo `
                -ThrowIfNotFound $true
        } | Should -Throw
    }
    
    It 'Returns null when table not found and ThrowIfNotFound is false' {
        $result = Get-ValidatedTableInfo `
            -SchemaName "dbo" `
            -TableName "NonExistent" `
            -DatabaseInfo $script:mockDatabaseInfo `
            -ThrowIfNotFound $false
        
        $result | Should -BeNullOrEmpty
    }
    
    It 'Throws when table has no primary key and RequirePrimaryKey is true' {
        { 
            Get-ValidatedTableInfo `
                -SchemaName "dbo" `
                -TableName "NoPKTable" `
                -DatabaseInfo $script:mockDatabaseInfo `
                -RequirePrimaryKey $true
        } | Should -Throw
    }
    
    It 'Returns table with no PK when RequirePrimaryKey is false' {
        $result = Get-ValidatedTableInfo `
            -SchemaName "dbo" `
            -TableName "NoPKTable" `
            -DatabaseInfo $script:mockDatabaseInfo `
            -RequirePrimaryKey $false
        
        $result.TableName | Should -Be "NoPKTable"
    }
    
    It 'Includes available tables in error message' {
        try {
            Get-ValidatedTableInfo `
                -SchemaName "dbo" `
                -TableName "NonExistent" `
                -DatabaseInfo $script:mockDatabaseInfo
            throw "Should have thrown"
        }
        catch {
            $_.Exception.Message | Should -Match "dbo\.Orders"
            $_.Exception.Message | Should -Match "dbo\.NoPKTable"
        }
    }
}

Describe 'Test-SqlInjectionRisk Tests' {
    It 'Returns false for safe string' {
        $result = Test-SqlInjectionRisk "SafeTableName"
        $result | Should -Be $false
    }
    
    It 'Returns true for statement terminator' {
        $result = Test-SqlInjectionRisk "'; DROP TABLE"
        $result | Should -Be $true
    }
    
    It 'Returns true for comment injection' {
        $result = Test-SqlInjectionRisk "'--"
        $result | Should -Be $true
    }
    
    It 'Returns true for OR injection' {
        $result = Test-SqlInjectionRisk "' OR 1=1"
        $result | Should -Be $true
    }
    
    It 'Returns true for AND injection' {
        $result = Test-SqlInjectionRisk "' AND 1=1"
        $result | Should -Be $true
    }
    
    It 'Returns true for EXEC command' {
        $result = Test-SqlInjectionRisk "EXEC ('malicious code')"
        $result | Should -Be $true
    }
    
    It 'Returns true for DROP TABLE' {
        $result = Test-SqlInjectionRisk "DROP TABLE Users"
        $result | Should -Be $true
    }
    
    It 'Returns true for DELETE FROM' {
        $result = Test-SqlInjectionRisk "DELETE FROM Users"
        $result | Should -Be $true
    }
    
    It 'Returns true for xp_ extended proc' {
        $result = Test-SqlInjectionRisk "xp_cmdshell"
        $result | Should -Be $true
    }
    
    It 'Throws when -Throw is specified and risk found' {
        { 
            Test-SqlInjectionRisk "'; DROP TABLE" -Throw
        } | Should -Throw -ExceptionType ([System.Security.SecurityException])
    }
    
    It 'Does not throw when -Throw is specified but no risk' {
        { 
            Test-SqlInjectionRisk "SafeString" -Throw
        } | Should -Not -Throw
    }
}

Describe 'Assert-ValidTraversalState Tests' {
    It 'Returns valid Include state' {
        $result = Assert-ValidTraversalState ([TraversalState]::Include)
        $result | Should -Be ([TraversalState]::Include)
    }
    
    It 'Returns valid Exclude state' {
        $result = Assert-ValidTraversalState ([TraversalState]::Exclude)
        $result | Should -Be ([TraversalState]::Exclude)
    }
    
    It 'Returns valid Pending state' {
        $result = Assert-ValidTraversalState ([TraversalState]::Pending)
        $result | Should -Be ([TraversalState]::Pending)
    }
    
    It 'Returns valid InboundOnly state' {
        $result = Assert-ValidTraversalState ([TraversalState]::InboundOnly)
        $result | Should -Be ([TraversalState]::InboundOnly)
    }
}

Describe 'Assert-ValidTraversalDirection Tests' {
    It 'Returns valid Outgoing direction' {
        $result = Assert-ValidTraversalDirection ([TraversalDirection]::Outgoing)
        $result | Should -Be ([TraversalDirection]::Outgoing)
    }
    
    It 'Returns valid Incoming direction' {
        $result = Assert-ValidTraversalDirection ([TraversalDirection]::Incoming)
        $result | Should -Be ([TraversalDirection]::Incoming)
    }
}

Describe 'New-ValidationError Tests' {
    It 'Creates error object with all properties' {
        $result = New-ValidationError `
            -ParameterName "testParam" `
            -ErrorMessage "Invalid value" `
            -ActualValue 5 `
            -ExpectedValue "10"
        
        $result.Parameter | Should -Be "testParam"
        $result.Error | Should -Be "Invalid value"
        $result.ActualValue | Should -Be 5
        $result.ExpectedValue | Should -Be "10"
        $result.Timestamp | Should -Not -BeNullOrEmpty
    }
    
    It 'Creates error object without optional values' {
        $result = New-ValidationError `
            -ParameterName "testParam" `
            -ErrorMessage "Invalid value"
        
        $result.Parameter | Should -Be "testParam"
        $result.Error | Should -Be "Invalid value"
    }
}

Describe 'Write-ValidationWarning Tests' {
    It 'Writes warning with parameter name' {
        $output = Write-ValidationWarning `
            -ParameterName "testParam" `
            -WarningMessage "This is a warning" `
            3>&1  # Capture warning stream
        
        $output | Should -Match "\[testParam\]"
        $output | Should -Match "This is a warning"
    }
}

Describe 'Test-TableHasPrimaryKey Tests' {
    It 'Returns true when table has primary key' {
        $table = New-Object TableInfo
        $table.PrimaryKey = New-Object "System.Collections.Generic.List[ColumnInfo]"
        $table.PrimaryKey.Add([PSCustomObject]@{ Name = "ID" })
        
        $result = Test-TableHasPrimaryKey $table
        $result | Should -Be $true
    }
    
    It 'Returns false when table has no primary key' {
        $table = New-Object TableInfo
        $table.PrimaryKey = New-Object "System.Collections.Generic.List[ColumnInfo]"
        
        $result = Test-TableHasPrimaryKey $table
        $result | Should -Be $false
    }
    
    It 'Throws when table is null' {
        { Test-TableHasPrimaryKey $null } | Should -Throw
    }
}
