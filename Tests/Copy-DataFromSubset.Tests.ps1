BeforeDiscovery {
    $modulePath = Split-Path -Parent $PSScriptRoot
    Import-Module "$modulePath\SqlSizer-MSSQL\SqlSizer-MSSQL" -Force -Global -ErrorAction Stop
}

Describe 'Copy-DataFromSubset source' {
    It 'Does not request converted table selects' {
        $modulePath = Split-Path -Parent $PSScriptRoot
        $script = Get-Content -LiteralPath "$modulePath\SqlSizer-MSSQL\Public\Copy-DataFromSubset.ps1" -Raw

        $script | Should -Not -Match '-Conversion\s+\$true'
    }
}

Describe 'Copy-DataFromSubset SQL generation' {
    InModuleScope SqlSizer-MSSQL {
        BeforeAll {
            function New-TestColumn {
                param(
                    [string]$Name,
                    [string]$DataType = 'int',
                    [switch]$Computed,
                    [switch]$Generated
                )

                $column = New-Object -TypeName ColumnInfo
                $column.Name = $Name
                $column.DataType = $DataType
                $column.Length = '50'
                $column.IsComputed = [bool]$Computed
                $column.IsGenerated = [bool]$Generated

                return $column
            }

            function New-IgnoredTable {
                $ignored = New-Object -TypeName TableInfo2
                $ignored.SchemaName = 'ref'
                $ignored.TableName = 'Ignored'

                return $ignored
            }

            function New-CopySubsetTestTable {
                param(
                    [switch]$Identity
                )

                $table = New-Object -TypeName TableInfo
                $table.SchemaName = 'dbo'
                $table.TableName = 'Orders'
                $table.IsIdentity = [bool]$Identity
                $table.Columns = New-Object 'System.Collections.Generic.List[ColumnInfo]'
                $table.PrimaryKey = New-Object 'System.Collections.Generic.List[ColumnInfo]'
                $table.ForeignKeys = New-Object 'System.Collections.Generic.List[TableFk]'

                $id = New-TestColumn -Name 'Id'
                $tenantId = New-TestColumn -Name 'TenantId'
                $xmlPayload = New-TestColumn -Name 'XmlPayload' -DataType 'xml'
                $geoPoint = New-TestColumn -Name 'GeoPoint' -DataType 'geography'
                $hierarchyNode = New-TestColumn -Name 'HierarchyNode' -DataType 'hierarchyid'
                $imageData = New-TestColumn -Name 'ImageData' -DataType 'image'
                $refId = New-TestColumn -Name 'RefId'
                $computedTotal = New-TestColumn -Name 'ComputedTotal' -Computed
                $generatedValue = New-TestColumn -Name 'GeneratedValue' -Generated
                $rowVersion = New-TestColumn -Name 'RowVersion' -DataType 'timestamp'

                @(
                    $id,
                    $tenantId,
                    $xmlPayload,
                    $geoPoint,
                    $hierarchyNode,
                    $imageData,
                    $refId,
                    $computedTotal,
                    $generatedValue,
                    $rowVersion
                ) | ForEach-Object { $table.Columns.Add($_) | Out-Null }

                $table.PrimaryKey.Add($id) | Out-Null
                $table.PrimaryKey.Add($tenantId) | Out-Null

                $fk = New-Object -TypeName TableFk
                $fk.Schema = 'ref'
                $fk.Table = 'Ignored'
                $fk.FkColumns = New-Object 'System.Collections.Generic.List[ColumnInfo]'
                $fk.FkColumns.Add($refId) | Out-Null
                $table.ForeignKeys.Add($fk) | Out-Null

                return $table
            }
        }

        It 'Selects raw source columns without conversion or generated columns' {
            $table = New-CopySubsetTestTable

            $sql = New-CopyDataFromSubsetQuery `
                -SessionId 'S1' `
                -Source 'SourceDb' `
                -TableInfo $table `
                -ProcessingTableName 'dbo_Orders'

            $sql | Should -Not -Match 'CONVERT\('
            $sql | Should -Not -Match 'Result_'
            $sql | Should -Match 'SELECT src\.\[Id\], src\.\[TenantId\], src\.\[XmlPayload\], src\.\[GeoPoint\], src\.\[HierarchyNode\], src\.\[ImageData\], src\.\[RefId\] FROM'
            $sql | Should -Not -Match 'ComputedTotal|GeneratedValue|RowVersion'
        }

        It 'Deduplicates only processing keys' {
            $table = New-CopySubsetTestTable

            $sql = New-CopyDataFromSubsetQuery `
                -SessionId 'S1' `
                -Source 'SourceDb' `
                -TableInfo $table `
                -ProcessingTableName 'dbo_Orders'

            ([regex]::Matches($sql, 'SELECT DISTINCT')).Count | Should -Be 1
            $sql | Should -Match '\(SELECT DISTINCT \[Key0\], \[Key1\] FROM \[SourceDb\]\.\[SqlSizer_S1\]\.\[dbo_Orders\] WHERE \[State\] IN \(1, 4, 5\)\)'
            $sql | Should -Not -Match 'SELECT DISTINCT src\.'
        }

        It 'Keeps ignored FK columns in the insert list and selects NULL for them' {
            $table = New-CopySubsetTestTable

            $sql = New-CopyDataFromSubsetQuery `
                -SessionId 'S1' `
                -Source 'SourceDb' `
                -TableInfo $table `
                -ProcessingTableName 'dbo_Orders' `
                -IgnoredTables @(New-IgnoredTable)

            $sql | Should -Match 'INSERT INTO \[dbo\]\.\[Orders\] \(\[Id\], \[TenantId\], \[XmlPayload\], \[GeoPoint\], \[HierarchyNode\], \[ImageData\], \[RefId\]\)'
            $sql | Should -Match 'SELECT src\.\[Id\], src\.\[TenantId\], src\.\[XmlPayload\], src\.\[GeoPoint\], src\.\[HierarchyNode\], src\.\[ImageData\], NULL FROM'
        }

        It 'Wraps identity inserts around the generated insert statement' {
            $table = New-CopySubsetTestTable -Identity

            $sql = New-CopyDataFromSubsetQuery `
                -SessionId 'S1' `
                -Source 'SourceDb' `
                -TableInfo $table `
                -ProcessingTableName 'dbo_Orders'
            $sql = Add-CopyDataFromSubsetIdentityInsert -Sql $sql -TableInfo $table

            $sql | Should -Match '^SET IDENTITY_INSERT \[dbo\]\.\[Orders\] ON; INSERT INTO'
            $sql | Should -Match '; SET IDENTITY_INSERT \[dbo\]\.\[Orders\] OFF$'
        }
    }
}
