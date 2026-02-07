## Example that shows how compare two tables

# Connection settings
$server = "localhost"
$database = "AdventureWorks2019"
$username = "someuser"
$password = ConvertTo-SecureString -String "pass" -AsPlainText -Force

# Create connection
$connection = New-SqlConnectionInfo -Server $server -Username $username -Password $password

# Get database info
$info = Get-DatabaseInfo -Database $database -ConnectionInfo $connection

# New table clone
New-DataTableClone -ConnectionInfo $connection -CopyData $true -DatabaseInfo $info -SourceDatabase $database -TargetDatabase $database -SchemaName "Person" -TableName "Person" -NewSchemaName "Person2" -NewTableName "Persons"

# Remove some data from new table
$null = Invoke-SqlcmdEx -Sql "DELETE TOP (10) FROM Person2.Persons" -Database $Database -ConnectionInfo $connection

# Update some data on table
$null = Invoke-SqlcmdEx -Sql "UPDATE Person2.Persons SET FirstName = 'Name' WHERE FirstName = 'John'" -Database $Database -ConnectionInfo $connection

# Compare two tables
Compare-Tables -Database $database -SchemaName1 "Person" -SchemaName2 "Person2" -TableName1 "Person" -TableName2 "Persons" -ConnectionInfo $connection -DatabaseInfo $info

