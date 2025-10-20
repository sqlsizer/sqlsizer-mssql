## Example that shows color maps feature

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

# Define start set

# Query 1: 10 persons with first name = 'John'
$query = New-Object -TypeName Query
$query.Color = [Color]::Yellow
$query.Schema = "Person"
$query.Table = "Person"
$query.KeyColumns = @('BusinessEntityID')
$query.Where = "[`$table].FirstName = 'John'"
$query.Top = 10
$query.OrderBy = "[`$table].LastName ASC"

# Define color map
$colorMap = New-Object -Type ColorMap

foreach ($table in $info.Tables)
{
    $colorMapItem = New-Object -Type ColorItem
    $colorMapItem.SchemaName = $table.SchemaName
    $colorMapItem.TableName = $table.TableName

    $colorMapItem.ForcedColor = New-Object -Type ForcedColor
    $colorMapItem.ForcedColor.Color = [Color]::Yellow

    $colorMapItem.Condition = New-Object -Type Condition
    $colorMapItem.Condition.Top = 10 # limit all dependend data for each fk by 10 rows (it doesn't mean that there will be no more rows!)
    $colorMap.Items += $colorMapItem
}

# Init start set
Initialize-StartSet -Database $database -ConnectionInfo $connection -Queries @($query) -DatabaseInfo $info -SessionId $sessionId

# Find subset
Find-Subset -Database $database -ConnectionInfo $connection -IgnoredTables @($ignored) -DatabaseInfo $info -ColorMap $colorMap -SessionId $sessionId

# Get subset info
Get-SubsetTables -Database $database -Connection $connection -DatabaseInfo $info -SessionId $sessionId

# end of script
