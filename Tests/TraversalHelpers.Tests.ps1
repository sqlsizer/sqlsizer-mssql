<#
.SYNOPSIS
    Pester tests for TraversalHelpers functions.
    
.DESCRIPTION
    Unit tests for all pure helper functions in TraversalHelpers.ps1
    Tests cover state transitions, constraints, and traversal logic.
#>

Describe 'Get-NewTraversalState' {
    BeforeAll {
        # Create TableFk object
        $mockFk = New-Object TableFk
        $mockFk.Schema = 'dbo'
        $mockFk.Table = 'Orders'
        $mockFk.FkSchema = 'dbo'
        $mockFk.FkTable = 'Customers'
        $mockFk.Name = 'FK_Orders_Customers'
        $mockFk.FkColumns = New-Object 'System.Collections.Generic.List[ColumnInfo]'
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

        It 'IncludeFull state becomes Include' {
            $result = Get-NewTraversalState `
                -Direction ([TraversalDirection]::Outgoing) `
                -CurrentState ([TraversalState]::IncludeFull) `
                -Fk $mockFk `
                -FullSearch $false

            $result | Should -Be ([TraversalState]::Include)
        }
    }

    Context 'Incoming Direction' {
        It 'Include state resolves to Exclude sentinel when FullSearch is false' {
            $result = Get-NewTraversalState `
                -Direction ([TraversalDirection]::Incoming) `
                -CurrentState ([TraversalState]::Include) `
                -Fk $mockFk `
                -FullSearch $false

            $result | Should -Be ([TraversalState]::Exclude)
        }

        It 'Include state remains Include when FullSearch is true' {
            $result = Get-NewTraversalState `
                -Direction ([TraversalDirection]::Incoming) `
                -CurrentState ([TraversalState]::Include) `
                -Fk $mockFk `
                -FullSearch $true

            $result | Should -Be ([TraversalState]::Include)
        }

        It 'Pending state resolves to Exclude sentinel' {
            $result = Get-NewTraversalState `
                -Direction ([TraversalDirection]::Incoming) `
                -CurrentState ([TraversalState]::Pending) `
                -Fk $mockFk `
                -FullSearch $false

            $result | Should -Be ([TraversalState]::Exclude)
        }

        It 'Exclude state remains Exclude' {
            $result = Get-NewTraversalState `
                -Direction ([TraversalDirection]::Incoming) `
                -CurrentState ([TraversalState]::Exclude) `
                -Fk $mockFk `
                -FullSearch $false

            $result | Should -Be ([TraversalState]::Exclude)
        }

        It 'IncludeFull state becomes Include regardless of FullSearch' {
            $result = Get-NewTraversalState `
                -Direction ([TraversalDirection]::Incoming) `
                -CurrentState ([TraversalState]::IncludeFull) `
                -Fk $mockFk `
                -FullSearch $false

            $result | Should -Be ([TraversalState]::Include)
        }

        It 'IncludeFull state becomes Include when FullSearch is true' {
            $result = Get-NewTraversalState `
                -Direction ([TraversalDirection]::Incoming) `
                -CurrentState ([TraversalState]::IncludeFull) `
                -Fk $mockFk `
                -FullSearch $true

            $result | Should -Be ([TraversalState]::Include)
        }

        It 'InboundOnly state remains InboundOnly' {
            $result = Get-NewTraversalState `
                -Direction ([TraversalDirection]::Incoming) `
                -CurrentState ([TraversalState]::InboundOnly) `
                -Fk $mockFk `
                -FullSearch $false

            $result | Should -Be ([TraversalState]::InboundOnly)
        }
    }

    Context 'TraversalConfiguration Override' {
        It 'Applies StateOverride when configuration is provided' {
            # Create TraversalConfiguration with StateOverride
            $config = New-Object TraversalConfiguration
            $rule = New-Object TraversalRule -ArgumentList 'dbo', 'Orders'
            $rule.StateOverride = New-Object StateOverride -ArgumentList ([TraversalState]::Exclude)
            $config.Rules = @($rule)

            $result = Get-NewTraversalState `
                -Direction ([TraversalDirection]::Outgoing) `
                -CurrentState ([TraversalState]::Include) `
                -Fk $mockFk `
                -TraversalConfiguration $config `
                -FullSearch $false

            $result | Should -Be ([TraversalState]::Exclude)
        }

        It 'Uses default state when no override is configured' {
            $config = New-Object TraversalConfiguration

            $result = Get-NewTraversalState `
                -Direction ([TraversalDirection]::Outgoing) `
                -CurrentState ([TraversalState]::Include) `
                -Fk $mockFk `
                -TraversalConfiguration $config `
                -FullSearch $false

            $result | Should -Be ([TraversalState]::Include)
        }
    }
}

Describe 'Get-TraversalConstraints' {
    BeforeAll {
        $mockFk = New-Object TableFk
        $mockFk.Schema = 'dbo'
        $mockFk.Table = 'Orders'
        $mockFk.FkSchema = 'dbo'
        $mockFk.FkTable = 'Customers'
    }

    It 'Returns null constraints when no configuration provided' {
        $result = Get-TraversalConstraints `
            -Fk $mockFk `
            -Direction ([TraversalDirection]::Outgoing)

        $result.MaxDepth | Should -BeNullOrEmpty
        $result.Top | Should -BeNullOrEmpty
    }

    It 'Returns MaxDepth when configured' {
        $config = New-Object TraversalConfiguration
        $rule = New-Object TraversalRule -ArgumentList 'dbo', 'Orders'
        $rule.Constraints = New-Object TraversalConstraints
        $rule.Constraints.MaxDepth = 3
        $rule.Constraints.Top = -1
        $config.Rules = @($rule)

        $result = Get-TraversalConstraints `
            -Fk $mockFk `
            -Direction ([TraversalDirection]::Outgoing) `
            -TraversalConfiguration $config

        $result.MaxDepth | Should -Be 3
        $result.Top | Should -BeNullOrEmpty
    }

    It 'Returns Top when configured' {
        $config = New-Object TraversalConfiguration
        $rule = New-Object TraversalRule -ArgumentList 'dbo', 'Orders'
        $rule.Constraints = New-Object TraversalConstraints
        $rule.Constraints.MaxDepth = -1
        $rule.Constraints.Top = 100
        $config.Rules = @($rule)

        $result = Get-TraversalConstraints `
            -Fk $mockFk `
            -Direction ([TraversalDirection]::Outgoing) `
            -TraversalConfiguration $config

        $result.MaxDepth | Should -BeNullOrEmpty
        $result.Top | Should -Be 100
    }

    It 'Returns both MaxDepth and Top when both configured' {
        $config = New-Object TraversalConfiguration
        $rule = New-Object TraversalRule -ArgumentList 'dbo', 'Orders'
        $rule.Constraints = New-Object TraversalConstraints
        $rule.Constraints.MaxDepth = 5
        $rule.Constraints.Top = 50
        $config.Rules = @($rule)

        $result = Get-TraversalConstraints `
            -Fk $mockFk `
            -Direction ([TraversalDirection]::Outgoing) `
            -TraversalConfiguration $config

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

        It 'Returns true for IncludeFull state' {
            $result = Test-ShouldTraverseDirection `
                -State ([TraversalState]::IncludeFull) `
                -Direction ([TraversalDirection]::Outgoing)

            $result | Should -Be $true
        }
    }

    Context 'Incoming Direction' {
        It 'Returns false for Include state when FullSearch=false (default)' {
            $result = Test-ShouldTraverseDirection `
                -State ([TraversalState]::Include) `
                -Direction ([TraversalDirection]::Incoming)

            $result | Should -Be $false
        }

        It 'Returns true for Include state when FullSearch=true' {
            $result = Test-ShouldTraverseDirection `
                -State ([TraversalState]::Include) `
                -Direction ([TraversalDirection]::Incoming) `
                -FullSearch $true

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

        It 'Returns true for IncludeFull state regardless of FullSearch' {
            $result = Test-ShouldTraverseDirection `
                -State ([TraversalState]::IncludeFull) `
                -Direction ([TraversalDirection]::Incoming) `
                -FullSearch $false

            $result | Should -Be $true
        }

        It 'Returns true for IncludeFull state when FullSearch is true' {
            $result = Test-ShouldTraverseDirection `
                -State ([TraversalState]::IncludeFull) `
                -Direction ([TraversalDirection]::Incoming) `
                -FullSearch $true

            $result | Should -Be $true
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
        $mockTable = New-Object TableInfo
        $mockTable.SchemaName = 'dbo'
        $mockTable.TableName = 'Orders'
        
        # Create ForeignKeys list with actual TableFk objects
        $mockTable.ForeignKeys = New-Object 'System.Collections.Generic.List[TableFk]'
        $fk1 = New-Object TableFk
        $fk1.Name = 'FK1'
        $fk2 = New-Object TableFk
        $fk2.Name = 'FK2'
        $mockTable.ForeignKeys.Add($fk1)
        $mockTable.ForeignKeys.Add($fk2)
        
        # Create IsReferencedBy list with actual TableInfo objects 
        $mockTable.IsReferencedBy = New-Object 'System.Collections.Generic.List[TableInfo]'
        $fk3 = New-Object TableInfo
        $fk3.TableName = 'T1'
        $fk4 = New-Object TableInfo
        $fk4.TableName = 'T2'
        $mockTable.IsReferencedBy.Add($fk3)
        $mockTable.IsReferencedBy.Add($fk4)
    }

    It 'Returns ForeignKeys for Outgoing direction' {
        $result = Get-ForeignKeyRelationships `
            -Table $mockTable `
            -Direction ([TraversalDirection]::Outgoing)

        $result | Should -HaveCount 2
        $result[0].Name | Should -Be 'FK1'
        $result[1].Name | Should -Be 'FK2'
    }

    It 'Returns IsReferencedBy for Incoming direction' {
        $result = Get-ForeignKeyRelationships `
            -Table $mockTable `
            -Direction ([TraversalDirection]::Incoming)

        $result | Should -HaveCount 2
        $result[0].TableName | Should -Be 'T1'
        $result[1].TableName | Should -Be 'T2'
    }
}

Describe 'Get-TargetTableInfo' {
    BeforeAll {
        $mockFk = New-Object TableFk
        $mockFk.Schema = 'dbo'
        $mockFk.Table = 'Orders'
        $mockFk.FkSchema = 'dbo'
        $mockFk.FkTable = 'Customers'
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
            [TableInfo2]@{ SchemaName = 'dbo'; TableName = 'IgnoredTable' }
        )
        
        $result = Test-ShouldSkipTable `
            -Schema 'dbo' `
            -Table 'IgnoredTable' `
            -IgnoredTables $ignoredTables

        $result | Should -Be $true
    }

    It 'Returns true when TableInfo is null' {
        $result = Test-ShouldSkipTable `
            -Schema 'dbo' `
            -Table 'Orders' `
            -TableInfo $null

        $result | Should -Be $true
    }

    It 'Returns true when table has no primary key' {
        $mockTableInfo = New-Object TableInfo
        $mockTableInfo.SchemaName = 'dbo'
        $mockTableInfo.TableName = 'Orders'
        $mockTableInfo.PrimaryKey = New-Object 'System.Collections.Generic.List[ColumnInfo]'

        $result = Test-ShouldSkipTable `
            -Schema 'dbo' `
            -Table 'Orders' `
            -TableInfo $mockTableInfo

        $result | Should -Be $true
    }

    It 'Returns false when table is valid and not ignored' {
        $mockTableInfo = New-Object TableInfo
        $mockTableInfo.SchemaName = 'dbo'
        $mockTableInfo.TableName = 'Orders'
        $mockTableInfo.PrimaryKey = New-Object 'System.Collections.Generic.List[ColumnInfo]'
        $column = New-Object ColumnInfo
        $column.Name = 'OrderID'
        $mockTableInfo.PrimaryKey.Add($column)

        $result = Test-ShouldSkipTable `
            -Schema 'dbo' `
            -Table 'Orders' `
            -TableInfo $mockTableInfo

        $result | Should -Be $false
    }
}

Describe 'Get-JoinConditions' {
    BeforeAll {
        $mockColumn1 = New-Object ColumnInfo
        $mockColumn1.Name = 'CustomerID'
        $mockColumn2 = New-Object ColumnInfo
        $mockColumn2.Name = 'OrderType'
        
        $mockFk = New-Object TableFk
        $mockFk.FkColumns = New-Object 'System.Collections.Generic.List[ColumnInfo]'
        $mockFk.FkColumns.Add($mockColumn1)
        $mockFk.FkColumns.Add($mockColumn2)
    }

    It 'Generates correct JOIN conditions for single column FK' {
        $singleColumnFk = New-Object TableFk
        $singleColumnFk.FkColumns = New-Object 'System.Collections.Generic.List[ColumnInfo]'
        $column = New-Object ColumnInfo
        $column.Name = 'CustomerID'
        $singleColumnFk.FkColumns.Add($column)

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
        $singleColumnFk = New-Object TableFk
        $singleColumnFk.FkColumns = New-Object 'System.Collections.Generic.List[ColumnInfo]'
        $column = New-Object ColumnInfo
        $column.Name = 'CustomerID'
        $singleColumnFk.FkColumns.Add($column)

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

    It 'Does not add FK-name cycle prevention when FullSearch is false' {
        $result = Get-AdditionalWhereConditions `
            -FkId 5 `
            -FullSearch $false

        $result | Should -HaveCount 0
    }

    It 'Includes MaxDepth constraint when provided' {
        $result = Get-AdditionalWhereConditions `
            -Constraints @{ MaxDepth = 3 } `
            -FkId 1 `
            -FullSearch $true

        $result | Should -Be "src.Depth < 3"
    }

    It 'Includes MaxDepth without FK-name cycle prevention' {
        $result = Get-AdditionalWhereConditions `
            -Constraints @{ MaxDepth = 3 } `
            -FkId 10 `
            -FullSearch $false

        $result | Should -HaveCount 1
        $result[0] | Should -Be "src.Depth < 3"
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

Describe 'Get-IncludedTraversalStateValues' {
    It 'Includes closure output states' {
        $result = Get-IncludedTraversalStateValues

        $result | Should -Contain ([int][TraversalState]::Include)
        $result | Should -Contain ([int][TraversalState]::InboundOnly)
        $result | Should -Contain ([int][TraversalState]::IncludeFull)
    }

    It 'Excludes bookkeeping states' {
        $result = Get-IncludedTraversalStateValues

        $result | Should -Not -Contain ([int][TraversalState]::Pending)
        $result | Should -Not -Contain ([int][TraversalState]::Exclude)
    }
}

Describe 'Get-IncludedTraversalStateSqlList' {
    It 'Returns a deterministic SQL list for output closure filters' {
        $result = Get-IncludedTraversalStateSqlList

        $result | Should -Be '1, 4, 5'
    }
}

Describe 'TraversalRule Convenience Methods' {
    Context 'Constraint Setting Methods' {
        It 'SetTop creates constraints and sets Top value' {
            $rule = New-Object TraversalRule -ArgumentList 'dbo', 'Orders'
            
            $rule.SetTop(50)
            
            $rule.Constraints | Should -Not -BeNull
            $rule.Constraints.Top | Should -Be 50
        }
        
        It 'SetMaxDepth creates constraints and sets MaxDepth value' {
            $rule = New-Object TraversalRule -ArgumentList 'dbo', 'Orders'
            
            $rule.SetMaxDepth(3)
            
            $rule.Constraints | Should -Not -BeNull
            $rule.Constraints.MaxDepth | Should -Be 3
        }
        
        It 'SetSourceFilter creates constraints and sets source filter' {
            $rule = New-Object TraversalRule -ArgumentList 'dbo', 'Orders'
            
            $rule.SetSourceFilter('Sales', 'Customers')
            
            $rule.Constraints | Should -Not -BeNull
            $rule.Constraints.SourceSchemaName | Should -Be 'Sales'
            $rule.Constraints.SourceTableName | Should -Be 'Customers'
        }
        
        It 'SetForeignKeyFilter creates constraints and sets FK filter' {
            $rule = New-Object TraversalRule -ArgumentList 'dbo', 'Orders'
            
            $rule.SetForeignKeyFilter('FK_Orders_Customers')
            
            $rule.Constraints | Should -Not -BeNull
            $rule.Constraints.ForeignKeyName | Should -Be 'FK_Orders_Customers'
        }
        
        It 'Multiple constraint methods work together' {
            $rule = New-Object TraversalRule -ArgumentList 'dbo', 'Orders'
            
            $rule.SetTop(100).SetMaxDepth(2).SetSourceFilter('Sales', 'Invoices')
            
            $rule.Constraints.Top | Should -Be 100
            $rule.Constraints.MaxDepth | Should -Be 2
            $rule.Constraints.SourceSchemaName | Should -Be 'Sales'
            $rule.Constraints.SourceTableName | Should -Be 'Invoices'
        }
        
        It 'SetStateOverride creates state override and sets state' {
            $rule = New-Object TraversalRule -ArgumentList 'dbo', 'Orders'
            
            $rule.SetStateOverride([TraversalState]::Include)
            
            $rule.StateOverride | Should -Not -BeNull
            $rule.StateOverride.State | Should -Be ([TraversalState]::Include)
        }
        
        It 'Methods return the rule for chaining' {
            $rule = New-Object TraversalRule -ArgumentList 'dbo', 'Orders'
            
            $result = $rule.SetTop(50)
            
            $result | Should -Be $rule
            $rule.Constraints.Top | Should -Be 50
        }
    }
}

Describe 'TraversalConfiguration Convenience Methods' {
    Context 'Ignored Tables Management' {
        It 'AddIgnoredTable adds table and returns config for chaining' {
            $config = New-Object TraversalConfiguration
            
            $result = $config.AddIgnoredTable("dbo", "AuditLog")
            
            $result | Should -Be $config
            $config.IgnoredTables.Count | Should -Be 1
            $config.IgnoredTables[0].SchemaName | Should -Be "dbo"
            $config.IgnoredTables[0].TableName | Should -Be "AuditLog"
        }
        
        It 'Methods can be chained' {
            $config = New-Object TraversalConfiguration
            
            $config.AddIgnoredTable("dbo", "AuditLog").AddIgnoredTable("dbo", "ErrorLog")
            
            $config.IgnoredTables.Count | Should -Be 2
            $config.IgnoredTables[0].TableName | Should -Be "AuditLog"
            $config.IgnoredTables[1].TableName | Should -Be "ErrorLog"
        }
        
        It 'AddRule adds rule and returns config for chaining' {
            $config = New-Object TraversalConfiguration
            $rule = New-Object TraversalRule -ArgumentList 'dbo', 'Orders'
            
            $result = $config.AddRule($rule)
            
            $result | Should -Be $config
            $config.Rules.Count | Should -Be 1
            $config.Rules[0] | Should -Be $rule
        }
    }
}
