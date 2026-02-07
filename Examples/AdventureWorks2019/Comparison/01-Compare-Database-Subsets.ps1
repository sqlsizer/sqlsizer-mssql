## Example that shows how to save and compare subsets

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
$sessionId2 = Start-SqlSizerSession -Database $database -ConnectionInfo $connection -DatabaseInfo $info

# Define start set
$query = New-Object -TypeName Query2
$query.State = [TraversalState]::Include  # Use modern TraversalState enum for forward traversal
$query.Schema = "Person"
$query.Table = "Person"
$query.KeyColumns = @('BusinessEntityID')
$query.Where = "[`$table].FirstName = 'Rob'"

Initialize-StartSet-Refactored -Database $database -ConnectionInfo $connection -Queries @($query) -DatabaseInfo $info -SessionId $sessionId

# Find subset using refactored algorithm
Find-Subset-Refactored -Database $database -ConnectionInfo $connection -DatabaseInfo $info -FullSearch $false -SessionId $sessionId
$subsetGuid = Save-Subset -Database $database -ConnectionInfo $connection -SubsetName "Subset_from_example_17" -DatabaseInfo $info -SessionId $sessionId

Disable-ForeignKeys -Database $database -ConnectionInfo $connection -DatabaseInfo $info
Disable-AllTablesTriggers -Database $database -ConnectionInfo $connection -DatabaseInfo $info

Remove-FoundSubsetFromDatabase -Database $database -ConnectionInfo $connection -DatabaseInfo $info -SessionId $sessionId

# Test foreign keys
Test-ForeignKeys -Database $database -ConnectionInfo $connection -DatabaseInfo $info

Enable-ForeignKeys -Database $database -ConnectionInfo $connection -DatabaseInfo $info
Enable-AllTablesTriggers -Database $database -ConnectionInfo $connection -DatabaseInfo $info

# Use refactored algorithm for forward subset finding
Find-Subset-Refactored -Database $database -ConnectionInfo $connection -IgnoredTables @($ignored) -DatabaseInfo $info  -FullSearch $false -SessionId $sessionId2
$subsetGuid2 = Save-Subset -Database $database -ConnectionInfo $connection -SubsetName "Subset_from_example_17_after_little_change" -DatabaseInfo $info -SessionId $sessionId2

$compareResult = Compare-SavedSubsets -SourceDatabase $database -TargetDatabase $database -SourceSubsetGuid $subsetGuid -TargetSubsetGuid $subsetGuid2 -ConnectionInfo $connection

$compareResult

