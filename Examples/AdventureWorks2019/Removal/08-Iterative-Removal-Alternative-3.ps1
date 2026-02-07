## Example that shows how to remove in the fastest way (session reuse)

# Connection settings
$server = "localhost"
$database = "AdventureWorks2019"
$username = "someuser"
$password = ConvertTo-SecureString -String "pass" -AsPlainText -Force

# Create connection
$connection = New-SqlConnectionInfo -Server $server -Username $username -Password $password

# Get database info
$info = Get-DatabaseInfo -Database $database -ConnectionInfo $connection

# Verify if SqlSizer is installed
Install-SqlSizer -Database $database -ConnectionInfo $connection -DatabaseInfo $info

# Disable integrity checks and triggers
Disable-ForeignKeys -Database $database -ConnectionInfo $connection -DatabaseInfo $info
Disable-AllTablesTriggers -Database $database -ConnectionInfo $connection -DatabaseInfo $info
$start = Get-Date

$i = 0
$step = 10000
$sessionId = Start-SqlSizerSession -Database $database -ConnectionInfo $connection -DatabaseInfo $info -Installation $false -SecureViews $false -ExportViews $false -Removal $true

$startIteration = 0

while ($true)
{
    # Define start set
    $query = New-Object -TypeName Query2
    $query.State = [TraversalState]::InboundOnly  # Use modern TraversalState enum for removal/incoming FK traversal
    $query.Schema = "Person"
    $query.Table = "Person"
    $query.KeyColumns = @('BusinessEntityID')
    $query.Top = $step
    $query.Where = "[`$table].BusinessEntityID > $i"
    $query.OrderBy = "[`$table].BusinessEntityID ASC"

    Initialize-StartSet-Refactored -Database $database -ConnectionInfo $connection -Queries @($query) -DatabaseInfo $info -SessionId $sessionId -StartIteration $startIteration
    # Use refactored removal subset algorithm (Blue = InboundOnly)
    $result = Find-RemovalSubset-Refactored -Database $database -ConnectionInfo $connection -DatabaseInfo $info -SessionId $sessionId -StartIteration $startIteration  
    $empty = Test-FoundSubsetIsEmpty -Database $database -ConnectionInfo $connection -DatabaseInfo $info -SessionId $sessionId -StartIteration $startIteration

    $startIteration += $result.CompletedIterations

    if ($empty -eq $true)
    {
        break
    }

    $i += $step
}

$query = New-Object -TypeName Query2
$query.State = [TraversalState]::InboundOnly  # Use modern TraversalState enum for removal/incoming FK traversal
$query.Schema = "Person"
$query.Table = "Person"
$query.KeyColumns = @('BusinessEntityID')

Disable-ReachableIndexes -Queries @($query) -Database $database -ConnectionInfo $connection -DatabaseInfo $info
Remove-FoundSubsetsFromDatabase -Database $database -ConnectionInfo $connection -DatabaseInfo $info -Step 100000 -Sessions @($sessionId)
Enable-ReachableIndexes -Queries @($query) -Database $database -ConnectionInfo $connection -DatabaseInfo $info
Clear-SqlSizerSession -SessionId $sessionId -Database $database -ConnectionInfo $connection -DatabaseInfo $info
Update-DatabaseInfo -DatabaseInfo $info -Database $Database -ConnectionInfo $connection

$end = Get-Date

# Enable integrity checks and triggers
Enable-ForeignKeys -Database $database -ConnectionInfo $connection -DatabaseInfo $info
Enable-AllTablesTriggers -Database $database -ConnectionInfo $connection -DatabaseInfo $info

# Test foreign keys
Test-ForeignKeys -Database $database -ConnectionInfo $connection -DatabaseInfo $info

Write-Host ($end - $start)
