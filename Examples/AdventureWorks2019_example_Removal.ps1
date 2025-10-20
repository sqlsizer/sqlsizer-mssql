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
$query = New-Object -TypeName Query
$query.Color = [Color]::Blue
$query.Schema = "Person"
$query.Table = "Person"
$query.KeyColumns = @('BusinessEntityID')
$query.Where = "[`$table].FirstName = 'Michael'"

$ignored = New-Object -Type TableInfo2
$ignored.SchemaName = "Sales"
$ignored.TableName = "Store"

Initialize-StartSet -Database $database -ConnectionInfo $connection -Queries @($query) -DatabaseInfo $info -SessionId $sessionId
$null = Find-Subset -Database $database -ConnectionInfo $connection -DatabaseInfo $info -IgnoredTables @($ignored) -SessionId $sessionId

Get-SubsetTables -Database $database -Connection $connection -DatabaseInfo $info -SessionId $sessionId
Get-SubsetHashSummary -Database $database -Connection $connection -SessionId $sessionId
Get-SubsetTableStatistics -Database $database -Connection $connection -DatabaseInfo $info -SessionId $sessionId

Get-SubsetTableRows -Database $database -Connection $connection -DatabaseInfo $info -SessionId $sessionId -Iteration 0 -TableName "Person" -SchemaName "Person"


# end of script
