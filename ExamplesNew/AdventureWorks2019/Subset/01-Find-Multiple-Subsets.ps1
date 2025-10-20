## Example that shows how to find two subsets

# Connection settings
$server = "localhost"
$database = "AdventureWorks2019"
$username = "someuser"
$password = ConvertTo-SecureString -String "pass" -AsPlainText -Force

# Create connection
$connection = New-SqlConnectionInfo -Server $server -Username $username -Password $password

# Get database info
$info = Get-DatabaseInfo -Database $database -ConnectionInfo $connection

# Create sessions
$sessionId = Start-SqlSizerSession -Database $database -ConnectionInfo $connection -DatabaseInfo $info
$sessionId2 = Start-SqlSizerSession -Database $database -ConnectionInfo $connection -DatabaseInfo $info

# Find subset
# Query 1: top 100 persons with peron types EM
$query = New-Object -TypeName Query2
$query.State = [TraversalState]::Include  # Use modern TraversalState enum for forward traversal
$query.Schema = "Person"
$query.Table = "Person"
$query.KeyColumns = @('BusinessEntityID')
$query.Where = "[`$table].PersonType = 'EM'"
$query.Top = 100

Initialize-StartSet-Refactored -Database $database -ConnectionInfo $connection -Queries @($query) -DatabaseInfo $info -SessionId $sessionId
# Use refactored algorithm for forward subset finding
Find-Subset-Refactored -Database $database -ConnectionInfo $connection -DatabaseInfo $info -SessionId $sessionId
$subset1 = Get-SubsetTables -Database $database -ConnectionInfo $connection -DatabaseInfo $info -SessionId $sessionId

# Query 2: All persons with first name = 'Wanida'
$query2 = New-Object -TypeName Query2
$query2.State = [TraversalState]::Include  # Use modern TraversalState enum for forward traversal
$query2.Schema = "Person"
$query2.Table = "Person"
$query2.KeyColumns = @('BusinessEntityID')
$query2.Where = "[`$table].FirstName = 'Wanida'"

Initialize-StartSet-Refactored -Database $database -ConnectionInfo $connection -Queries @($query2) -DatabaseInfo $info -SessionId $sessionId2
# Use refactored algorithm for forward subset finding
Find-Subset-Refactored -Database $database -ConnectionInfo $connection -DatabaseInfo $info -SessionId $sessionId2
$subset2 = Get-SubsetTables -Database $database -ConnectionInfo $connection -DatabaseInfo $info -SessionId $sessionId2

# end of script
