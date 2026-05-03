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
        $script | Should -Match 'ProgressRefreshInterval = 5'
    }
}
