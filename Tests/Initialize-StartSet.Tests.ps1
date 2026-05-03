$modulePath = Split-Path -Parent $PSScriptRoot
Import-Module "$modulePath\SqlSizer-MSSQL\SqlSizer-MSSQL" -Force -Global -ErrorAction Stop

Describe 'Initialize-StartSet seed query optimization' {
    InModuleScope SqlSizer-MSSQL {
        BeforeAll {
            function New-StartSetTestColumn {
            param(
                [Parameter(Mandatory = $true)]
                [string]$Name,

                [Parameter(Mandatory = $false)]
                [string]$DataType = 'int'
            )

            $column = New-Object ColumnInfo
            $column.Name = $Name
            $column.DataType = $DataType
            $column.Length = '4'
            $column.IsPresent = $true

            return $column
            }

            function New-StartSetTestTable {
            $table = New-Object TableInfo
            $table.SchemaName = 'dbo'
            $table.TableName = 'Orders'
            $table.PrimaryKey = New-Object 'System.Collections.Generic.List[ColumnInfo]'
            $table.Columns = New-Object 'System.Collections.Generic.List[ColumnInfo]'
            $table.Indexes = New-Object 'System.Collections.Generic.List[TableIndex]'

            $tenantId = New-StartSetTestColumn -Name 'TenantId'
            $orderId = New-StartSetTestColumn -Name 'OrderId'
            $name = New-StartSetTestColumn -Name 'Name' -DataType 'nvarchar'
            $createdAt = New-StartSetTestColumn -Name 'CreatedAt' -DataType 'datetime'

            @($tenantId, $orderId) | ForEach-Object { $table.PrimaryKey.Add($_) | Out-Null }
            @($tenantId, $orderId, $name, $createdAt) | ForEach-Object { $table.Columns.Add($_) | Out-Null }

            $index = New-Object TableIndex
            $index.Name = 'IX_Orders_CreatedAt'
            $index.Columns = New-Object 'System.Collections.Generic.List[string]'
            $index.Columns.Add('CreatedAt') | Out-Null
            $table.Indexes.Add($index) | Out-Null

            return $table
            }

            function New-StartSetTestQuery {
            param(
                [Parameter(Mandatory = $false)]
                [string[]]$KeyColumns = @('TenantId', 'OrderId'),

                [Parameter(Mandatory = $false)]
                [int]$Top = 0,

                [Parameter(Mandatory = $false)]
                [string]$Where = $null,

                [Parameter(Mandatory = $false)]
                [string]$OrderBy = $null
            )

            $query = New-Object SqlSizerQuery
            $query.State = [TraversalState]::Include
            $query.Schema = 'dbo'
            $query.Table = 'Orders'
            $query.KeyColumns = $KeyColumns
            $query.Top = $Top
            $query.Where = $Where
            $query.OrderBy = $OrderBy

            return $query
            }

            function New-StartSetSqlUnderTest {
            param(
                [Parameter(Mandatory = $true)]
                [SqlSizerQuery]$Query,

                [Parameter(Mandatory = $false)]
                [TableInfo]$Table = (New-StartSetTestTable)
            )

            New-StartSetInsertSql `
                -Query $Query `
                -Table $Table `
                -ProcessingTable 'SqlSizer_S1.dbo_Orders' `
                -StartIteration 0
            }

            function Invoke-AndCaptureExceptionMessage {
            param(
                [Parameter(Mandatory = $true)]
                [scriptblock]$ScriptBlock
            )

            try
            {
                & $ScriptBlock
            }
            catch
            {
                return $_.Exception.Message
            }

            return $null
            }
        }

        It 'adds primary key ORDER BY when Top is set without OrderBy' {
            $query = New-StartSetTestQuery -Top 5

            $sql = New-StartSetSqlUnderTest -Query $query

            $sql | Should -Match 'SELECT\s+TOP 5\s+\[\$table\]\.\[TenantId\], \[\$table\]\.\[OrderId\], 1 as \[State\]'
            $sql | Should -Match 'ORDER BY \[\$table\]\.\[TenantId\] ASC, \[\$table\]\.\[OrderId\] ASC$'
        }

        It 'emits composite keys in metadata primary key order' {
            $query = New-StartSetTestQuery -KeyColumns @('OrderId', 'TenantId') -Top 1

            $sql = New-StartSetSqlUnderTest -Query $query

            $sql | Should -Match 'SELECT\s+TOP 1\s+\[\$table\]\.\[TenantId\], \[\$table\]\.\[OrderId\], 1 as \[State\]'
        }

        It 'keeps explicit OrderBy and appends missing primary key tie breakers' {
            $query = New-StartSetTestQuery -Top 10 -OrderBy '[$table].[CreatedAt] DESC'

            $sql = New-StartSetSqlUnderTest -Query $query

            $sql | Should -Match 'ORDER BY \[\$table\]\.\[CreatedAt\] DESC, \[\$table\]\.\[TenantId\] ASC, \[\$table\]\.\[OrderId\] ASC$'
        }

        It 'does not duplicate primary key columns already present in explicit OrderBy' {
            $query = New-StartSetTestQuery -Top 10 -OrderBy '[$table].[TenantId] DESC'

            $sql = New-StartSetSqlUnderTest -Query $query

            $sql | Should -Match 'ORDER BY \[\$table\]\.\[TenantId\] DESC, \[\$table\]\.\[OrderId\] ASC$'
            $sql | Should -Not -Match 'TenantId\] DESC, \[\$table\]\.\[TenantId\] ASC'
        }

        It 'throws when KeyColumns are missing primary key columns' {
            $query = New-StartSetTestQuery -KeyColumns @('TenantId')

            $message = Invoke-AndCaptureExceptionMessage -ScriptBlock { New-StartSetSqlUnderTest -Query $query }

            $message | Should -Match 'must exactly match primary key columns'
        }

        It 'throws when KeyColumns include extra columns' {
            $query = New-StartSetTestQuery -KeyColumns @('TenantId', 'OrderId', 'Name')

            $message = Invoke-AndCaptureExceptionMessage -ScriptBlock { New-StartSetSqlUnderTest -Query $query }

            $message | Should -Match 'must exactly match primary key columns'
        }

        It 'throws when KeyColumns include non-primary-key columns' {
            $query = New-StartSetTestQuery -KeyColumns @('TenantId', 'Name')

            $message = Invoke-AndCaptureExceptionMessage -ScriptBlock { New-StartSetSqlUnderTest -Query $query }

            $message | Should -Match 'must exactly match primary key columns'
        }

        It 'throws when Top is negative' {
            $query = New-StartSetTestQuery -Top -1

            $message = Invoke-AndCaptureExceptionMessage -ScriptBlock { New-StartSetSqlUnderTest -Query $query }

            $message | Should -Match 'Top must be greater than or equal to 0'
        }

        It 'keeps rejecting dangerous Where clauses' {
            $query = New-StartSetTestQuery -Where '[$table].Name = ''A''; DROP TABLE dbo.Orders'

            $message = Invoke-AndCaptureExceptionMessage -ScriptBlock { New-StartSetSqlUnderTest -Query $query }

            $message | Should -Match 'Where clause contains potentially dangerous SQL'
        }

        It 'keeps rejecting dangerous OrderBy clauses' {
            $query = New-StartSetTestQuery -OrderBy 'Name; DROP TABLE dbo.Orders'

            $message = Invoke-AndCaptureExceptionMessage -ScriptBlock { New-StartSetSqlUnderTest -Query $query }

            $message | Should -Match 'OrderBy clause contains potentially dangerous SQL'
        }

        It 'warns when Where does not reference a known primary key or indexed column' {
            $query = New-StartSetTestQuery -Where '[$table].[Name] = ''A'''

            $output = & { New-StartSetSqlUnderTest -Query $query } 3>&1
            $warnings = @($output | Where-Object { $_ -is [System.Management.Automation.WarningRecord] })

            $warnings.Count | Should -Be 1
            [string]$warnings[0] | Should -Match 'does not appear to reference a primary key or indexed column'
        }
    }
}
