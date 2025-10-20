## Example that shows how to a subset database in Azure

# Connection settings
$server = "sqlsizer.database.windows.net"
$database = "test01"
$storageAccount = "<your storage account>"

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
$query = New-Object -TypeName Query
$query.Color = [Color]::Yellow
$query.Schema = "SalesLT"
$query.Table = "Customer"
$query.KeyColumns = @('CustomerID')
$query.Top = 10

Initialize-StartSet -Database $database -ConnectionInfo $connection -Queries @($query) -DatabaseInfo $info -SessionId $sessionId

# Find subset
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

# Connect to storage
$keys = Get-AzStorageAccountKey -Name $storageAccount -ResourceGroupName "SqlSizer"
$ctx = New-AzStorageContext -StorageAccountName "$storageAccount" -StorageAccountKey "$($keys[0].Value)"

# Copy subset to storage account
$container = "subset_for_$newDatabase".Replace('_', '').Substring(0, 30)
Copy-SubsetToAzStorageContainer -ContainerName $container -StorageContext $ctx -Database $database -DatabaseInfo $info -ConnectionInfo $connection -Secure $false -SessionId $sessionId

$masterPassword = "$((New-Guid).ToString().Replace('-', '_'))"
# Copy data from Azure Blob storage
Import-SubsetFromAzStorageContainer -MasterPassword $masterPassword -Database $newDatabase -OriginalDatabase $database -ConnectionInfo $connection -DatabaseInfo $info `
    -ContainerName $container -StorageAccountName $storageAccount -StorageContext $ctx

Test-ForeignKeys -Database $newDatabase -ConnectionInfo $connection -DatabaseInfo $info
Remove-EmptyTables -Database $newDatabase -ConnectionInfo $connection -DatabaseInfo $info

Write-Verbose "Azure SQL database created"

# end of script
