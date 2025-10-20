## Example that shows how to find a subset in Azure Synapse Analytics, save them for analysis

# Connection settings
$server = "#name#.sql.azuresynapse.net"
$database = "#db#"
$username = "sqladminuser"
$password = ConvertTo-SecureString -String "#pass#" -AsPlainText -Force

# Create connection
$connection = New-SqlConnectionInfo -Server $server -Username $username -Password $password -EncryptConnection $true -IsSynapse $true

# Check if database is available
if ((Test-DatabaseOnline -Database $database -ConnectionInfo $connection) -eq $false)
{
    Write-Verbose "Database is not available" 
    return
}

$additonalStructure = New-Object DatabaseStructureInfo

$fk1 = New-Object TableFk
$fk1.Name = "AC"
$fk1.FkSchema = "SalesLT"
$fk1.FkTable = "CustomerAddress"
$fk1.Schema = "SalesLT"
$fk1.Table = "Customer"
$c1 = New-Object ColumnInfo
$c1.Name = "CustomerID"
$c1.DataType = "int"
$fk1.FkColumns += $c1
$fk1.Columns += $c1
$additonalStructure.Fks += $fk1

# Get database info
$info = Get-DatabaseInfo -Database $database -ConnectionInfo $connection -AdditonalStructureInfo $additonalStructure

# Start sessions
$sessionId = Start-SqlSizerSession -Database $database -ConnectionInfo $connection -DatabaseInfo $info
$sessionId2 = Start-SqlSizerSession -Database $database -ConnectionInfo $connection -DatabaseInfo $info

# Define start set

# Query 1: 10 persons with first name = 'John'
$query = New-Object -TypeName Query
$query.Color = [Color]::Yellow
$query.Schema = "SalesLT"
$query.Table = "Customer"
$query.KeyColumns = @('CustomerID')
$query.Where =  "[`$table].FirstName = 'Brian'"
$query.Top = 1000

Initialize-StartSet -Database $database -ConnectionInfo $connection -Queries @($query) -DatabaseInfo $info -SessionId $sessionId

# Find some subset
Find-Subset -Database $database -ConnectionInfo $connection -DatabaseInfo $info -SessionId $sessionId
$subset1Guid = Save-Subset -Database $database -ConnectionInfo $connection -SubsetName "BeforeChangesToData" -DatabaseInfo $info -SessionId $sessionId

# Remove some data from db
$null = Invoke-SqlcmdEx -Sql "DELETE FROM SalesLT.Customer WHERE FirstName = 'Brian' AND LastName = 'Goldstein'" -Database $Database -ConnectionInfo $connection

# Update some data from db
$null = Invoke-SqlcmdEx -Sql "UPDATE SalesLT.Customer SET Title = 'MR2.' WHERE FirstName = 'Brian'" -Database $Database -ConnectionInfo $connection

# Find some subset again
Find-Subset -Database $database -ConnectionInfo $connection -DatabaseInfo $info -SessionId $sessionId2
$subset2Guid = Save-Subset -Database $database -ConnectionInfo $connection -SubsetName "AfterChangesToData" -DatabaseInfo $info -SessionId $sessionId2

$compareResult = Compare-SavedSubsets -SourceDatabase $database -TargetDatabase $database `
                                    -SourceSubsetGuid $subset1Guid -TargetSubsetGuid $subset2Guid -ConnectionInfo $connection `

$compareResult


# end of script
