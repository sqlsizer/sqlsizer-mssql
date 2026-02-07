## Example that shows how to use multiple queries to remove complex data at once

## Persons with name 'Michael' will be removed from database
## Production products with SafetyStockLevel > 500 will be removed from database

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
$query = New-Object -TypeName Query2
$query.State = [TraversalState]::InboundOnly  # Use modern TraversalState enum for removal/incoming FK traversal
$query.Schema = "Person"
$query.Table = "Person"
$query.KeyColumns = @('BusinessEntityID')
$query.Where = "[`$table].FirstName = 'Michael'"

$query2 = New-Object -TypeName Query2
$query2.State = [TraversalState]::InboundOnly  # Use modern TraversalState enum for removal/incoming FK traversal
$query2.Schema = "Production"
$query2.Table = "Product"
$query2.KeyColumns = @('ProductID')
$query2.Where = "[`$table].SafetyStockLevel > 500"

# Init start set with data from query and query2 (multiple sources)
Initialize-StartSet -Database $database -ConnectionInfo $connection -Queries @($query, $query2) -DatabaseInfo $info -SessionId $sessionId

# Find removal subset - Blue = InboundOnly (find rows that must be removed first)
# Use the refactored algorithm (cleaner, more efficient, CTE-based queries)
Find-RemovalSubset -Database $database -ConnectionInfo $connection -DatabaseInfo $info -SessionId $sessionId

# Test foreign keys
Test-ForeignKeys -Database $database -ConnectionInfo $connection -DatabaseInfo $info

# Disable integrity checks and triggers
Disable-ForeignKeys -Database $database -ConnectionInfo $connection -DatabaseInfo $info
Disable-AllTablesTriggers -Database $database -ConnectionInfo $connection -DatabaseInfo $info

# Remove subset from database
Remove-FoundSubsetFromDatabase -Database $database -ConnectionInfo $connection -DatabaseInfo $info -Step 1000 -SessionId $sessionId

# Enable integrity checks and triggers
Enable-ForeignKeys -Database $database -ConnectionInfo $connection -DatabaseInfo $info
Enable-AllTablesTriggers -Database $database -ConnectionInfo $connection -DatabaseInfo $info

# Test foreign keys
Test-ForeignKeys -Database $database -ConnectionInfo $connection -DatabaseInfo $info

Write-Host "Following data has been removed:"
Get-SubsetTables -Database $database -Connection $connection -DatabaseInfo $info -SessionId $sessionId

