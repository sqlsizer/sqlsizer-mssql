## Example that shows how to create a subset database without making data-copy of original database

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
$query = New-Object -TypeName SqlSizerQuery
$query.State = [TraversalState]::Include  # Seed rows for the subset closure
$query.Schema = "Person"
$query.Table = "Person"
$query.KeyColumns = @('BusinessEntityID')
$query.Where = "[`$table].FirstName = 'Gigi'"
$query.Top = 10
$query.OrderBy = "[`$table].LastName ASC"

# Define ignored tables

$ignored = New-Object -Type TableInfo2
$ignored.SchemaName = "dbo"
$ignored.TableName = "ErrorLog"

# Init start set
Initialize-StartSet -Database $database -ConnectionInfo $connection -Queries @($query) -DatabaseInfo $info -SessionId $sessionId

# Find subset using minimal dependency closure with ignored tables
Find-Subset -Database $database -ConnectionInfo $connection -IgnoredTables @($ignored) -DatabaseInfo $info -SessionId $sessionId

# Create a new db with found subset of data
$newDatabase = "AdventureWorks2019_subset_w2"

if ((New-EmptyCompactDatabase -Database $database -NewDatabase $newDatabase -ConnectionInfo $connection -DatabaseInfo $info) -eq $false)
{
    Write-Verbose "Database already exists"
    return
}

Copy-DataFromSubset -Source $database -Destination $newDatabase -ConnectionInfo $connection -DatabaseInfo $info -SessionId $sessionId -BatchSize 100000
Format-Indexes -Database $newDatabase -ConnectionInfo $connection -DatabaseInfo $info
Compress-Database -Database $newDatabase -ConnectionInfo $connection
