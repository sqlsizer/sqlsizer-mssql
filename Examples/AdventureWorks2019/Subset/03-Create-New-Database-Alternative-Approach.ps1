## Example that shows how to create a new database with the subset of data based on queries which define initial data with color map

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

# Define traversal configuration using modern API
$config = New-Object -Type TraversalConfiguration

foreach ($table in $info.Tables)
{
    $rule = New-Object -Type TraversalRule -ArgumentList $table.SchemaName, $table.TableName

    if ($table.TableName -in @('Person'))
    {
        # Use StateOverride instead of ForcedColor for modern configuration
        $rule.StateOverride = New-Object -Type StateOverride -ArgumentList ([TraversalState]::Pending)
    }

    # Use TraversalConstraints instead of Condition for modern configuration
    $rule.Constraints = New-Object -Type TraversalConstraints
    $rule.Constraints.Top = 10 # limit all dependend data for each fk by 10 rows (it doesn't mean that there will be no more rows!)
    $config.Rules += $rule
}

Initialize-StartSet -Database $database -ConnectionInfo $connection -Queries @($query) -DatabaseInfo $info -SessionId $sessionId

# Find subset using refactored algorithm with modern TraversalConfiguration
Find-Subset -Database $database -ConnectionInfo $connection -DatabaseInfo $info -TraversalConfiguration $config -UseDfs $true -SessionId $sessionId

# Get subset info
Get-SubsetTables -Database $database -Connection $connection -DatabaseInfo $info -SessionId $sessionId

# Create a new db with found subset of data

$newDatabase = "AdventureWorks2019_subset_07"
Copy-Database -Database $database -NewDatabase $newDatabase -ConnectionInfo $connection
$infoNew = Get-DatabaseInfo -Database $newDatabase -ConnectionInfo $connection

Disable-ForeignKeys -Database $newDatabase -ConnectionInfo $connection -DatabaseInfo $infoNew
Disable-AllTablesTriggers -Database $newDatabase -ConnectionInfo $connection -DatabaseInfo $infoNew

Clear-Database -Database $newDatabase -ConnectionInfo $connection -DatabaseInfo $infoNew
Copy-DataFromSubset -Source $database -Destination  $newDatabase -ConnectionInfo $connection -DatabaseInfo $info -SessionId $sessionId
Enable-ForeignKeys -Database $newDatabase -ConnectionInfo $connection -DatabaseInfo $infoNew
Enable-AllTablesTriggers -Database $newDatabase -ConnectionInfo $connection -DatabaseInfo $infoNew

Format-Indexes -Database $newDatabase -ConnectionInfo $connection -DatabaseInfo $infoNew
Uninstall-SqlSizer -Database $newDatabase -ConnectionInfo $connection -DatabaseInfo $infoNew
Compress-Database -Database $newDatabase -ConnectionInfo $connection

Test-ForeignKeys -Database $newDatabase -ConnectionInfo $connection -DatabaseInfo $infoNew

$infoNew = Get-DatabaseInfo -Database $newDatabase -ConnectionInfo $connection -MeasureSize $true

Write-Verbose "Subset size: $($infoNew.DatabaseSize)"
$sum = 0
foreach ($table in $infoNew.Tables)
{
    $sum += $table.Statistics.Rows
}

Write-Verbose "Total rows: $($sum)"

# end of script
