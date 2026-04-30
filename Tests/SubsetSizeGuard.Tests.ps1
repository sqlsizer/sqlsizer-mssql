<#
.SYNOPSIS
    Unit tests for Find-Subset whole-database guard helpers.
#>

BeforeAll {
    $modulePath = Split-Path -Parent $PSScriptRoot
    Import-Module "$modulePath\SqlSizer-MSSQL\SqlSizer-MSSQL" -Force -Global

    function New-GuardColumn {
        param([string]$Name = 'Id')

        $column = New-Object ColumnInfo
        $column.Name = $Name
        $column.DataType = 'int'
        $column.Length = '4'
        $column.IsNullable = $false
        $column.IsPresent = $true
        return $column
    }

    function New-GuardTable {
        param(
            [string]$SchemaName = 'dbo',
            [string]$TableName,
            [Nullable[long]]$Rows = 100
        )

        $table = New-Object TableInfo
        $table.SchemaName = $SchemaName
        $table.TableName = $TableName
        $table.PrimaryKey = [System.Collections.Generic.List[ColumnInfo]]::new()
        $table.PrimaryKey.Add((New-GuardColumn))
        $table.Columns = [System.Collections.Generic.List[ColumnInfo]]::new()
        $table.ForeignKeys = [System.Collections.Generic.List[TableFk]]::new()
        $table.IsReferencedBy = [System.Collections.Generic.List[TableInfo]]::new()
        $table.Indexes = [System.Collections.Generic.List[TableIndex]]::new()
        $table.Views = [System.Collections.Generic.List[ViewInfo]]::new()
        $table.Triggers = [System.Collections.Generic.List[string]]::new()

        if ($null -ne $Rows)
        {
            $stats = New-Object TableStatistics
            $stats.Rows = [long]$Rows
            $table.Statistics = $stats
        }

        return $table
    }

    function Add-GuardFk {
        param(
            [TableInfo]$From,
            [TableInfo]$To,
            [string]$Name
        )

        $fk = New-Object TableFk
        $fk.Name = $Name
        $fk.FkSchema = $From.SchemaName
        $fk.FkTable = $From.TableName
        $fk.Schema = $To.SchemaName
        $fk.Table = $To.TableName
        $fk.FkColumns = [System.Collections.Generic.List[ColumnInfo]]::new()
        $fk.FkColumns.Add((New-GuardColumn -Name "$($To.TableName)Id"))
        $fk.Columns = [System.Collections.Generic.List[ColumnInfo]]::new()
        $fk.Columns.Add((New-GuardColumn))

        $From.ForeignKeys.Add($fk)
        $To.IsReferencedBy.Add($From)
    }

    function New-GuardDatabaseInfo {
        param([TableInfo[]]$Tables)

        $info = New-Object DatabaseInfo
        $info.Tables = [System.Collections.Generic.List[TableInfo]]::new()
        foreach ($table in $Tables)
        {
            $info.Tables.Add($table)
        }
        $info.Schemas = [System.Collections.Generic.List[string]]::new()
        $info.Views = [System.Collections.Generic.List[ViewInfo]]::new()
        $info.StoredProcedures = [System.Collections.Generic.List[StoredProcedureInfo]]::new()
        return $info
    }

    function New-SeedState {
        param(
            [string]$TableName,
            [TraversalState]$State = [TraversalState]::Include
        )

        return [pscustomobject]@{
            SchemaName = 'dbo'
            TableName = $TableName
            State = [int]$State
        }
    }
}

Describe 'Subset size guard metadata reachability' {
    BeforeEach {
        $script:categories = New-GuardTable -TableName 'Categories' -Rows 10
        $script:subCategories = New-GuardTable -TableName 'SubCategories' -Rows 20
        $script:products = New-GuardTable -TableName 'Products' -Rows 50
        Add-GuardFk -From $script:subCategories -To $script:categories -Name 'FK_SubCategories_Categories'
        Add-GuardFk -From $script:products -To $script:subCategories -Name 'FK_Products_SubCategories'
        $script:dbInfo = New-GuardDatabaseInfo -Tables @($script:categories, $script:subCategories, $script:products)
    }

    It 'follows outgoing dependencies when FullSearch is false' {
        $result = Get-SubsetGuardReachableTables `
            -DatabaseInfo $script:dbInfo `
            -SeedStates @((New-SeedState -TableName 'Products')) `
            -FullSearch $false

        $result | Should -Contain 'dbo, Products'
        $result | Should -Contain 'dbo, SubCategories'
        $result | Should -Contain 'dbo, Categories'
    }

    It 'does not follow incoming dependencies when FullSearch is false' {
        $result = Get-SubsetGuardReachableTables `
            -DatabaseInfo $script:dbInfo `
            -SeedStates @((New-SeedState -TableName 'Categories')) `
            -FullSearch $false

        $result | Should -Contain 'dbo, Categories'
        $result | Should -Not -Contain 'dbo, SubCategories'
        $result | Should -Not -Contain 'dbo, Products'
    }

    It 'follows incoming dependencies when FullSearch is true' {
        $result = Get-SubsetGuardReachableTables `
            -DatabaseInfo $script:dbInfo `
            -SeedStates @((New-SeedState -TableName 'Categories')) `
            -FullSearch $true

        $result | Should -Contain 'dbo, Categories'
        $result | Should -Contain 'dbo, SubCategories'
        $result | Should -Contain 'dbo, Products'
    }

    It 'honors ignored tables' {
        $ignored = New-Object TableInfo2
        $ignored.SchemaName = 'dbo'
        $ignored.TableName = 'SubCategories'

        $result = Get-SubsetGuardReachableTables `
            -DatabaseInfo $script:dbInfo `
            -SeedStates @((New-SeedState -TableName 'Products')) `
            -IgnoredTables @($ignored) `
            -FullSearch $false

        $result | Should -Contain 'dbo, Products'
        $result | Should -Not -Contain 'dbo, SubCategories'
        $result | Should -Not -Contain 'dbo, Categories'
    }

    It 'honors IncludeFull without cascading it to discovered records' {
        $result = Get-SubsetGuardReachableTables `
            -DatabaseInfo $script:dbInfo `
            -SeedStates @((New-SeedState -TableName 'Categories' -State ([TraversalState]::IncludeFull))) `
            -FullSearch $false

        $result | Should -Contain 'dbo, Categories'
        $result | Should -Contain 'dbo, SubCategories'
        $result | Should -Not -Contain 'dbo, Products'
    }
}

Describe 'Subset size guard threshold math' {
    It 'does not exceed runtime threshold below the configured percentage' {
        $result = New-SubsetGuardRuntimeResult `
            -SubsetRows 10 `
            -SourceRows 100 `
            -MaxSubsetPercentOfSource 20

        $result.PercentOfSourceRows | Should -Be 10
        $result.Exceeded | Should -Be $false
    }

    It 'exceeds runtime threshold above the configured percentage' {
        $result = New-SubsetGuardRuntimeResult `
            -SubsetRows 25 `
            -SourceRows 100 `
            -MaxSubsetPercentOfSource 20

        $result.PercentOfSourceRows | Should -Be 25
        $result.Exceeded | Should -Be $true
    }

    It 'disables runtime threshold when configured as zero' {
        $result = New-SubsetGuardRuntimeResult `
            -SubsetRows 100 `
            -SourceRows 100 `
            -MaxSubsetPercentOfSource 0

        $result.Enabled | Should -Be $false
        $result.Exceeded | Should -Be $false
    }

    It 'does not exceed runtime threshold when source rows are zero' {
        $result = New-SubsetGuardRuntimeResult `
            -SubsetRows 1 `
            -SourceRows 0 `
            -MaxSubsetPercentOfSource 20

        $result.PercentOfSourceRows | Should -BeNullOrEmpty
        $result.Exceeded | Should -Be $false
    }

    It 'throws when runtime threshold is exceeded and error mode is requested' {
        $runtime = New-SubsetGuardRuntimeResult `
            -SubsetRows 25 `
            -SourceRows 100 `
            -MaxSubsetPercentOfSource 20

        { Throw-SubsetGuardRuntimeError -Runtime $runtime } | Should -Throw
    }

    It 'does not throw when runtime threshold is not exceeded' {
        $runtime = New-SubsetGuardRuntimeResult `
            -SubsetRows 10 `
            -SourceRows 100 `
            -MaxSubsetPercentOfSource 20

        { Throw-SubsetGuardRuntimeError -Runtime $runtime } | Should -Not -Throw
    }

    It 'flags missing statistics in preflight estimates' {
        $withStats = New-GuardTable -TableName 'WithStats' -Rows 10
        $withoutStats = New-GuardTable -TableName 'WithoutStats' -Rows $null
        $info = New-GuardDatabaseInfo -Tables @($withStats, $withoutStats)
        $metrics = Get-SubsetGuardTableMetrics -DatabaseInfo $info

        $result = New-SubsetGuardPreflightResult `
            -ReachableTableKeys @('dbo, WithStats', 'dbo, WithoutStats') `
            -TableMetrics $metrics `
            -MaxReachableTablePercent 80

        $result.MissingStatistics | Should -Be $true
        $result.SourceRowsAvailable | Should -Be $false
        $result.ReachableSourceRows | Should -BeNullOrEmpty
    }

    It 'disables preflight threshold when configured as zero' {
        $table = New-GuardTable -TableName 'OnlyTable' -Rows 10
        $info = New-GuardDatabaseInfo -Tables @($table)
        $metrics = Get-SubsetGuardTableMetrics -DatabaseInfo $info

        $result = New-SubsetGuardPreflightResult `
            -ReachableTableKeys @('dbo, OnlyTable') `
            -TableMetrics $metrics `
            -MaxReachableTablePercent 0

        $result.Enabled | Should -Be $false
        $result.Exceeded | Should -Be $false
    }
}
