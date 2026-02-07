## Example that shows how to create a table from subset table

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
$query = New-Object -TypeName Query2
$query.State = [TraversalState]::Include  # Use modern TraversalState enum for forward traversal
$query.Schema = "Person"
$query.Table = "Person"
$query.KeyColumns = @('BusinessEntityID')
$query.Where = "[`$table].FirstName = 'John'"
$query.Top = 10
$query.OrderBy = "[`$table].LastName ASC"

# Define ignored tables

$ignored = New-Object -Type TableInfo2
$ignored.SchemaName = "dbo"
$ignored.TableName = "ErrorLog"

# Init start set
Initialize-StartSet-Refactored -Database $database -ConnectionInfo $connection -Queries @($query) -DatabaseInfo $info -SessionId $sessionId

# Find subset using refactored algorithm
Find-Subset-Refactored -Database $database -ConnectionInfo $connection -IgnoredTables @($ignored) -DatabaseInfo $info -SessionId $sessionId

# Get subset info
Get-SubsetTables -Database $database -Connection $connection -DatabaseInfo $info -SessionId $sessionId

Write-Verbose "Logical reads from db during subsetting: $($connection.Statistics.LogicalReads)"

New-DataTableFromSubsetTable -Connection $connection -Database $database -DatabaseInfo $info -CopyData $true `
                             -NewSchemaName "Person_subset_02" -NewTableName "Address" -SchemaName "Person" -TableName "Address" `
                             -SessionId $sessionId
                        
# end of script
