## Example that shows color map feature

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
    if ($table.TableName -eq "Password")
    {
        $colorMapItem = New-Object -Type ColorItem
        $colorMapItem.SchemaName = $table.SchemaName
        $colorMapItem.TableName = $table.TableName
        $colorMapItem.ForcedColor = New-Object -Type ForcedColor
        $colorMapItem.ForcedColor.Color = [Color]::Purple

        $colorMapItem.Condition = New-Object -Type Condition
        $colorMapItem.Condition.SourceTableName = "Person"
        $colorMapItem.Condition.SourceSchemaName = "Person"
        $colorMap.Items += $colorMapItem
    }
}

Initialize-StartSet -Database $database -ConnectionInfo $connection -Queries @($query) -DatabaseInfo $info -SessionId $sessionId

# Find subset
Measure-Command {
    Find-Subset -Database $database -ConnectionInfo $connection -IgnoredTables @($ignored) -DatabaseInfo $info -ColorMap $colorMap -SessionId $sessionId
}

# end of script
