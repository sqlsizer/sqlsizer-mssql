<#
.SYNOPSIS
    Unit tests for Subset Impact Report helpers.
#>

BeforeAll {
    $modulePath = Split-Path -Parent $PSScriptRoot
    Import-Module "$modulePath\SqlSizer-MSSQL\SqlSizer-MSSQL" -Force -Global
    . "$modulePath\SqlSizer-MSSQL\Shared\SubsetImpactReportHelpers.ps1"

    function New-SyntheticSubsetImpactReport {
        $summary = [pscustomobject]@{
            Database               = 'SyntheticDb'
            SessionId              = 'SESSION_123'
            GeneratedAt            = '2026-04-29T20:00:00.0000000Z'
            TableCount             = 2
            TotalRows              = 15
            SourceRows             = 1500
            PercentOfSourceRows    = 1.0
            EstimatedDataKB        = 42.5
            RelationshipsReached   = 1
            RelationshipsUnreached = 1
            OperationsComplete     = $true
        }

        $tables = @(
            [pscustomobject]@{
                SchemaName          = 'dbo'
                TableName           = 'Orders'
                SubsetRows          = 10
                SourceRows          = 1000
                PercentOfSourceRows = 1.0
                PrimaryKeySize      = 1
                CanBeDeleted        = $true
                IsHistoric          = $false
                EstimatedDataKB     = 25.0
            },
            [pscustomobject]@{
                SchemaName          = 'dbo'
                TableName           = 'Customers'
                SubsetRows          = 5
                SourceRows          = 500
                PercentOfSourceRows = 1.0
                PrimaryKeySize      = 1
                CanBeDeleted        = $true
                IsHistoric          = $false
                EstimatedDataKB     = 17.5
            }
        )

        $relationships = [pscustomobject]@{
            Reached = @(
                [pscustomobject]@{
                    Id         = 1
                    Name       = 'FK_Orders_Customers'
                    FromSchema = 'dbo'
                    FromTable  = 'Orders'
                    ToSchema   = 'dbo'
                    ToTable    = 'Customers'
                    IsReached  = $true
                }
            )
            Unreached = @(
                [pscustomobject]@{
                    Id         = 2
                    Name       = 'FK_Orders_Optional|Escaped'
                    FromSchema = 'dbo'
                    FromTable  = 'Orders'
                    ToSchema   = 'dbo'
                    ToTable    = 'Optional'
                    IsReached  = $false
                }
            )
            All = @()
        }

        $operations = [pscustomobject]@{
            Summary = [pscustomobject]@{
                TotalOperations       = 3
                CompletedOperations   = 3
                TotalRecordsProcessed = 15
                TotalRecordsRemaining = 0
                MaxDepthReached       = 2
                StartedAt             = '2026-04-29T19:59:00'
                LastProcessedAt       = '2026-04-29T20:00:00'
            }
            ByStateAndDepth = @(
                [pscustomobject]@{
                    State            = 'Include'
                    StateValue       = 1
                    Depth            = 0
                    OperationCount   = 1
                    RecordsToProcess = 10
                    RecordsProcessed = 10
                    RecordsRemaining = 0
                },
                [pscustomobject]@{
                    State            = 'Include'
                    StateValue       = 1
                    Depth            = 1
                    OperationCount   = 2
                    RecordsToProcess = 5
                    RecordsProcessed = 5
                    RecordsRemaining = 0
                }
            )
        }

        return New-SubsetImpactReportObject `
            -Summary $summary `
            -Tables $tables `
            -Relationships $relationships `
            -Operations $operations `
            -Warnings @('Synthetic <warning>')
    }
}

Describe 'New-SubsetImpactReportObject' {
    It 'Creates the expected top-level report shape' {
        $report = New-SyntheticSubsetImpactReport

        $report.PSObject.Properties.Name | Should -Contain 'Summary'
        $report.PSObject.Properties.Name | Should -Contain 'Tables'
        $report.PSObject.Properties.Name | Should -Contain 'Relationships'
        $report.PSObject.Properties.Name | Should -Contain 'Operations'
        $report.PSObject.Properties.Name | Should -Contain 'Warnings'
        $report.Tables.Count | Should -Be 2
        $report.Relationships.Reached.Count | Should -Be 1
    }
}

Describe 'ConvertTo-SubsetImpactReportMarkdown' {
    It 'Renders summary, tables, relationships, operations, and warnings' {
        $markdown = ConvertTo-SubsetImpactReportMarkdown -Report (New-SyntheticSubsetImpactReport)

        $markdown | Should -Match '# SqlSizer Subset Impact Report'
        $markdown | Should -Match 'SyntheticDb'
        $markdown | Should -Match 'dbo\.Orders'
        $markdown | Should -Match 'FK_Orders_Customers'
        $markdown | Should -Match 'Include'
        $markdown | Should -Match 'Synthetic <warning>'
    }

    It 'Escapes markdown table pipes' {
        $markdown = ConvertTo-SubsetImpactReportMarkdown -Report (New-SyntheticSubsetImpactReport)

        $markdown | Should -Match 'FK_Orders_Optional\\\|Escaped'
    }
}

Describe 'ConvertTo-SubsetImpactReportHtml' {
    It 'Renders an HTML document with escaped content' {
        $html = ConvertTo-SubsetImpactReportHtml -Report (New-SyntheticSubsetImpactReport)

        $html | Should -Match '<!doctype html>'
        $html | Should -Match 'SqlSizer Subset Impact Report'
        $html | Should -Match 'dbo\.Customers'
        $html | Should -Match 'Synthetic &lt;warning&gt;'
    }
}

Describe 'JSON serialization' {
    It 'Serializes and deserializes report shape with depth 10' {
        $json = New-SyntheticSubsetImpactReport | ConvertTo-Json -Depth 10
        $roundTripped = $json | ConvertFrom-Json

        $roundTripped.Summary.Database | Should -Be 'SyntheticDb'
        $roundTripped.Tables.Count | Should -Be 2
        $roundTripped.Relationships.Reached[0].Name | Should -Be 'FK_Orders_Customers'
        $roundTripped.Operations.ByStateAndDepth.Count | Should -Be 2
    }
}
