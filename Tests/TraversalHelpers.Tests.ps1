<#
.SYNOPSIS
    Pester tests for TraversalHelpers functions.
    
.DESCRIPTION
    Unit tests for all pure helper functions in TraversalHelpers.ps1
    Tests cover state transitions, constraints, and traversal logic.
#>

BeforeAll {
}

Describe 'Get-NewTraversalState' {
    BeforeAll {
       
        # Create mock FK object
        $mockFk = [PSCustomObject]@{
            Schema    = 'dbo'
            Table     = 'Orders'
            FkSchema  = 'dbo'
            FkTable   = 'Customers'
            Name      = 'FK_Orders_Customers'
            FkColumns = @()
        }
        $mockFk.PSObject.TypeNames.Insert(0, 'TableFk')
    }

    Context 'Outgoing Direction' {
        It 'Include state remains Include' {
            $result = Get-NewTraversalState `
                -Direction ([TraversalDirection]::Outgoing) `
                -CurrentState ([TraversalState]::Include) `
                -Fk $mockFk `
                -FullSearch $false

            $result | Should -Be ([TraversalState]::Include)
        }

        It 'Pending state remains Pending' {
            $result = Get-NewTraversalState `
                -Direction ([TraversalDirection]::Outgoing) `
                -CurrentState ([TraversalState]::Pending) `
                -Fk $mockFk `
                -FullSearch $false

            $result | Should -Be ([TraversalState]::Pending)
        }

        It 'Exclude state remains Exclude' {
            $result = Get-NewTraversalState `
                -Direction ([TraversalDirection]::Outgoing) `
                -CurrentState ([TraversalState]::Exclude) `
                -Fk $mockFk `
                -FullSearch $false

            $result | Should -Be ([TraversalState]::Exclude)
        }
    }

    Context 'Incoming Direction' {
        It 'Include state becomes Pending when FullSearch is false' {
            $result = Get-NewTraversalState `
                -Direction ([TraversalDirection]::Incoming) `
                -CurrentState ([TraversalState]::Include) `
                -Fk $mockFk `
                -FullSearch $false

            $result | Should -Be ([TraversalState]::Pending)
        }

        It 'Include state remains Include when FullSearch is true' {
            $result = Get-NewTraversalState `
                -Direction ([TraversalDirection]::Incoming) `
                -CurrentState ([TraversalState]::Include) `
                -Fk $mockFk `
                -FullSearch $true

            $result | Should -Be ([TraversalState]::Include)
        }

        It 'Pending state remains Pending' {
            $result = Get-NewTraversalState `
                -Direction ([TraversalDirection]::Incoming) `
                -CurrentState ([TraversalState]::Pending) `
                -Fk $mockFk `
                -FullSearch $false

            $result | Should -Be ([TraversalState]::Pending)
        }

        It 'Exclude state remains Exclude' {
            $result = Get-NewTraversalState `
                -Direction ([TraversalDirection]::Incoming) `
                -CurrentState ([TraversalState]::Exclude) `
                -Fk $mockFk `
                -FullSearch $false

            $result | Should -Be ([TraversalState]::Exclude)
        }
    }

    Context 'TraversalConfiguration Override' {
        It 'Applies StateOverride when configuration is provided' {
            # Mock TraversalConfiguration
            $mockConfig = [PSCustomObject]@{} | Add-Member -MemberType ScriptMethod -Name GetItemForTable -Value {
                param($schema, $table)
                return [PSCustomObject]@{
                    StateOverride = [PSCustomObject]@{
                        State = [TraversalState]::Exclude
                    }
                }
            } -PassThru

            $result = Get-NewTraversalState `
                -Direction ([TraversalDirection]::Outgoing) `
                -CurrentState ([TraversalState]::Include) `
                -Fk $mockFk `
                -TraversalConfiguration $mockConfig `
                -FullSearch $false

            $result | Should -Be ([TraversalState]::Exclude)
        }

        It 'Uses default state when no override is configured' {
            $mockConfig = [PSCustomObject]@{} | Add-Member -MemberType ScriptMethod -Name GetItemForTable -Value {
                param($schema, $table)
                return $null
            } -PassThru

            $result = Get-NewTraversalState `
                -Direction ([TraversalDirection]::Outgoing) `
                -CurrentState ([TraversalState]::Include) `
                -Fk $mockFk `
                -TraversalConfiguration $mockConfig `
                -FullSearch $false

            $result | Should -Be ([TraversalState]::Include)
        }
    }
}

Describe 'Get-TraversalConstraints' {
    BeforeAll {
        $mockFk = [PSCustomObject]@{
            Schema    = 'dbo'
            Table     = 'Orders'
            FkSchema  = 'dbo'
            FkTable   = 'Customers'
        }
        $mockFk.PSObject.TypeNames.Insert(0, 'TableFk')
    }

    It 'Returns null constraints when no configuration provided' {
        $result = Get-TraversalConstraints `
            -Fk $mockFk `
            -Direction ([TraversalDirection]::Outgoing)

        $result.MaxDepth | Should -BeNullOrEmpty
        $result.Top | Should -BeNullOrEmpty
    }

    It 'Returns MaxDepth when configured' {
        $mockConfig = [PSCustomObject]@{} | Add-Member -MemberType ScriptMethod -Name GetItemForTable -Value {
            param($schema, $table)
            return [PSCustomObject]@{
                Constraints = [PSCustomObject]@{
                    MaxDepth = 3
                    Top      = -1
                }
            }
        } -PassThru

        $result = Get-TraversalConstraints `
            -Fk $mockFk `
            -Direction ([TraversalDirection]::Outgoing) `
            -TraversalConfiguration $mockConfig

        $result.MaxDepth | Should -Be 3
        $result.Top | Should -BeNullOrEmpty
    }

    It 'Returns Top when configured' {
        $mockConfig = [PSCustomObject]@{} | Add-Member -MemberType ScriptMethod -Name GetItemForTable -Value {
            param($schema, $table)
            return [PSCustomObject]@{
                Constraints = [PSCustomObject]@{
                    MaxDepth = -1
                    Top      = 100
                }
            }
        } -PassThru

        $result = Get-TraversalConstraints `
            -Fk $mockFk `
            -Direction ([TraversalDirection]::Outgoing) `
            -TraversalConfiguration $mockConfig

        $result.MaxDepth | Should -BeNullOrEmpty
        $result.Top | Should -Be 100
    }

    It 'Returns both MaxDepth and Top when both configured' {
        $mockConfig = [PSCustomObject]@{} | Add-Member -MemberType ScriptMethod -Name GetItemForTable -Value {
            param($schema, $table)
            return [PSCustomObject]@{
                Constraints = [PSCustomObject]@{
                    MaxDepth = 5
                    Top      = 50
                }
            }
        } -PassThru

        $result = Get-TraversalConstraints `
            -Fk $mockFk `
            -Direction ([TraversalDirection]::Outgoing) `
            -TraversalConfiguration $mockConfig

        $result.MaxDepth | Should -Be 5
        $result.Top | Should -Be 50
    }
}

Describe 'Test-ShouldTraverseDirection' {
    Context 'Outgoing Direction' {
        It 'Returns true for Include state' {
            $result = Test-ShouldTraverseDirection `
                -State ([TraversalState]::Include) `
                -Direction ([TraversalDirection]::Outgoing)

            $result | Should -Be $true
        }

        It 'Returns true for Pending state' {
            $result = Test-ShouldTraverseDirection `
                -State ([TraversalState]::Pending) `
                -Direction ([TraversalDirection]::Outgoing)

            $result | Should -Be $true
        }

        It 'Returns false for Exclude state' {
            $result = Test-ShouldTraverseDirection `
                -State ([TraversalState]::Exclude) `
                -Direction ([TraversalDirection]::Outgoing)

            $result | Should -Be $false
        }

        It 'Returns false for InboundOnly state' {
            $result = Test-ShouldTraverseDirection `
                -State ([TraversalState]::InboundOnly) `
                -Direction ([TraversalDirection]::Outgoing)

            $result | Should -Be $false
        }
    }

    Context 'Incoming Direction' {
        It 'Returns true for Include state' {
            $result = Test-ShouldTraverseDirection `
                -State ([TraversalState]::Include) `
                -Direction ([TraversalDirection]::Incoming)

            $result | Should -Be $true
        }

        It 'Returns true for InboundOnly state' {
            $result = Test-ShouldTraverseDirection `
                -State ([TraversalState]::InboundOnly) `
                -Direction ([TraversalDirection]::Incoming)

            $result | Should -Be $true
        }

        It 'Returns false for Pending state' {
            $result = Test-ShouldTraverseDirection `
                -State ([TraversalState]::Pending) `
                -Direction ([TraversalDirection]::Incoming)

            $result | Should -Be $false
        }

        It 'Returns false for Exclude state' {
            $result = Test-ShouldTraverseDirection `
                -State ([TraversalState]::Exclude) `
                -Direction ([TraversalDirection]::Incoming)

            $result | Should -Be $false
        }
    }
}

Describe 'Get-TopClause' {
    It 'Returns global MaxBatchSize when set' {
        $result = Get-TopClause -MaxBatchSize 1000 -Constraints @{ Top = 500 }
        $result | Should -Be "TOP (1000)"
    }

    It 'Returns constraint Top when MaxBatchSize is -1' {
        $result = Get-TopClause -MaxBatchSize -1 -Constraints @{ Top = 500 }
        $result | Should -Be "TOP (500)"
    }

    It 'Returns empty string when both are unlimited' {
        $result = Get-TopClause -MaxBatchSize -1 -Constraints @{ Top = $null }
        $result | Should -Be ""
    }

    It 'Returns empty string when no constraints provided' {
        $result = Get-TopClause -MaxBatchSize -1
        $result | Should -Be ""
    }

    It 'Prioritizes MaxBatchSize over constraint Top' {
        $result = Get-TopClause -MaxBatchSize 100 -Constraints @{ Top = 1000 }
        $result | Should -Be "TOP (100)"
    }
}

Describe 'Get-ForeignKeyRelationships' {
    BeforeAll {
        $mockTable = [PSCustomObject]@{
            SchemaName     = 'dbo'
            TableName      = 'Orders'
            ForeignKeys    = @('FK1', 'FK2')
            IsReferencedBy = @('FK3', 'FK4')
        }
        $mockTable.PSObject.TypeNames.Insert(0, 'TableInfo')
    }

    It 'Returns ForeignKeys for Outgoing direction' {
        $result = Get-ForeignKeyRelationships `
            -Table $mockTable `
            -Direction ([TraversalDirection]::Outgoing)

        $result | Should -HaveCount 2
        $result[0] | Should -Be 'FK1'
        $result[1] | Should -Be 'FK2'
    }

    It 'Returns IsReferencedBy for Incoming direction' {
        $result = Get-ForeignKeyRelationships `
            -Table $mockTable `
            -Direction ([TraversalDirection]::Incoming)

        $result | Should -HaveCount 2
        $result[0] | Should -Be 'FK3'
        $result[1] | Should -Be 'FK4'
    }
}

Describe 'Get-TargetTableInfo' {
    BeforeAll {
        $mockFk = [PSCustomObject]@{
            Schema   = 'dbo'
            Table    = 'Orders'
            FkSchema = 'dbo'
            FkTable  = 'Customers'
        }
        $mockFk.PSObject.TypeNames.Insert(0, 'TableFk')
    }

    It 'Returns target table info for Outgoing direction' {
        $result = Get-TargetTableInfo `
            -Fk $mockFk `
            -Direction ([TraversalDirection]::Outgoing)

        $result.Schema | Should -Be 'dbo'
        $result.Table | Should -Be 'Orders'
    }

    It 'Returns source table info for Incoming direction' {
        $result = Get-TargetTableInfo `
            -Fk $mockFk `
            -Direction ([TraversalDirection]::Incoming)

        $result.Schema | Should -Be 'dbo'
        $result.Table | Should -Be 'Customers'
    }
}

Describe 'Test-ShouldSkipTable' {
    It 'Returns true when table is in ignored list' {
        $ignoredTables = @(
            [PSCustomObject]@{ SchemaName = 'dbo'; TableName = 'IgnoredTable' }
        )
        
        # Mock the IsIgnored static method
        Mock -CommandName ([TableInfo2]::IsIgnored) -MockWith { $true }

        $result = Test-ShouldSkipTable `
            -Schema 'dbo' `
            -Table 'IgnoredTable' `
            -IgnoredTables $ignoredTables

        $result | Should -Be $true
    }

    It 'Returns true when TableInfo is null' {
        Mock -CommandName ([TableInfo2]::IsIgnored) -MockWith { $false }

        $result = Test-ShouldSkipTable `
            -Schema 'dbo' `
            -Table 'Orders' `
            -TableInfo $null

        $result | Should -Be $true
    }

    It 'Returns true when table has no primary key' {
        Mock -CommandName ([TableInfo2]::IsIgnored) -MockWith { $false }

        $mockTableInfo = [PSCustomObject]@{
            SchemaName = 'dbo'
            TableName  = 'Orders'
            PrimaryKey = @()
        }
        $mockTableInfo.PSObject.TypeNames.Insert(0, 'TableInfo')

        $result = Test-ShouldSkipTable `
            -Schema 'dbo' `
            -Table 'Orders' `
            -TableInfo $mockTableInfo

        $result | Should -Be $true
    }

    It 'Returns false when table is valid and not ignored' {
        Mock -CommandName ([TableInfo2]::IsIgnored) -MockWith { $false }

        $mockTableInfo = [PSCustomObject]@{
            SchemaName = 'dbo'
            TableName  = 'Orders'
            PrimaryKey = @('OrderID')
        }
        $mockTableInfo.PSObject.TypeNames.Insert(0, 'TableInfo')

        $result = Test-ShouldSkipTable `
            -Schema 'dbo' `
            -Table 'Orders' `
            -TableInfo $mockTableInfo

        $result | Should -Be $false
    }
}

Describe 'Get-JoinConditions' {
    BeforeAll {
        $mockColumn1 = [PSCustomObject]@{ Name = 'CustomerID' }
        $mockColumn2 = [PSCustomObject]@{ Name = 'OrderType' }
        
        $mockFk = [PSCustomObject]@{
            FkColumns = @($mockColumn1, $mockColumn2)
        }
        $mockFk.PSObject.TypeNames.Insert(0, 'TableFk')
    }

    It 'Generates correct JOIN conditions for single column FK' {
        $singleColumnFk = [PSCustomObject]@{
            FkColumns = @([PSCustomObject]@{ Name = 'CustomerID' })
        }
        $singleColumnFk.PSObject.TypeNames.Insert(0, 'TableFk')

        $result = Get-JoinConditions `
            -Fk $singleColumnFk `
            -Direction ([TraversalDirection]::Outgoing) `
            -SourceAlias 'src' `
            -TargetAlias 'tgt'

        $result | Should -Be "src.Key0 = tgt.CustomerID"
    }

    It 'Generates correct JOIN conditions for multi-column FK' {
        $result = Get-JoinConditions `
            -Fk $mockFk `
            -Direction ([TraversalDirection]::Outgoing) `
            -SourceAlias 'src' `
            -TargetAlias 'tgt'

        $result | Should -Be "src.Key0 = tgt.CustomerID AND src.Key1 = tgt.OrderType"
    }

    It 'Uses custom aliases correctly' {
        $singleColumnFk = [PSCustomObject]@{
            FkColumns = @([PSCustomObject]@{ Name = 'CustomerID' })
        }
        $singleColumnFk.PSObject.TypeNames.Insert(0, 'TableFk')

        $result = Get-JoinConditions `
            -Fk $singleColumnFk `
            -Direction ([TraversalDirection]::Outgoing) `
            -SourceAlias 'source' `
            -TargetAlias 'target'

        $result | Should -Be "source.Key0 = target.CustomerID"
    }
}

Describe 'Get-AdditionalWhereConditions' {
    It 'Returns empty array when no constraints and FullSearch is true' {
        $result = Get-AdditionalWhereConditions `
            -FkId 1 `
            -FullSearch $true

        $result | Should -HaveCount 0
    }

    It 'Includes cycle prevention when FullSearch is false' {
        $result = Get-AdditionalWhereConditions `
            -FkId 5 `
            -FullSearch $false

        $result | Should -HaveCount 1
        $result[0] | Should -Match "src\.Fk <> 5"
    }

    It 'Includes MaxDepth constraint when provided' {
        $result = Get-AdditionalWhereConditions `
            -Constraints @{ MaxDepth = 3 } `
            -FkId 1 `
            -FullSearch $true

        $result | Should -HaveCount 1
        $result[0] | Should -Be "src.Depth < 3"
    }

    It 'Includes both MaxDepth and cycle prevention' {
        $result = Get-AdditionalWhereConditions `
            -Constraints @{ MaxDepth = 3 } `
            -FkId 10 `
            -FullSearch $false

        $result | Should -HaveCount 2
        $result[0] | Should -Be "src.Depth < 3"
        $result[1] | Should -Match "src\.Fk <> 10"
    }

    It 'Ignores Top constraint (not used in WHERE clause)' {
        $result = Get-AdditionalWhereConditions `
            -Constraints @{ MaxDepth = 3; Top = 100 } `
            -FkId 1 `
            -FullSearch $true

        $result | Should -HaveCount 1
        $result[0] | Should -Not -Match "TOP"
    }
}
