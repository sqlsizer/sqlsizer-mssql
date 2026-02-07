## Example that shows how to a subset database in Azure without using Azure Storage Account (with data-copy clone) and then remove it ...

# Connection settings
$server = "sqlsizer.database.windows.net"
$database = "test03"

Connect-AzAccount
$accessToken = (Get-AzAccessToken -ResourceUrl https://database.windows.net).Token

# Create connection
$connection = New-SqlConnectionInfo -Server $server -AccessToken $accessToken -EncryptConnection $true

# Check if database is available
if ((Test-DatabaseOnline -Database $database -ConnectionInfo $connection) -eq $false)
{
    Write-Verbose "Database is not available" 
    return
}

# Get database info
$info = Get-DatabaseInfo -Database $database -ConnectionInfo $connection

# Start session
$sessionId = Start-SqlSizerSession -Database $database -ConnectionInfo $connection -DatabaseInfo $info

# Define start set

# Query 1: 10 persons with first name = 'John'
$query = New-Object -TypeName Query2
$query.State = [TraversalState]::Include  # Use modern TraversalState enum for forward traversal
$query.Schema = "SalesLT"
$query.Table = "Customer"
$query.KeyColumns = @('CustomerID')
$query.Top = 10

Initialize-StartSet -Database $database -ConnectionInfo $connection -Queries @($query) -DatabaseInfo $info -SessionId $sessionId

# Find subset using refactored algorithm
Find-Subset -Database $database -ConnectionInfo $connection -DatabaseInfo $info -SessionId $sessionId

# Get subset info
Get-SubsetTables -Database $database -Connection $connection -DatabaseInfo $info -SessionId $sessionId

Write-Verbose "Logical reads from db during subsetting: $($connection.Statistics.LogicalReads)"


# Ensure that empty database with the database schema exists
$emptyDb = "test03_empty"

if ((Test-DatabaseOnline -Database $emptyDb -ConnectionInfo $connection) -eq $false)
{
    New-EmptyAzDatabase -Database $database -NewDatabase $emptyDb -ConnectionInfo $connection -DatabaseInfo $info
}

# Create a copy of empty db for new subset db
$newDatabase = "test03_$((New-Guid).ToString().Replace('-', '_'))"
Copy-AzDatabase -Database $emptyDb -NewDatabase $newDatabase -ConnectionInfo $connection

while ((Test-DatabaseOnline -Database $newDatabase -ConnectionInfo $connection) -eq $false)
{
    Write-Verbose "Waiting for database"
    Start-Sleep -Seconds 5
}

$newInfo = Get-DatabaseInfo -Database $newDatabase -ConnectionInfo $connection
Disable-ForeignKeys -Database $newDatabase -ConnectionInfo $connection -DatabaseInfo $newInfo
Disable-AllTablesTriggers -Database $newDatabase -ConnectionInfo $connection -DatabaseInfo $newInfo
$files = Copy-SubsetToDatabaseFileSet -SourceDatabase $database -TargetDatabase $newDatabase -DatabaseInfo $info -ConnectionInfo $connection -Secure $false -SessionId $sessionId

# import data
Import-SubsetFromFileSet -SourceDatabase $newDatabase -TargetDatabase $newDatabase -DatabaseInfo $newInfo -ConnectionInfo $connection -Files $files

# remove data 
Remove-DataFromFileSet -Database $newDatabase -DatabaseInfo $newInfo -ConnectionInfo $connection -Files $files

Enable-ForeignKeys -Database $newDatabase -ConnectionInfo $connection -DatabaseInfo $newInfo
Enable-AllTablesTriggers -Database $newDatabase -ConnectionInfo $connection -DatabaseInfo $newInfo
# end of script
