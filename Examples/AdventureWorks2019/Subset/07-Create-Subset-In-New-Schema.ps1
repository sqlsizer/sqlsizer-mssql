## Example that shows how to create a schema with subset

# Connection settings
$server = "localhost"
$database = "AdventureWorks2019"
$username = "sa"
$password = ConvertTo-SecureString -String "sasa" -AsPlainText -Force

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
Initialize-StartSet -Database $database -ConnectionInfo $connection -Queries @($query) -DatabaseInfo $info -SessionId $sessionId

# Find subset using refactored algorithm
Find-Subset -Database $database -ConnectionInfo $connection -IgnoredTables @($ignored) -DatabaseInfo $info -SessionId $sessionId

# Get subset info
Get-SubsetTables -Database $database -Connection $connection -DatabaseInfo $info -SessionId $sessionId

Write-Verbose "Logical reads from db during subsetting: $($connection.Statistics.LogicalReads)"

$subsetId = (New-Guid).ToString().Replace('-', '_')

New-SchemaFromSubset -Connection $connection -Database $database -DatabaseInfo $info -CopyData $true `
                     -NewSchemaPrefix "SqlSizer_subset_$subsetId" `
                     -SessionId $sessionId

Write-Verbose "New schema: SqlSizer_subset_$subsetId"

# end of script
