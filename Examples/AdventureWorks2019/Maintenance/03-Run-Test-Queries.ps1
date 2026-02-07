## Example that shows how to check which tables are reachable by queries and color map

# Connection settings
$server = "localhost"
$database = "AdventureWorks2019"
$username = "someuser"
$password = ConvertTo-SecureString -String "pass" -AsPlainText -Force

# Create connection
$connection = New-SqlConnectionInfo -Server $server -Username $username -Password $password
$info = Get-DatabaseInfo -Database $database -ConnectionInfo $connection

# Query 1: All persons with first name = 'Michael'
$query = New-Object -TypeName Query2
$query.State = [TraversalState]::Include  # Use modern TraversalState enum for forward traversal
$query.Schema = "Person"
$query.Table = "Person"
$query.KeyColumns = @('BusinessEntityID')
$query.Where = "[`$table].FirstName = 'Michael'"

# Define traversal configuration using modern API
$config = New-Object -Type TraversalConfiguration

$rule = New-Object -Type TraversalRule -ArgumentList "Person", "Address"
# Use StateOverride instead of ForcedColor for modern configuration
# Bidirectional traversal (was Purple in legacy)
$rule.StateOverride = New-Object -Type StateOverride -ArgumentList ([TraversalState]::Bidirectional)
$config.Rules += $rule

$null = Test-Queries -Database $database -ConnectionInfo $connection -Queries @($query) -DatabaseInfo $info -TraversalConfiguration $config

# end of script
