## Example that shows how to work generate JSON with database schema

# Connection settings
$server = "localhost"
$database = "AdventureWorks2019"
$username = "someuser"
$password = ConvertTo-SecureString -String "pass" -AsPlainText -Force

# Create connection
$connection = New-SqlConnectionInfo -Server $server -Username $username -Password $password

$info = Get-DatabaseInfo -Database $database -ConnectionInfo $connection

$json = Get-DatabaseSchemaJson -Database $database -DatabaseInfo $info -ConnectionInfo $connection

$json
