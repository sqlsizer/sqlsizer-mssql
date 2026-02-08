## Example that shows color maps feature

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
$query.State = [TraversalState]::Include  
$query.Schema = "Person"
$query.Table = "Person"
$query.KeyColumns = @('BusinessEntityID')
$query.Where = "[`$table].FirstName = 'John'"
$query.Top = 10
$query.OrderBy = "[`$table].LastName ASC"

# Define ignored tables (empty - don't ignore any tables)
$ignored = @()

# Init start set
Initialize-StartSet -Database $database -ConnectionInfo $connection -Queries @($query) -DatabaseInfo $info -SessionId $sessionId

# Find subset using refactored algorithm with modern TraversalConfiguration
$result = Find-Subset -Database $database -ConnectionInfo $connection -IgnoredTables $ignored -DatabaseInfo $info -SessionId $sessionId
Write-Host "Find-Subset result: Finished=$($result.Finished), CompletedIterations=$($result.CompletedIterations)"

# Get subset info
$subsetTables = Get-SubsetTables -Database $database -ConnectionInfo $connection -DatabaseInfo $info -SessionId $sessionId
Write-Host "`nSubset tables with data:"
$subsetTables | Format-Table -AutoSize

# end of script
