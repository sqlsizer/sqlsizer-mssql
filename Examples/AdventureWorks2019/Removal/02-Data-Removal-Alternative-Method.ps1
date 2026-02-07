## Another example that shows how to find data needed to remove initial data set

# Connection settings
$server = "localhost"
$database = "AdventureWorks2019"
$username = "someuser"
$password = ConvertTo-SecureString -String "pass" -AsPlainText -Force

# Create connection
$connection = New-SqlConnectionInfo -Server $server -Username $username -Password $password

# Get database info
$info = Get-DatabaseInfo -Database $database -ConnectionInfo $connection

# Create session id
$sessionId = Start-SqlSizerSession -Database $database -ConnectionInfo $connection -DatabaseInfo $info

# Install SqlSizer
Install-SqlSizer -Database $database -ConnectionInfo $connection -DatabaseInfo $info

# Define start set
# Query 1: All persons with first name = 'Rob'
$query = New-Object -TypeName Query2
$query.State = [TraversalState]::InboundOnly  # Use modern TraversalState enum for removal/incoming FK traversal
$query.Schema = "Person"
$query.Table = "Person"
$query.KeyColumns = @('BusinessEntityID')
$query.Where = "[`$table].FirstName = 'Rob'"

Initialize-StartSet -Database $database -ConnectionInfo $connection -Queries @($query) -DatabaseInfo $info -SessionId $sessionId

# Use the refactored removal subset algorithm (cleaner, more efficient)
Find-RemovalSubset -Database $database -ConnectionInfo $connection -DatabaseInfo $info -SessionId $sessionId

# end of script
