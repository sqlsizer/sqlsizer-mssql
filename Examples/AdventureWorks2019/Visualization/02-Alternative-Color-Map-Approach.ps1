## Example that shows color map feature

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
$query.State = [TraversalState]::Include  # Use modern TraversalState enum instead of legacy Color
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
    if ($table.TableName -eq "Password")
    {
        $rule = New-Object -Type TraversalRule -ArgumentList $table.SchemaName, $table.TableName
        
        # Use StateOverride instead of ForcedColor for modern configuration
        # Bidirectional traversal (was Purple in legacy)
        $rule.StateOverride = New-Object -Type StateOverride -ArgumentList ([TraversalState]::Bidirectional)

        # Use TraversalConstraints instead of Condition for modern configuration
        $rule.Constraints = New-Object -Type TraversalConstraints
        $rule.Constraints.SourceTableName = "Person"
        $rule.Constraints.SourceSchemaName = "Person"
        $config.Rules += $rule
    }
}

Initialize-StartSet -Database $database -ConnectionInfo $connection -Queries @($query) -DatabaseInfo $info -SessionId $sessionId

# Find subset using refactored algorithm with modern TraversalConfiguration
Measure-Command {
    Find-Subset -Database $database -ConnectionInfo $connection -IgnoredTables @($ignored) -DatabaseInfo $info -TraversalConfiguration $config -SessionId $sessionId
}

# end of script
