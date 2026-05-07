## Example that shows how to create a new database with a subset of data using TraversalConfiguration

# Load the local module manifest so SqlSizer classes/enums are available to this script.
$modulePath = Join-Path $PSScriptRoot "..\..\..\SqlSizer-MSSQL\SqlSizer-MSSQL.psd1"
Import-Module $modulePath -Force -Global

# Connection settings
$server = "localhost"
$database = "AdventureWorks2019"
$username = "someuser"
$password = ConvertTo-SecureString -String "pass" -AsPlainText -Force

# Create connection
$connection = New-SqlConnectionInfo -Server $server -Username $username -Password $password

# Get database info
$info = Get-DatabaseInfo -Database $database -ConnectionInfo $connection

# Start session
$sessionId = Start-SqlSizerSession -Database $database -ConnectionInfo $connection -DatabaseInfo $info

# Define start set

# Query 1: 10 persons with first name = 'John'
$query = New-Object -TypeName SqlSizerQuery
$query.State = [TraversalState]::Include  # Seed rows for the subset closure
$query.Schema = "Person"
$query.Table = "Person"
$query.KeyColumns = @('BusinessEntityID')
$query.Where = "[`$table].FirstName = 'John'"
$query.Top = 10
$query.OrderBy = "[`$table].LastName ASC"

# Define traversal configuration using modern API
$config = New-Object -Type TraversalConfiguration

foreach ($table in $info.Tables)
{
    $rule = New-Object -Type TraversalRule -ArgumentList $table.SchemaName, $table.TableName

    if ($table.TableName -in @('Person'))
    {
        # Use IncludeFull when this table should expand as a per-table full closure.
        $rule.SetStateOverride([TraversalState]::IncludeFull)
    }

    # Use TraversalConstraints instead of Condition for modern configuration
    # Old way:
    # $rule.Constraints = New-Object -Type TraversalConstraints
    # $rule.Constraints.Top = 10
    
    # New convenient way:
    $rule.SetTop(10) # limit all dependent data for each fk by 10 rows (it doesn't mean that there will be no more rows!)
    $config.AddRule($rule)
}

# Optionally, configure ignored tables to exclude from traversal (modern alternative to separate IgnoredTables parameter)
# Fluent interface example:
# $config.AddIgnoredTable("dbo", "AuditLog").AddIgnoredTable("dbo", "ErrorLog")
# Or set multiple at once:
# $config.SetIgnoredTables(@(
#     New-Object -Type TableInfo2 -Property @{SchemaName="dbo"; TableName="AuditLog"},
#     New-Object -Type TableInfo2 -Property @{SchemaName="dbo"; TableName="ErrorLog"}
# ))

# You can also set constraints on rules easily:
# $rule.SetMaxDepth(3).SetSourceFilter("Sales", "Orders").SetForeignKeyFilter("FK_OrderDetails_Orders")

# ===== NEW FLUENT API EXAMPLES =====
# The modern API provides convenience methods and fluent interfaces for easier configuration:

# Example configurations using the new fluent API:

# Example 1: Simple ignored tables
# $config.AddIgnoredTable("dbo", "AuditLog").AddIgnoredTable("dbo", "ErrorLog")

# Example 2: Complex rule with multiple constraints
# $rule = New-Object TraversalRule -ArgumentList "Sales", "Orders"
# $rule.SetStateOverride([TraversalState]::Include).SetTop(100).SetMaxDepth(2)
# $config.AddRule($rule)

# Example 3: Rule with source filtering
# $rule = New-Object TraversalRule -ArgumentList "Sales", "OrderDetails" 
# $rule.SetSourceFilter("Sales", "Orders").SetTop(50)
# $config.AddRule($rule)

# Example 4: Bulk ignored tables setup
# $config.SetIgnoredTables(@(
#     New-Object TableInfo2 -Property @{SchemaName="dbo"; TableName="AuditLog"},
#     New-Object TableInfo2 -Property @{SchemaName="dbo"; TableName="Settings"}
# ))

# Example 5: Chained configuration
# $config.AddIgnoredTable("dbo", "Logs").
#         AddRule((New-Object TraversalRule -ArgumentList "Sales", "Customers").SetTop(10)).
#         AddRule((New-Object TraversalRule -ArgumentList "Sales", "Orders").SetMaxDepth(3).SetStateOverride([TraversalState]::IncludeFull))

Initialize-StartSet -Database $database -ConnectionInfo $connection -Queries @($query) -DatabaseInfo $info -SessionId $sessionId

# Find subset using the closure engine with modern TraversalConfiguration
Find-Subset -Database $database -ConnectionInfo $connection -DatabaseInfo $info -TraversalConfiguration $config -UseDfs $true -SessionId $sessionId

# Get subset info
Get-SubsetTables -Database $database -ConnectionInfo $connection -DatabaseInfo $info -SessionId $sessionId

# Create a new db with found subset of data

$newDatabase = "AdventureWorks2019_subset_07"
Copy-Database -Database $database -NewDatabase $newDatabase -ConnectionInfo $connection
$infoNew = Get-DatabaseInfo -Database $newDatabase -ConnectionInfo $connection

Disable-ForeignKeys -Database $newDatabase -ConnectionInfo $connection -DatabaseInfo $infoNew
Disable-AllTablesTriggers -Database $newDatabase -ConnectionInfo $connection -DatabaseInfo $infoNew

Clear-Database -Database $newDatabase -ConnectionInfo $connection -DatabaseInfo $infoNew
Copy-DataFromSubset -Source $database -Destination  $newDatabase -ConnectionInfo $connection -DatabaseInfo $info -SessionId $sessionId
Enable-ForeignKeys -Database $newDatabase -ConnectionInfo $connection -DatabaseInfo $infoNew
Enable-AllTablesTriggers -Database $newDatabase -ConnectionInfo $connection -DatabaseInfo $infoNew

Format-Indexes -Database $newDatabase -ConnectionInfo $connection -DatabaseInfo $infoNew
Uninstall-SqlSizer -Database $newDatabase -ConnectionInfo $connection -DatabaseInfo $infoNew
Compress-Database -Database $newDatabase -ConnectionInfo $connection

Test-ForeignKeys -Database $newDatabase -ConnectionInfo $connection -DatabaseInfo $infoNew

$infoNew = Get-DatabaseInfo -Database $newDatabase -ConnectionInfo $connection -MeasureSize $true

Write-Verbose "Subset size: $($infoNew.DatabaseSize)"
$sum = 0
foreach ($table in $infoNew.Tables)
{
    $sum += $table.Statistics.Rows
}

Write-Verbose "Total rows: $($sum)"

# end of script
