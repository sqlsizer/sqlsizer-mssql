## Example that shows how to check which tables are reachable by queries and color map

# Connection settings
$server = "localhost"
$database = "AdventureWorks2019"
$username = "someuser"
$password = ConvertTo-SecureString -String "pass" -AsPlainText -Force

# Create connection
$connection = New-SqlConnectionInfo -Server $server -Username $username -Password $password
$info = Get-DatabaseInfo -Database $database -ConnectionInfo $connection

# Query 1: All persons with first name = 'Michael'
$query = New-Object -TypeName Query
$query.Color = [Color]::Yellow
$query.Schema = "Person"
$query.Table = "Person"
$query.KeyColumns = @('BusinessEntityID')
$query.Where = "[`$table].FirstName = 'Michael'"

$colorMap = New-Object -Type ColorMap

$colorMapItem = New-Object -Type ColorItem
$colorMapItem.SchemaName = "Person"
$colorMapItem.TableName = "Address"
$colorMapItem.ForcedColor = New-Object -Type ForcedColor
$colorMapItem.ForcedColor.Color = [Color]::Purple
$colorMap.Items += $colorMapItem

$null = Test-Queries -Database $database -ConnectionInfo $connection -Queries @($query) -DatabaseInfo $info -ColorMap $colorMap

# end of script
