## Example that shows how to check which tables are reachable by queries and traversal configuration

# Connection settings
$server = "localhost"
$database = "AdventureWorks2019"
$username = "someuser"
$password = ConvertTo-SecureString -String "pass" -AsPlainText -Force

# Create connection
$connection = New-SqlConnectionInfo -Server $server -Username $username -Password $password
$info = Get-DatabaseInfo -Database $database -ConnectionInfo $connection

# Query 1: All persons with first name = 'Michael'
$query = New-Object -TypeName SqlSizerQuery
$query.State = [TraversalState]::Include  # Seed rows for the subset closure
$query.Schema = "Person"
$query.Table = "Person"
$query.KeyColumns = @('BusinessEntityID')
$query.Where = "[`$table].FirstName = 'Michael'"

# Define traversal configuration using modern API
$config = New-Object -Type TraversalConfiguration

$rule = New-Object -Type TraversalRule -ArgumentList "Person", "Address"
# Use IncludeFull when a table should expand through incoming and outgoing FKs.
$rule.StateOverride = New-Object -Type StateOverride -ArgumentList ([TraversalState]::IncludeFull)
$config.Rules += $rule

$null = Test-Queries -Database $database -ConnectionInfo $connection -Queries @($query) -DatabaseInfo $info -TraversalConfiguration $config

# end of script
