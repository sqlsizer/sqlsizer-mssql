## Example that shows how to create a new database with the subset of data

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
$sessionId = Start-SqlSizerSession -Database $database -ConnectionInfo $connection -DatabaseInfo $info -ForceInstallation $true

# Define start set
# Query 1: 10 persons with first name = 'John'
$query = New-Object -TypeName Query2
$query.State = [TraversalState]::Include  # Use modern TraversalState enum for forward traversal
$query.Schema = "Person"
$query.Table = "Person"
$query.KeyColumns = @('BusinessEntityID')
$query.Where = "[`$table].FirstName = 'John'"
$query.Top = 10
$query.OrderBy = "[`$table].LastName ASC"

# Init start set
Initialize-StartSet -Database $database -ConnectionInfo $connection -Queries @($query) -DatabaseInfo $info -SessionId $sessionId

# Find subset using refactored algorithm (forward traversal)
Find-Subset -Database $database -ConnectionInfo $connection -DatabaseInfo $info -FullSearch $false -UseDfs $false -SessionId $sessionId

# Get subset info
Get-SubsetTables -Database $database -Connection $connection -DatabaseInfo $info -SessionId $sessionId

# Create a new db with found subset of data
$newDatabase = "AdventureWorks2019_subset_John"
Copy-Database -Database $database -NewDatabase $newDatabase -ConnectionInfo $connection
$infoNew = Get-DatabaseInfo -Database $newDatabase -ConnectionInfo $connection

Disable-ForeignKeys -Database $newDatabase -ConnectionInfo $connection -DatabaseInfo $infoNew
Disable-AllTablesTriggers -Database $newDatabase -ConnectionInfo $connection -DatabaseInfo $infoNew
Clear-Database -Database $newDatabase -ConnectionInfo $connection -DatabaseInfo $infoNew

Copy-DataFromSubset -Source $database -Destination $newDatabase -ConnectionInfo $connection -DatabaseInfo $info -SessionId $sessionId
Clear-SqlSizerSession -SessionId $sessionId -Database $database -ConnectionInfo $connection -DatabaseInfo $info


Enable-ForeignKeys -Database $newDatabase -ConnectionInfo $connection -DatabaseInfo $infoNew
Enable-AllTablesTriggers -Database $newDatabase -ConnectionInfo $connection -DatabaseInfo $infoNew
Format-Indexes -Database $newDatabase -ConnectionInfo $connection -DatabaseInfo $infoNew
Compress-Database -Database $newDatabase -ConnectionInfo $connection
Test-ForeignKeys -Database $newDatabase -ConnectionInfo $connection -DatabaseInfo $infoNew

$infoNew = Get-DatabaseInfo -Database $newDatabase -ConnectionInfo $connection -MeasureSize $true

Write-Verbose "Subset size: $($infoNew.DatabaseSize)"
$sum = 0
foreach ($table in $infoNew.Tables)
{
    $sum += $table.Statistics.Rows
}

Write-Verbose "Logical reads: $($connection.Statistics.LogicalReads)"
Write-Verbose "Total rows: $($sum)"
Write-Verbose "==================="

