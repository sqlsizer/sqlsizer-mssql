## Example that shows how to setup missing PKs

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
$table = New-Object TableStructureInfo
$table.SchemaName = "SalesLT"
$table.TableName = "Customer"
$column = New-Object ColumnInfo
$column.Name = "CustomerID"
$column.DataType = "int"
$table.PrimaryKey += $column
$additonalStructure.Tables += $table

$table = New-Object TableStructureInfo
$table.SchemaName = "SalesLT"
$table.TableName = "ProductDescription"
$column = New-Object ColumnInfo
$column.Name = "ProductDescriptionID"
$column.DataType = "int"
$table.PrimaryKey += $column
$additonalStructure.Tables += $table

$table = New-Object TableStructureInfo
$table.SchemaName = "SalesLT"
$table.TableName = "ProductModelProductDescription"
$column = New-Object ColumnInfo
$column.Name = "ProductDescriptionID"
$column.DataType = "int"
$table.PrimaryKey += $column

$column = New-Object ColumnInfo
$column.Name = "ProductModelID"
$column.DataType = "int"
$table.PrimaryKey += $column
$additonalStructure.Tables += $table

# Get database info
$info = Get-DatabaseInfo -Database $database -ConnectionInfo $connection -AdditonalStructureInfo $additonalStructure

# Setup not present primary keys
Install-PrimaryKeys -Database $database -ConnectionInfo $connection -DatabaseInfo $info
