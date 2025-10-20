## Example that shows how to find a subset in Azure Synapse Analytics and export JSON

# Connection settings
$server = ".sql.azuresynapse.net"
$database = ""
$username = "sqladminuser"
$password = ConvertTo-SecureString -String "" -AsPlainText -Force

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

# Start session
$sessionId = Start-SqlSizerSession -Database $database -ConnectionInfo $connection -DatabaseInfo $info

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

Get-SubsetTableJson -Database $database -ConnectionInfo $connection -SchemaName "SalesLT" -TableName "Customer" -DatabaseInfo $info -Secure $false -SessionId $sessionId

# end of script
