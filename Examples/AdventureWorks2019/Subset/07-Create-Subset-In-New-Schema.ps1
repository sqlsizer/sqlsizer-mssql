## Example that shows how to create a schema with subset

# Load the local module manifest so SqlSizer classes/enums are available to this script.
$modulePath = Join-Path $PSScriptRoot "..\..\..\SqlSizer-MSSQL\SqlSizer-MSSQL.psd1"
Import-Module $modulePath -Force -Global

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
$query = New-Object -TypeName SqlSizerQuery
$query.State = [TraversalState]::Include  # Seed rows for the subset closure
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

# Find subset using minimal dependency closure
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
