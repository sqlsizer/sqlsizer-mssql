## Example that shows how to remove all persons with FirstName LIKE '%o' in very slow way

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

while ($true)
{
    $sessionId = Start-SqlSizerSession -Database $database -ConnectionInfo $connection -DatabaseInfo $info -Installation $false -SecureViews $false -ExportViews $false -Removal $true

    # Define start set
    $query = New-Object -TypeName Query2
    $query.State = [TraversalState]::InboundOnly  # Use modern TraversalState enum for removal/incoming FK traversal
    $query.Schema = "Person"
    $query.Table = "Person"
    $query.KeyColumns = @('BusinessEntityID')
    $query.Where = "[`$table].FirstName LIKE '%a'"
    $query.Top = 10000
    $query.OrderBy = "[`$table].BusinessEntityID ASC"
    
    Initialize-StartSet-Refactored -Database $database -ConnectionInfo $connection -Queries @($query) -DatabaseInfo $info -SessionId $sessionId

    # Use refactored removal subset algorithm (Blue = InboundOnly)
    $null = Find-RemovalSubset-Refactored -Database $database -ConnectionInfo $connection -DatabaseInfo $info -SessionId $sessionId

    $empty = Test-FoundSubsetIsEmpty -Database $database -ConnectionInfo $connection -DatabaseInfo $info -SessionId $sessionId

    if ($empty -eq $true)
    {
        Clear-SqlSizerSession -SessionId $sessionId -Database $database -ConnectionInfo $connection -DatabaseInfo $info
        break
    }

    Remove-FoundSubsetFromDatabase -Database $database -ConnectionInfo $connection -DatabaseInfo $info -Step 100000 -SessionId $sessionId
    Clear-SqlSizerSession -SessionId $sessionId -Database $database -ConnectionInfo $connection -DatabaseInfo $info
}

Update-DatabaseInfo -DatabaseInfo $info -Database $Database -ConnectionInfo $connection

# Enable integrity checks and triggers
Enable-ForeignKeys -Database $database -ConnectionInfo $connection -DatabaseInfo $info
Enable-AllTablesTriggers -Database $database -ConnectionInfo $connection -DatabaseInfo $info

Write-Verbose "Logical reads from db: $($connection.Statistics.LogicalReads)"

# Test foreign keys
Test-ForeignKeys -Database $database -ConnectionInfo $connection -DatabaseInfo $info


