## Example that shows how to do full search in interactive mode

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

# Init start set
Initialize-StartSet -Database $database -ConnectionInfo $connection -Queries @($query) -DatabaseInfo $info -SessionId $sessionId

$iteration = 0

do
{
    # Use refactored algorithm for forward subset finding (Yellow = Pending/Include states)
    $result = Find-Subset -Interactive $true -Iteration $iteration -Database $database -ConnectionInfo $connection `
            -DatabaseInfo $info -FullSearch $true `
            -UseDfs $false -SessionId $sessionId

    # custom logic when to stop or custom logic to process results of iterations

    $sum = "SELECT SUM(ToProcess) as Sum FROM SqlSizer.Operations WHERE [SessionId] = '$sessionId'"
    $sumRow = Invoke-SqlcmdEx -Sql $sum -Database $Database -ConnectionInfo $connection

    if ($sumRow.Sum -gt 4008)
    {
        Write-Host "Full search stopped..."
        break
    }
    $iteration += 1
}
while ($result.Finished -eq $false)


