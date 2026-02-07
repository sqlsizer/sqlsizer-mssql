## Example that shows how to find data needed to remove desired data

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
# Query 1: All persons with first name = 'Michael'
$query = New-Object -TypeName Query2
$query.State = [TraversalState]::InboundOnly  # Use modern TraversalState enum for removal/incoming FK traversal
$query.Schema = "Person"
$query.Table = "Person"
$query.KeyColumns = @('BusinessEntityID')
$query.Where = "[`$table].FirstName = 'Michael'"

$ignored = New-Object -Type TableInfo2
$ignored.SchemaName = "Sales"
$ignored.TableName = "Store"

Initialize-StartSet-Refactored -Database $database -ConnectionInfo $connection -Queries @($query) -DatabaseInfo $info -SessionId $sessionId

# Use the refactored removal subset algorithm (cleaner, more efficient)
$null = Find-RemovalSubset-Refactored -Database $database -ConnectionInfo $connection -DatabaseInfo $info -SessionId $sessionId

Get-SubsetTables -Database $database -Connection $connection -DatabaseInfo $info -SessionId $sessionId
Get-SubsetHashSummary -Database $database -Connection $connection -SessionId $sessionId
Get-SubsetTableStatistics -Database $database -Connection $connection -DatabaseInfo $info -SessionId $sessionId

Get-SubsetTableRows -Database $database -Connection $connection -DatabaseInfo $info -SessionId $sessionId -Iteration 0 -TableName "Person" -SchemaName "Person"


# end of script
