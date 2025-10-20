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
$query = New-Object -TypeName Query
$query.Color = [Color]::Yellow
$query.Schema = "Person"
$query.Table = "Person"
$query.KeyColumns = @('BusinessEntityID')
$query.Where = "[`$table].FirstName = 'John'"
$query.Top = 10
$query.OrderBy = "[`$table].LastName ASC"

# Init start set
Initialize-StartSet -Database $database -ConnectionInfo $connection -Queries @($query) -DatabaseInfo $info -SessionId $sessionId

$iteration = 0
$found = $false
do
{
    $result = Find-Subset -Interactive $true -Iteration $iteration -Database $database -ConnectionInfo $connection `
            -DatabaseInfo $info -FullSearch $true `
            -UseDfs $false -SessionId $sessionId

    $tables = Get-SubsetTableStatistics -Iteration $iteration -Database $database -Connection $connection -DatabaseInfo $info -SessionId $sessionId

    foreach ($table in $tables)
    {
        $rows = Get-SubsetTableRows -Database $database -Connection $connection -DatabaseInfo $info -SessionId $sessionId `
                -Iteration $iteration -TableName $table.TableName -SchemaName $table.SchemaName `
                -AllColumns $true

        foreach ($row in $rows)
        {
            foreach ($column in $row.ItemArray)
            {
                if ($column -eq '98011')
                {
                    $foundRow = $row
                    $foundTable = $table
                    $found = $true
                    break
                }
            }
        }
    }

    $iteration += 1
}
while (($result.Finished -eq $false) -and ($found -eq $false))

if ($found)
{
    Write-Host "Found in => $($foundTable.SchemaName).$($foundTable.TableName)"
    Write-Host "Row => $($foundRow.ItemArray)"
}
