## Example that shows how copy schema

# Connection settings
$server = "localhost"
$database = "AdventureWorks2019"
$username = "someuser"
$password = ConvertTo-SecureString -String "pass" -AsPlainText -Force

# Create connection
$connection = New-SqlConnectionInfo -Server $server -Username $username -Password $password

# Get database info
$info = Get-DatabaseInfo -Database $database -ConnectionInfo $connection

Remove-Schema -Database $database -ConnectionInfo $connection -SchemaName "Person6" -DatabaseInfo $info
$null = New-SchemaFromDatabase -SourceDatabase $database -TargetDatabase $database -ConnectionInfo $connection -SchemaName "Person" -NewSchemaName "Person6" -CopyData $false -DatabaseInfo $info

# end of script
