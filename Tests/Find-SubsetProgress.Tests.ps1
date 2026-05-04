BeforeDiscovery {
    $modulePath = Split-Path -Parent $PSScriptRoot
    Import-Module "$modulePath\SqlSizer-MSSQL\SqlSizer-MSSQL" -Force -Global -ErrorAction Stop
}

Describe 'Find-Subset progress formatting' {
    InModuleScope SqlSizer-MSSQL {
        It 'Formats elapsed time and record counts in progress status' {
            $stats = [TraversalStatistics]::new()
            $stats.TotalOperations = 5
            $stats.CompletedOperations = 2
            $stats.TotalRecordsProcessed = 1000
            $stats.TotalRecordsRemaining = 3000

            $status = Get-FindSubsetProgressStatus `
                -Statistics $stats `
                -Iteration 12 `
                -ElapsedTime ([TimeSpan]::FromSeconds(3723))

            $status | Should -Be '25% | elapsed 01:02:03 | records 1,000 processed / 3,000 remaining | ops 2/5 | iteration 12'
        }

        It 'Includes phase context when provided' {
            $stats = [TraversalStatistics]::new()
            $stats.TotalOperations = 4
            $stats.CompletedOperations = 1
            $stats.TotalRecordsProcessed = 250
            $stats.TotalRecordsRemaining = 750

            $status = Get-FindSubsetProgressStatus `
                -Statistics $stats `
                -Iteration 3 `
                -ElapsedTime ([TimeSpan]::FromSeconds(5)) `
                -Phase 'Executing traversal SQL'

            $status | Should -Be 'Executing traversal SQL | 25% | elapsed 00:00:05 | records 250 processed / 750 remaining | ops 1/4 | iteration 3'
        }

        It 'Formats current table operation context' {
            $table = [TableInfo]::new()
            $table.SchemaName = 'dbo'
            $table.TableName = 'Orders'

            $operation = [TraversalOperation]::new()
            $operation.State = [TraversalState]::Include
            $operation.Depth = 2
            $operation.RecordsToProcess = 12345

            $currentOperation = Get-FindSubsetProgressCurrentOperation -Table $table -Operation $operation

            $currentOperation | Should -Be 'dbo.Orders | state Include | depth 2 | operation records 12,345'
        }

        It 'Includes phase context in current operation when provided' {
            $table = [TableInfo]::new()
            $table.SchemaName = 'dbo'
            $table.TableName = 'Orders'

            $operation = [TraversalOperation]::new()
            $operation.State = [TraversalState]::Include
            $operation.Depth = 2
            $operation.RecordsToProcess = 12345

            $currentOperation = Get-FindSubsetProgressCurrentOperation `
                -Table $table `
                -Operation $operation `
                -Phase 'Marking operation in progress'

            $currentOperation | Should -Be 'Marking operation in progress | dbo.Orders | state Include | depth 2 | operation records 12,345'
        }

        It 'Handles null statistics safely' {
            $status = Get-FindSubsetProgressStatus `
                -Statistics $null `
                -Iteration 0 `
                -ElapsedTime ([TimeSpan]::Zero)

            $status | Should -Be '0% | elapsed 00:00:00 | records 0 processed / 0 remaining | ops 0/0 | iteration 0'
            Get-FindSubsetProgressPercent -Statistics $null | Should -Be 0.0
        }
    }
}

Describe 'Find-Subset performance profiling' {
    InModuleScope SqlSizer-MSSQL {
        It 'Aggregates SQL and PowerShell profile samples by phase' {
            $samples = @(
                [pscustomobject]@{
                    Category = 'SQL'
                    Phase = 'Executing traversal SQL'
                    Iteration = 2
                    Table = 'dbo.Orders'
                    State = 'Include'
                    Depth = 1
                    Direction = ''
                    ElapsedMs = 120.5
                    LogicalReads = 300
                    SqlChars = 4000
                },
                [pscustomobject]@{
                    Category = 'SQL'
                    Phase = 'Executing traversal SQL'
                    Iteration = 3
                    Table = 'dbo.Orders'
                    State = 'Include'
                    Depth = 1
                    Direction = ''
                    ElapsedMs = 80
                    LogicalReads = 200
                    SqlChars = 3000
                },
                [pscustomobject]@{
                    Category = 'PowerShell'
                    Phase = 'Building Incoming traversal SQL'
                    Iteration = 2
                    Table = 'dbo.Orders'
                    State = 'Include'
                    Depth = 1
                    Direction = 'Incoming'
                    ElapsedMs = 15.25
                    LogicalReads = 0
                    SqlChars = 1500
                    RelationshipsVisited = 12
                    FksScanned = 9
                    FksEmitted = 4
                    IgnoredChecks = 9
                    GeneratedQueryCount = 5
                    RuleBranchCalls = 4
                    RuleBranchElapsedMs = 3.2
                },
                [pscustomobject]@{
                    Category = 'PowerShell'
                    Phase = 'Runtime subset guard check'
                    Iteration = 5
                    Table = ''
                    State = ''
                    Depth = 0
                    Direction = ''
                    ElapsedMs = 2
                    LogicalReads = 0
                    SqlChars = 0
                }
            )

            $profile = ConvertTo-FindSubsetPerformanceProfile -Samples $samples

            $profile.Summary.TotalCalls | Should -Be 4
            $profile.Summary.SqlCallCount | Should -Be 2
            $profile.Summary.PowerShellCallCount | Should -Be 2
            $profile.Summary.TotalElapsedMs | Should -Be 217.75
            $profile.Summary.SqlElapsedMs | Should -Be 200.5
            $profile.Summary.PowerShellElapsedMs | Should -Be 17.25
            $profile.Summary.TotalLogicalReads | Should -Be 500
            $profile.Summary.TotalSqlChars | Should -Be 8500

            $sqlPhase = $profile.ByPhase | Where-Object { $_.Category -eq 'SQL' -and $_.Phase -eq 'Executing traversal SQL' }
            $sqlPhase.CallCount | Should -Be 2
            $sqlPhase.TotalElapsedMs | Should -Be 200.5
            $sqlPhase.AverageElapsedMs | Should -Be 100.25
            $sqlPhase.TotalLogicalReads | Should -Be 500
            $sqlPhase.TotalSqlChars | Should -Be 7000

            $buildPhase = $profile.ByPhase | Where-Object { $_.Category -eq 'PowerShell' -and $_.Phase -eq 'Building Incoming traversal SQL' }
            $buildPhase.RelationshipsVisited | Should -Be 12
            $buildPhase.FksScanned | Should -Be 9
            $buildPhase.FksEmitted | Should -Be 4
            $buildPhase.IgnoredChecks | Should -Be 9
            $buildPhase.GeneratedQueryCount | Should -Be 5
            $buildPhase.RuleBranchCalls | Should -Be 4
            $buildPhase.RuleBranchElapsedMs | Should -Be 3.2

            $profile.SlowestCalls[0].ElapsedMs | Should -Be 120.5
            $profile.PowerShellBuildHotspots[0].Phase | Should -Be 'Building Incoming traversal SQL'
            $profile.PowerShellBuildHotspots[0].FksScanned | Should -Be 9
        }

        It 'Handles empty profile samples' {
            $profile = ConvertTo-FindSubsetPerformanceProfile -Samples @()

            $profile.Summary.TotalCalls | Should -Be 0
            $profile.Summary.TotalElapsedMs | Should -Be 0
            $profile.Summary.SqlCallCount | Should -Be 0
            $profile.Summary.PowerShellCallCount | Should -Be 0
            @($profile.ByPhase).Count | Should -Be 0
            @($profile.SlowestCalls).Count | Should -Be 0
            @($profile.PowerShellBuildHotspots).Count | Should -Be 0
        }

        It 'Adds PerformanceProfile only when requested' {
            $plain = New-FindSubsetResultObject `
                -Finished $true `
                -Initialized $true `
                -CompletedIterations 3 `
                -SubsetSizeGuard $null

            $plain.PSObject.Properties.Name | Should -Not -Contain 'PerformanceProfile'

            $expectedProfile = [pscustomobject]@{
                Summary = [pscustomobject]@{
                    TotalCalls = 1
                }
            }

            $profiled = New-FindSubsetResultObject `
                -Finished $true `
                -Initialized $true `
                -CompletedIterations 3 `
                -SubsetSizeGuard $null `
                -IncludePerformanceProfile $true `
                -PerformanceProfile $expectedProfile

            $profiled.PerformanceProfile | Should -Be $expectedProfile
        }

        It 'Builds ignored table key sets with case-insensitive lookup' {
            $ignoredTables = @(
                [TableInfo2]@{
                    SchemaName = 'dbo'
                    TableName = 'AuditLog'
                },
                [TableInfo2]@{
                    SchemaName = 'Ops'
                    TableName = 'Trace'
                }
            )

            $keySet = New-FindSubsetIgnoredTableKeySet -Tables $ignoredTables

            $keySet.Contains('DBO, auditlog') | Should -Be $true
            $keySet.Contains('ops, TRACE') | Should -Be $true
            $keySet.Contains('dbo, Orders') | Should -Be $false
        }

        It 'Builds incoming FK lookup equivalent to scanning referenced tables' {
            $parent = [TableInfo]::new()
            $parent.SchemaName = 'dbo'
            $parent.TableName = 'Parent'
            $parent.ForeignKeys = [System.Collections.Generic.List[TableFk]]::new()
            $parent.IsReferencedBy = [System.Collections.Generic.List[TableInfo]]::new()

            $child1 = [TableInfo]::new()
            $child1.SchemaName = 'dbo'
            $child1.TableName = 'Child1'
            $child1.ForeignKeys = [System.Collections.Generic.List[TableFk]]::new()
            $child1.IsReferencedBy = [System.Collections.Generic.List[TableInfo]]::new()

            $child2 = [TableInfo]::new()
            $child2.SchemaName = 'sales'
            $child2.TableName = 'Child2'
            $child2.ForeignKeys = [System.Collections.Generic.List[TableFk]]::new()
            $child2.IsReferencedBy = [System.Collections.Generic.List[TableInfo]]::new()

            $other = [TableInfo]::new()
            $other.SchemaName = 'dbo'
            $other.TableName = 'Other'
            $other.ForeignKeys = [System.Collections.Generic.List[TableFk]]::new()
            $other.IsReferencedBy = [System.Collections.Generic.List[TableInfo]]::new()

            $fk1 = [TableFk]::new()
            $fk1.Name = 'FK_Child1_Parent'
            $fk1.FkSchema = $child1.SchemaName
            $fk1.FkTable = $child1.TableName
            $fk1.Schema = $parent.SchemaName
            $fk1.Table = $parent.TableName

            $fk2 = [TableFk]::new()
            $fk2.Name = 'FK_Child2_Parent'
            $fk2.FkSchema = $child2.SchemaName
            $fk2.FkTable = $child2.TableName
            $fk2.Schema = $parent.SchemaName
            $fk2.Table = $parent.TableName

            $fk3 = [TableFk]::new()
            $fk3.Name = 'FK_Child2_Other'
            $fk3.FkSchema = $child2.SchemaName
            $fk3.FkTable = $child2.TableName
            $fk3.Schema = $other.SchemaName
            $fk3.Table = $other.TableName

            $child1.ForeignKeys.Add($fk1)
            $child2.ForeignKeys.Add($fk2)
            $child2.ForeignKeys.Add($fk3)
            $parent.IsReferencedBy.Add($child1)
            $parent.IsReferencedBy.Add($child2)

            $databaseInfo = [DatabaseInfo]::new()
            $databaseInfo.Tables = [System.Collections.Generic.List[TableInfo]]::new()
            $databaseInfo.Tables.Add($parent)
            $databaseInfo.Tables.Add($child1)
            $databaseInfo.Tables.Add($child2)
            $databaseInfo.Tables.Add($other)

            $lookup = New-FindSubsetIncomingForeignKeyLookup -DatabaseInfo $databaseInfo
            $key = 'dbo, Parent'
            $fromLookup = @($lookup[$key] | Sort-Object Name)
            $fromScan = @(
                $parent.IsReferencedBy |
                    ForEach-Object {
                        $_.ForeignKeys | Where-Object {
                            ($_.Schema -eq $parent.SchemaName) -and ($_.Table -eq $parent.TableName)
                        }
                    } |
                    Sort-Object Name
            )

            @($fromLookup).Count | Should -Be 2
            @($fromLookup).Count | Should -Be @($fromScan).Count
            $fromLookup[0].Name | Should -Be $fromScan[0].Name
            $fromLookup[1].Name | Should -Be $fromScan[1].Name
            $lookup['dbo, Other'][0].Name | Should -Be 'FK_Child2_Other'
        }
    }
}

Describe 'Find-Subset progress source wiring' {
    It 'Uses enriched Write-Progress status and current operation text' {
        $modulePath = Split-Path -Parent $PSScriptRoot
        $script = Get-Content -LiteralPath "$modulePath\SqlSizer-MSSQL\Public\Find-Subset.ps1" -Raw

        $script | Should -Match 'Get-FindSubsetProgressStatus'
        $script | Should -Match 'Get-FindSubsetProgressCurrentOperation'
        $script | Should -Match '-Status \$progressStatus'
        $script | Should -Match '-CurrentOperation \$progressOperation'
        $script | Should -Match 'elapsed \$elapsed'
        $script | Should -Match 'Invoke-FindSubsetSql'
        $script | Should -Match 'Executing traversal SQL'
        $script | Should -Match 'CollectSqlStatistics = \$false'
        $script | Should -Match 'CollectPerformanceProfile = \$false'
        $script | Should -Match 'ConvertTo-FindSubsetPerformanceProfile'
        $script | Should -Match 'PowerShellBuildHotspots'
        $script | Should -Match 'New-FindSubsetIncomingForeignKeyLookup'
        $script | Should -Match 'New-FindSubsetIgnoredTableKeySet'
        $script | Should -Match 'incomingFksByTarget'
        $script | Should -Match 'Test-FindSubsetIgnoredTable'
        $script | Should -Match 'System\.Collections\.Generic\.HashSet\[string\]'
        $script | Should -Match 'RelationshipsVisited'
        $script | Should -Not -Match '\$rel\.ForeignKeys\s*\|\s*Where-Object'
        $script | Should -Match 'ProgressRefreshInterval = 5'
    }
}
