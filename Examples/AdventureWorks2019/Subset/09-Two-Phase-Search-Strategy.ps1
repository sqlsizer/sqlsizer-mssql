## Example that shows how to run two phase search
## Use case: Remove some GDPR data (e.g. Person.Address data for people with last name 'Adams')

# Connection settings
$server = "localhost"
$database = "AdventureWorks2019"
$username = "someuser"
$password = ConvertTo-SecureString -String "pass" -AsPlainText -Force

# Create connection
$connection = New-SqlConnectionInfo -Server $server -Username $username -Password $password

# Get database info
$info = Get-DatabaseInfo -Database $database -ConnectionInfo $connection

# Phase 1
$sessionId = Start-SqlSizerSession -Database $database -ConnectionInfo $connection -DatabaseInfo $info -ForceInstallation $true
$query = New-Object -TypeName Query2
$query.State = [TraversalState]::Include  # Use modern TraversalState enum for forward traversal
$query.Schema = "Person"
$query.Table = "Person"
$query.KeyColumns = @('BusinessEntityID')
$query.Where = "[`$table].LastName = 'Adams'"
$query.OrderBy = "[`$table].LastName ASC"

# Define traversal configuration using modern API (empty for Phase 1 - no special rules)
$config = New-Object -Type TraversalConfiguration

Initialize-StartSet -Database $database -ConnectionInfo $connection -Queries @($query) -DatabaseInfo $info -SessionId $sessionId
# Phase 1: Use Find-Subset for forward traversal (Pending state for forward traversal)
$null = Find-Subset -Database $database -ConnectionInfo $connection -DatabaseInfo $info -FullSearch $false -UseDfs $false -SessionId $sessionId -TraversalConfiguration $config

# Phase 2
$sessionId2 = Start-SqlSizerSession -Database $database -ConnectionInfo $connection -DatabaseInfo $info
$query = New-Object -TypeName Query2
$query.Schema = "Person"
$query.Table = "Address"
$query.State = [TraversalState]::InboundOnly  # Use modern TraversalState enum for removal traversal
$query.KeyColumns = @('AddressID')
$query.Where = "[`$table].AddressID IN (SELECT AddressID FROM SqlSizer_$($sessionId).Result_Person_Address)"

Initialize-StartSet -Database $database -ConnectionInfo $connection -Queries @($query) -DatabaseInfo $info -SessionId $sessionId2
# Phase 2: Use Find-RemovalSubset for removal traversal (Blue = InboundOnly)
$null = Find-RemovalSubset -Database $database -ConnectionInfo $connection -DatabaseInfo $info -SessionId $sessionId2

Remove-FoundSubsetFromDatabase -Database $database -ConnectionInfo $connection -DatabaseInfo $info -Step 100000 -SessionId $sessionId2
