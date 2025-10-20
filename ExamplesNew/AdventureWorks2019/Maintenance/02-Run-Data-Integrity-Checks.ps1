## Example that shows how to work with integrity checks

# Connection settings
$server = "localhost"
$database = "AdventureWorks2019"
$username = "someuser"
$password = ConvertTo-SecureString -String "pass" -AsPlainText -Force

# Create connection
$connection = New-SqlConnectionInfo -Server $server -Username $username -Password $password
$info = Get-DatabaseInfo -Database $database -ConnectionInfo $connection

Disable-AllTablesTriggers -Database $database -ConnectionInfo $connection -DatabaseInfo $info

# change all fk to delte and update cascade
foreach ($table in $info.Tables)
{
    foreach ($fk in $table.ForeignKeys)
    {
            Edit-ForeignKey -Database $database -ConnectionInfo $connection -DatabaseInfo $info `
                            -SchemaName $table.SchemaName -TableName $table.TableName -FkName $fk.Name `
                            -DeleteRule ([ForeignKeyRule]::Cascade) `
                            -UpdateRule ([ForeignKeyRule]::Cascade)
    }
}

Enable-AllTablesTriggers -Database $database -ConnectionInfo $connection -DatabaseInfo $info

