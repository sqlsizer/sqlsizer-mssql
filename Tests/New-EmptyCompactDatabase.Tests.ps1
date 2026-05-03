BeforeDiscovery {
    $modulePath = Split-Path -Parent $PSScriptRoot
    Import-Module "$modulePath\SqlSizer-MSSQL\SqlSizer-MSSQL" -Force -Global -ErrorAction Stop
}

Describe 'New-EmptyCompactDatabase SQL helpers' {
    InModuleScope SqlSizer-MSSQL {
        It 'Builds sized nvarchar column types correctly' {
            $row = [pscustomobject]@{
                TypeName       = 'nvarchar'
                TypeSchemaName = 'sys'
                IsUserDefined  = $false
                MaxLength      = 100
                Precision      = 0
                Scale          = 0
            }

            Get-CompactDatabaseColumnTypeSql -ColumnRow $row | Should -Be 'nvarchar(50)'
        }

        It 'Builds typed XML column types with schema collections' {
            $row = [pscustomobject]@{
                TypeName                = 'xml'
                TypeSchemaName          = 'sys'
                IsUserDefined           = $false
                XmlCollectionId         = 42
                IsXmlDocument           = $true
                XmlCollectionSchemaName = 'xsd'
                XmlCollectionName       = 'OrderShape'
            }

            Get-CompactDatabaseColumnTypeSql -ColumnRow $row | Should -Be 'xml(DOCUMENT [xsd].[OrderShape])'
        }

        It 'Builds identity and default column definitions' {
            $row = [pscustomobject]@{
                ColumnName        = 'OrderId'
                TypeName          = 'int'
                TypeSchemaName    = 'sys'
                IsUserDefined     = $false
                MaxLength         = 4
                Precision         = 10
                Scale             = 0
                IsNullable        = $false
                IsIdentity        = $true
                IsComputed        = $false
                CollationName     = $null
                IsRowGuidColumn   = $false
                IsSparse          = $false
                IdentitySeed      = 10
                IdentityIncrement = 5
                DefaultName       = 'DF_Orders_OrderId'
                DefaultDefinition = '((10))'
            }

            $sql = Get-CompactDatabaseColumnDefinition -ColumnRow $row

            $sql | Should -Be '[OrderId] int IDENTITY(10,5) NOT NULL CONSTRAINT [DF_Orders_OrderId] DEFAULT ((10))'
        }

        It 'Builds persisted computed column definitions' {
            $row = [pscustomobject]@{
                ColumnName         = 'Total'
                IsComputed         = $true
                ComputedDefinition = '([Quantity]*[UnitPrice])'
                IsPersisted        = $true
            }

            Get-CompactDatabaseColumnDefinition -ColumnRow $row | Should -Be '[Total] AS ([Quantity]*[UnitPrice]) PERSISTED'
        }

        It 'Preserves foreign key update and delete rules' {
            $fk = New-Object -TypeName TableFk
            $fk.DeleteRule = [ForeignKeyRule]::Cascade
            $fk.UpdateRule = [ForeignKeyRule]::SetNull

            Get-CompactDatabaseForeignKeyRuleSql -ForeignKey $fk | Should -Be ' ON DELETE CASCADE ON UPDATE SET NULL'
        }

        It 'Requests full-length query results so XML schema collections are not truncated' {
            $script:invokeSqlcmdParameters = $null
            function Invoke-Sqlcmd {
                [cmdletbinding()]
                param(
                    [string]$Query,
                    [string]$ServerInstance,
                    [string]$Database,
                    [int]$QueryTimeout,
                    [string]$Encrypt,
                    [switch]$TrustServerCertificate,
                    [int]$MaxCharLength,
                    [int]$MaxBinaryLength
                )

                $script:invokeSqlcmdParameters = $PSBoundParameters
                return [pscustomobject]@{ Value = 'ok' }
            }

            try {
                $connection = New-Object SqlConnectionInfo
                $connection.Server = '.'
                $connection.EncryptConnection = $false

                $null = Invoke-SqlcmdEx `
                    -Sql 'SELECT 1 AS Value' `
                    -Database 'master' `
                    -ConnectionInfo $connection `
                    -Statistics $false

                $script:invokeSqlcmdParameters.MaxCharLength | Should -Be ([int]::MaxValue)
                $script:invokeSqlcmdParameters.MaxBinaryLength | Should -Be ([int]::MaxValue)
            }
            finally {
                Remove-Item -Path Function:\Invoke-Sqlcmd -ErrorAction SilentlyContinue
                Remove-Variable -Scope Script -Name invokeSqlcmdParameters -ErrorAction SilentlyContinue
            }
        }
    }
}
