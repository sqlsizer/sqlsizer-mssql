## Example that show to import JSON from previously exported JSON 

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
$sessionId = Start-SqlSizerSession -Database $database -ConnectionInfo $connection -DatabaseInfo $info -ForceInstallation $true

# Define start set
# Query 1: All persons with first name = 'Michael'
$query = New-Object -TypeName Query2
$query.State = [TraversalState]::Include  # Use modern TraversalState enum for forward traversal
$query.Schema = "Person"
$query.Table = "Person"
$query.KeyColumns = @('BusinessEntityID')
$query.Where = "[`$table].FirstName <> 'Michael'"

Initialize-StartSet -Database $database -ConnectionInfo $connection -Queries @($query) -DatabaseInfo $info -SessionId $sessionId
# Use refactored algorithm for forward subset finding
Find-Subset -Database $database -ConnectionInfo $connection -DatabaseInfo $info -IgnoredTables @($ignored) -SessionId $sessionId

$json = Get-SubsetTableJson -Database $database -ConnectionInfo $connection -SchemaName "Person" -TableName "Password" -DatabaseInfo $info -Secure $false -SessionId $sessionId

Remove-Table -Database $database -SchemaName "Person3" -TableName "Password" -DatabaseInfo $info -ConnectionInfo $connection
New-DataTableClone -ConnectionInfo $connection -CopyData $false -DatabaseInfo $info -SourceDatabase $database -TargetDatabase $database -SchemaName "Person" -TableName "Password" -NewSchemaName "Person3" -NewTableName "Password"
Update-DatabaseInfo -DatabaseInfo $info -Database $database -ConnectionInfo $connection

Import-TableJson -Json $json -Database $database -SchemaName "Person3" -TableName "Password" -DatabaseInfo $info -ConnectionInfo $connection
# end of script
