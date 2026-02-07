## Simple example showing basic usage of Find-Subset-Refactored

# Connection settings
$server = "localhost"
$database = "AdventureWorks2019"
$username = "someuser"
$password = ConvertTo-SecureString -String "pass" -AsPlainText -Force

# 1. Create connection
$connection = New-SqlConnectionInfo -Server $server -Username $username -Password $password

# 2. Get database metadata (tables, foreign keys, etc.)
$info = Get-DatabaseInfo -Database $database -ConnectionInfo $connection

# 3. Create a session to track this subset operation
$sessionId = Start-SqlSizerSession -Database $database -ConnectionInfo $connection -DatabaseInfo $info

# 4. Define what records to start with
$query = New-Object -TypeName Query2
$query.State = [TraversalState]::Include  # Include these records and their dependencies
$query.Schema = "Person"
$query.Table = "Person"
$query.KeyColumns = @('BusinessEntityID')
$query.Where = "[`$table].FirstName = 'John'"
$query.Top = 5

# 5. Initialize the starting set with your query
Initialize-StartSet-Refactored -Database $database -ConnectionInfo $connection `
    -Queries @($query) -DatabaseInfo $info -SessionId $sessionId

# 6. Find the complete subset by following foreign key relationships
Find-Subset-Refactored -Database $database -ConnectionInfo $connection `
    -DatabaseInfo $info -SessionId $sessionId

# 7. Get the results - which tables and how many rows in each
$subsetTables = Get-SubsetTables -Database $database -ConnectionInfo $connection `
    -DatabaseInfo $info -SessionId $sessionId

# Display results
Write-Host "Subset contains data from the following tables:" -ForegroundColor Green
$subsetTables | Format-Table SchemaName, TableName, Rows -AutoSize
