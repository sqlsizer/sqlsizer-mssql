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
            $sql | Should -Match 'SELECT src\.\[Id\], src\.\[TenantId\], src\.\[XmlPayload\], src\.\[GeoPoint\], src\.\[HierarchyNode\], src\.\[ImageData\], src\.\[RefId\]\s+FROM'
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
            $sql | Should -Match 'DistinctSubsetKeys AS'
            $sql | Should -Match 'SELECT DISTINCT \[Key0\], \[Key1\]'
            $sql | Should -Match 'FROM \[SourceDb\]\.\[SqlSizer_S1\]\.\[dbo_Orders\]'
            $sql | Should -Not -Match 'SELECT DISTINCT src\.'
        }

        It 'Builds deterministic batched copy progress SQL' {
            $table = New-CopySubsetTestTable

            $sql = New-CopyDataFromSubsetQuery `
                -SessionId 'S1' `
                -Source 'SourceDb' `
                -TableInfo $table `
                -ProcessingTableName 'dbo_Orders' `
                -BatchSize 25 `
                -Resume $true

            $sql | Should -Match 'DECLARE @BatchSize bigint = 25'
            $sql | Should -Match 'DECLARE @Resume bit = 1'
            $sql | Should -Match 'ROW_NUMBER\(\) OVER \(ORDER BY \[Key0\] ASC, \[Key1\] ASC\)'
            $sql | Should -Match 'MERGE SqlSizer\.CopyProgress'
            $sql | Should -Match 'WHILE @CopiedRows < @TotalRows'
            $sql | Should -Match 'SqlSizer_CopyRowNumber BETWEEN @BatchStart AND @BatchEnd'
            $sql | Should -Match 'LastKeyJson = @LastKeyJson'
            $sql | Should -Match 'NOT EXISTS'
            $sql | Should -Match 'existing\.\[Id\] = src\.\[Id\]'
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
            $sql | Should -Match 'SELECT src\.\[Id\], src\.\[TenantId\], src\.\[XmlPayload\], src\.\[GeoPoint\], src\.\[HierarchyNode\], src\.\[ImageData\], NULL\s+FROM'
        }

        It 'Wraps identity inserts around the generated insert statement' {
            $table = New-CopySubsetTestTable -Identity

            $sql = New-CopyDataFromSubsetQuery `
                -SessionId 'S1' `
                -Source 'SourceDb' `
                -TableInfo $table `
                -ProcessingTableName 'dbo_Orders'
            $sql = Add-CopyDataFromSubsetIdentityInsert -Sql $sql -TableInfo $table

            $sql | Should -Match '^SET IDENTITY_INSERT \[dbo\]\.\[Orders\] ON; DECLARE @BatchSize'
            $sql | Should -Match '; SET IDENTITY_INSERT \[dbo\]\.\[Orders\] OFF$'
        }

        It 'Orders tables by foreign key dependencies when constraints stay enabled' {
            $id = New-TestColumn -Name 'Id'
            $parent = New-Object -TypeName TableInfo
            $parent.SchemaName = 'dbo'
            $parent.TableName = 'Parent'
            $parent.PrimaryKey = New-Object 'System.Collections.Generic.List[ColumnInfo]'
            $parent.ForeignKeys = New-Object 'System.Collections.Generic.List[TableFk]'
            $parent.PrimaryKey.Add($id) | Out-Null

            $child = New-Object -TypeName TableInfo
            $child.SchemaName = 'dbo'
            $child.TableName = 'Child'
            $child.PrimaryKey = New-Object 'System.Collections.Generic.List[ColumnInfo]'
            $child.ForeignKeys = New-Object 'System.Collections.Generic.List[TableFk]'
            $child.PrimaryKey.Add($id) | Out-Null

            $fk = New-Object -TypeName TableFk
            $fk.Schema = 'dbo'
            $fk.Table = 'Parent'
            $child.ForeignKeys.Add($fk) | Out-Null

            $databaseInfo = New-Object -TypeName DatabaseInfo
            $databaseInfo.Tables = New-Object 'System.Collections.Generic.List[TableInfo]'
            $databaseInfo.Tables.Add($child) | Out-Null
            $databaseInfo.Tables.Add($parent) | Out-Null

            $subsetTables = @(
                [pscustomobject]@{ SchemaName = 'dbo'; TableName = 'Child' },
                [pscustomobject]@{ SchemaName = 'dbo'; TableName = 'Parent' }
            )

            $ordered = @(Get-CopyDataFromSubsetForeignKeySafeOrder -SubsetTables $subsetTables -DatabaseInfo $databaseInfo)

            $ordered[0].TableName | Should -Be 'Parent'
            $ordered[1].TableName | Should -Be 'Child'
        }
    }
}
