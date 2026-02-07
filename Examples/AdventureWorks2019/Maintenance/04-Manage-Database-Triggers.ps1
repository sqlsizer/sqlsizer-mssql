## Example that shows how to get work with triggers

# Connection settings
$server = "localhost"
$database = "AdventureWorks2019"
$username = "someuser"
$password = ConvertTo-SecureString -String "pass" -AsPlainText -Force

# Create connection
$connection = New-SqlConnectionInfo -Server $server -Username $username -Password $password

# disable
Disable-DatabaseTriggers -Database $database -ConnectionInfo $connection
Disable-TableTriggers -Database $database -ConnectionInfo $connection -SchemaName "Person" -TableName "Person"
Disable-TableTrigger -Database $database -ConnectionInfo $connection -SchemaName "Person" -TableName "Person" -TriggerName "iuPerson"

# enable
Enable-TableTrigger -Database $database -ConnectionInfo $connection -SchemaName "Person" -TableName "Person" -TriggerName "iuPerson"
Enable-TableTriggers -Database $database -ConnectionInfo $connection -SchemaName "Person" -TableName "Person"
Enable-DatabaseTriggers -Database $database -ConnectionInfo $connection
