## Advanced example showing Find-Subset with TraversalConfiguration rules

# Load the local module manifest so SqlSizer classes/enums are available to this script.
$modulePath = Join-Path $PSScriptRoot "..\..\..\SqlSizer-MSSQL\SqlSizer-MSSQL.psd1"
Import-Module $modulePath -Force -Global

# Load the local module manifest so SqlSizer classes/enums are available to this script.
$modulePath = Join-Path $PSScriptRoot "..\..\..\SqlSizer-MSSQL\SqlSizer-MSSQL.psd1"
Import-Module $modulePath -Force -Global

# Connection settings
$server = "localhost"
$database = "AdventureWorks2019"
$username = "someuser"
$password = ConvertTo-SecureString -String "pass" -AsPlainText -Force

# 1. Create connection
$connection = New-SqlConnectionInfo -Server $server -Username $username -Password $password

# 2. Get database metadata
$info = Get-DatabaseInfo -Database $database -ConnectionInfo $connection

# 3. Create a session to track this subset operation
$sessionId = Start-SqlSizerSession -Database $database -ConnectionInfo $connection `
    -DatabaseInfo $info -ForceInstallation $true

# 4. Define deterministic seed records from Sales.SalesOrderDetail.
# This starts from one known order and lets the rules below shape the closure.
$query = New-Object -TypeName SqlSizerQuery
$query.State = [TraversalState]::Include
$query.Schema = "Sales"
$query.Table = "SalesOrderDetail"
$query.KeyColumns = @("SalesOrderID", "SalesOrderDetailID")
$query.Where = "[`$table].SalesOrderID = 43659"
$query.Top = 5
$query.OrderBy = "[`$table].SalesOrderDetailID ASC"

# 5. Build advanced traversal rules.
$config = New-Object -Type TraversalConfiguration

# Skip tables that are not useful in this focused subset.
$null = $config.AddIgnoredTable("Sales", "SalesOrderHeaderSalesReason")
$null = $config.AddIgnoredTable("Production", "TransactionHistory")

# When SalesOrderHeader is reached from the order detail seed, make that table a local
# full-closure point. This pulls selected incoming dependents without turning on
# FullSearch for the whole database.
$salesOrderHeaderRule = New-Object -Type TraversalRule -ArgumentList "Sales", "SalesOrderHeader"
$null = $salesOrderHeaderRule.SetStateOverride([TraversalState]::IncludeFull)
$null = $config.AddRule($salesOrderHeaderRule)

# To make this conditional instead of applying IncludeFull to every header, replace
# the unfiltered rule above with ordered filtered/fallback rules like these.
# $onlineHeaderRule = New-Object -Type TraversalRule -ArgumentList "Sales", "SalesOrderHeader"
# $null = $onlineHeaderRule.SetFilter("[`$table].[OnlineOrderFlag] = 1").SetStateOverride([TraversalState]::IncludeFull)
# $null = $config.AddRule($onlineHeaderRule)
# $otherHeaderRule = New-Object -Type TraversalRule -ArgumentList "Sales", "SalesOrderHeader"
# $null = $otherHeaderRule.SetStateOverride([TraversalState]::Include)
# $null = $config.AddRule($otherHeaderRule)

# SalesOrderHeader can fan out to many SalesOrderDetail rows through incoming traversal.
# Keep the example small and deterministic.
$salesOrderDetailRule = New-Object -Type TraversalRule -ArgumentList "Sales", "SalesOrderDetail"
$null = $salesOrderDetailRule.SetTop(25)
$null = $config.AddRule($salesOrderDetailRule)

# Demonstrate relationship filtering. For Person.Address, follow only the ship-to
# relationship from Sales.SalesOrderHeader. If billing and shipping addresses can differ
# and you plan to copy the subset, remove the FK filter so both address paths are kept.
$shipToAddressRule = New-Object -Type TraversalRule -ArgumentList "Person", "Address"
$null = $shipToAddressRule.SetSourceFilter("Sales", "SalesOrderHeader")
$null = $shipToAddressRule.SetForeignKeyFilter("FK_SalesOrderHeader_Address_ShipToAddressID")
$null = $config.AddRule($shipToAddressRule)

# Stop before the last address lookup hop. Address -> StateProvince is kept, but
# StateProvince -> CountryRegion is not traversed in this example.
$countryRegionRule = New-Object -Type TraversalRule -ArgumentList "Person", "CountryRegion"
$null = $countryRegionRule.SetMaxDepth(0)
$null = $config.AddRule($countryRegionRule)

# 6. Initialize the starting set with your query
Initialize-StartSet -Database $database -ConnectionInfo $connection `
    -Queries @($query) -DatabaseInfo $info -SessionId $sessionId

# 7. Find the subset using the advanced TraversalConfiguration
$result = Find-Subset -Database $database -ConnectionInfo $connection `
    -DatabaseInfo $info -SessionId $sessionId `
    -TraversalConfiguration $config -FullSearch $false -UseDfs $false

Write-Host "Find-Subset completed: Finished=$($result.Finished), CompletedIterations=$($result.CompletedIterations)" -ForegroundColor Green

# 8. Print the resulting subset tables
$subsetTables = Get-SubsetTables -Database $database -ConnectionInfo $connection `
    -DatabaseInfo $info -SessionId $sessionId

Write-Host "`nSubset tables:" -ForegroundColor Green
$subsetTables |
    Sort-Object SchemaName, TableName |
    Format-Table SchemaName, TableName, RowCount -AutoSize

# 9. Print an impact summary so you can see how the rules changed traversal
$report = Get-SubsetImpactReport -Database $database -ConnectionInfo $connection `
    -DatabaseInfo $info -SessionId $sessionId

Write-Host "`nImpact summary:" -ForegroundColor Green
$report.Summary |
    Select-Object TableCount, TotalRows, RelationshipsReached, RelationshipsUnreached, OperationsComplete |
    Format-List

Write-Host "Unreached relationships caused by filters, depth limits, or ignored tables:" -ForegroundColor Yellow
$report.Relationships.Unreached |
    Select-Object -First 15 Name, FromSchema, FromTable, ToSchema, ToTable |
    Format-Table -AutoSize

# Keep the session so you can inspect it with Get-SubsetTables, Get-SubsetTableRows,
# Get-SubsetImpactReport, or Copy-DataFromSubset. Remove it when you are done:
# Clear-SqlSizerSession -Database $database -ConnectionInfo $connection -SessionId $sessionId
