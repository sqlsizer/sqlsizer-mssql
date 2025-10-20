## Example that shows how to remove all SqlSizer schemas

# Connection settings
$server = "localhost"
$database = "AdventureWorks2019"
$username = "someuser"
$password = ConvertTo-SecureString -String "pass" -AsPlainText -Force

# Create connection
$connection = New-SqlConnectionInfo -Server $server -Username $username -Password $password

# Get database info
$info = Get-DatabaseInfo -Database $database -ConnectionInfo $connection

foreach ($schema in $info.Schemas)
{
    if ($schema.StartsWith("SqlSizer"))
    {
        Remove-Schema -Database $database -SchemaName $schema -ConnectionInfo $connection -DatabaseInfo $info
    }
}

# end of script
