BeforeDiscovery {
    $modulePath = Split-Path -Parent $PSScriptRoot
    Import-Module "$modulePath\SqlSizer-MSSQL\SqlSizer-MSSQL" -Force -Global -ErrorAction Stop
}

Describe 'Initialize-OperationsTable batching' {
    InModuleScope SqlSizer-MSSQL {
        BeforeAll {
            function New-InitOpsTestTable {
                param(
                    [Parameter(Mandatory = $true)][string]$Schema,
                    [Parameter(Mandatory = $true)][string]$TableName,
                    [Parameter(Mandatory = $false)][bool]$WithPrimaryKey = $true
                )

                $table = New-Object TableInfo
                $table.SchemaName = $Schema
                $table.TableName = $TableName
                $table.PrimaryKey = New-Object 'System.Collections.Generic.List[ColumnInfo]'
                $table.Columns = New-Object 'System.Collections.Generic.List[ColumnInfo]'
                $table.Indexes = New-Object 'System.Collections.Generic.List[TableIndex]'
                $table.ForeignKeys = New-Object 'System.Collections.Generic.List[TableFk]'

                $idCol = New-Object ColumnInfo
                $idCol.Name = 'Id'
                $idCol.DataType = 'int'
                $idCol.Length = '4'
                $idCol.IsPresent = $true
                $table.Columns.Add($idCol) | Out-Null

                if ($WithPrimaryKey)
                {
                    $table.PrimaryKey.Add($idCol) | Out-Null
                }

                return $table
            }

            function New-InitOpsTestDatabaseInfo {
                param(
                    [Parameter(Mandatory = $true)][TableInfo[]]$Tables
                )

                $info = New-Object DatabaseInfo
                $info.Tables = New-Object 'System.Collections.Generic.List[TableInfo]'
                foreach ($t in $Tables)
                {
                    $info.Tables.Add($t) | Out-Null
                }
                $info.Views = New-Object 'System.Collections.Generic.List[ViewInfo]'
                return $info
            }

            function New-InitOpsConnection {
                $conn = New-Object SqlConnectionInfo
                $conn.Server = 'mock'
                $conn.EncryptConnection = $false
                $conn.Statistics = New-Object SqlConnectionStatistics
                return $conn
            }

            function New-InitOpsSqlSizerInfo {
                param(
                    [Parameter(Mandatory = $true)][TableInfo[]]$Tables
                )

                $tableRows = @()
                $id = 1
                foreach ($t in $Tables)
                {
                    $tableRows += [pscustomobject]@{
                        Id         = $id
                        SchemaName = $t.SchemaName
                        TableName  = $t.TableName
                    }
                    $id++
                }
                return [pscustomobject]@{
                    Tables      = $tableRows
                    ForeignKeys = @()
                }
            }
        }

        It 'Issues a single Invoke-SqlcmdEx call regardless of table count' {
            $tables = @(
                (New-InitOpsTestTable -Schema 'dbo' -TableName 'Orders'),
                (New-InitOpsTestTable -Schema 'dbo' -TableName 'Customers'),
                (New-InitOpsTestTable -Schema 'sales' -TableName 'Invoices')
            )
            $info = New-InitOpsTestDatabaseInfo -Tables $tables

            Mock Get-SqlSizerInfo { New-InitOpsSqlSizerInfo -Tables $tables }
            Mock Invoke-SqlcmdEx { return $null }

            Initialize-OperationsTable `
                -SessionId 'TEST-1' `
                -Database 'TestDb' `
                -DatabaseInfo $info `
                -ConnectionInfo (New-InitOpsConnection) `
                -Statistics $false

            Should -Invoke -CommandName Invoke-SqlcmdEx -Times 1 -Exactly
        }

        It 'Includes one INSERT per qualifying user table in the batched SQL' {
            $tables = @(
                (New-InitOpsTestTable -Schema 'dbo' -TableName 'A'),
                (New-InitOpsTestTable -Schema 'dbo' -TableName 'B'),
                (New-InitOpsTestTable -Schema 'dbo' -TableName 'C')
            )
            $info = New-InitOpsTestDatabaseInfo -Tables $tables

            Mock Get-SqlSizerInfo { New-InitOpsSqlSizerInfo -Tables $tables }
            $script:capturedSql = $null
            Mock Invoke-SqlcmdEx { $script:capturedSql = $Sql; return $null }

            Initialize-OperationsTable `
                -SessionId 'TEST-2' `
                -Database 'TestDb' `
                -DatabaseInfo $info `
                -ConnectionInfo (New-InitOpsConnection) `
                -Statistics $false

            $script:capturedSql | Should -Not -BeNullOrEmpty
            ([regex]::Matches($script:capturedSql, 'INSERT INTO SqlSizer\.Operations')).Count | Should -Be 3
        }

        It 'Skips tables without a primary key' {
            $tables = @(
                (New-InitOpsTestTable -Schema 'dbo' -TableName 'WithPk' -WithPrimaryKey $true),
                (New-InitOpsTestTable -Schema 'dbo' -TableName 'NoPk' -WithPrimaryKey $false)
            )
            $info = New-InitOpsTestDatabaseInfo -Tables $tables

            Mock Get-SqlSizerInfo { New-InitOpsSqlSizerInfo -Tables $tables }
            $script:capturedSql = $null
            Mock Invoke-SqlcmdEx { $script:capturedSql = $Sql; return $null }

            Initialize-OperationsTable `
                -SessionId 'TEST-3' `
                -Database 'TestDb' `
                -DatabaseInfo $info `
                -ConnectionInfo (New-InitOpsConnection) `
                -Statistics $false

            $script:capturedSql | Should -Match 'dbo_WithPk'
            $script:capturedSql | Should -Not -Match 'dbo_NoPk'
        }

        It 'Skips SqlSizer-internal schemas' {
            $userTable = New-InitOpsTestTable -Schema 'dbo' -TableName 'Real'
            $sysTable = New-InitOpsTestTable -Schema 'SqlSizer' -TableName 'Tables'
            $sysHist = New-InitOpsTestTable -Schema 'SqlSizerHistory' -TableName 'Hist'
            $tables = @($userTable, $sysTable, $sysHist)
            $info = New-InitOpsTestDatabaseInfo -Tables $tables

            Mock Get-SqlSizerInfo { New-InitOpsSqlSizerInfo -Tables $tables }
            $script:capturedSql = $null
            Mock Invoke-SqlcmdEx { $script:capturedSql = $Sql; return $null }

            Initialize-OperationsTable `
                -SessionId 'TEST-4' `
                -Database 'TestDb' `
                -DatabaseInfo $info `
                -ConnectionInfo (New-InitOpsConnection) `
                -Statistics $false

            ([regex]::Matches($script:capturedSql, 'INSERT INTO SqlSizer\.Operations')).Count | Should -Be 1
            $script:capturedSql | Should -Match 'dbo_Real'
            $script:capturedSql | Should -Not -Match 'SqlSizer_Tables'
            $script:capturedSql | Should -Not -Match 'SqlSizerHistory_Hist'
        }

        It 'Does not invoke Invoke-SqlcmdEx when no tables qualify' {
            $tables = @(
                (New-InitOpsTestTable -Schema 'dbo' -TableName 'NoPk1' -WithPrimaryKey $false),
                (New-InitOpsTestTable -Schema 'dbo' -TableName 'NoPk2' -WithPrimaryKey $false)
            )
            $info = New-InitOpsTestDatabaseInfo -Tables $tables

            Mock Get-SqlSizerInfo { New-InitOpsSqlSizerInfo -Tables $tables }
            Mock Invoke-SqlcmdEx { return $null }

            Initialize-OperationsTable `
                -SessionId 'TEST-5' `
                -Database 'TestDb' `
                -DatabaseInfo $info `
                -ConnectionInfo (New-InitOpsConnection) `
                -Statistics $false

            Should -Invoke -CommandName Invoke-SqlcmdEx -Times 0 -Exactly
        }

        It 'Forwards SessionId and StartIteration into every INSERT' {
            $tables = @(
                (New-InitOpsTestTable -Schema 'dbo' -TableName 'X'),
                (New-InitOpsTestTable -Schema 'dbo' -TableName 'Y')
            )
            $info = New-InitOpsTestDatabaseInfo -Tables $tables

            Mock Get-SqlSizerInfo { New-InitOpsSqlSizerInfo -Tables $tables }
            $script:capturedSql = $null
            Mock Invoke-SqlcmdEx { $script:capturedSql = $Sql; return $null }

            Initialize-OperationsTable `
                -SessionId 'SESSION-99' `
                -StartIteration 7 `
                -Database 'TestDb' `
                -DatabaseInfo $info `
                -ConnectionInfo (New-InitOpsConnection) `
                -Statistics $false

            ([regex]::Matches($script:capturedSql, "'SESSION-99'")).Count | Should -Be 2
            ([regex]::Matches($script:capturedSql, 'Iteration >= 7')).Count | Should -Be 2
        }

        It 'Separates INSERTs with semicolons so the batch is valid T-SQL' {
            $tables = @(
                (New-InitOpsTestTable -Schema 'dbo' -TableName 'A'),
                (New-InitOpsTestTable -Schema 'dbo' -TableName 'B')
            )
            $info = New-InitOpsTestDatabaseInfo -Tables $tables

            Mock Get-SqlSizerInfo { New-InitOpsSqlSizerInfo -Tables $tables }
            $script:capturedSql = $null
            Mock Invoke-SqlcmdEx { $script:capturedSql = $Sql; return $null }

            Initialize-OperationsTable `
                -SessionId 'TEST-6' `
                -Database 'TestDb' `
                -DatabaseInfo $info `
                -ConnectionInfo (New-InitOpsConnection) `
                -Statistics $false

            # Each INSERT must end with a semicolon before the next INSERT begins
            ([regex]::Matches($script:capturedSql, ';\s*INSERT INTO SqlSizer\.Operations')).Count | Should -Be 1
        }
    }
}
