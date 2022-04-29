# mssql-sqlsizer
A set of PowerShell scripts to make a subset of Microsoft SQL database

# Details
The algorithm used in SqlSizer is a variation of Breadth-first and Depth-first search search algorithm applied to a relational database.

The initial set of graph nodes needs to be defined before start of the scripts.

Each graph node is represented by the row in *SqlSizer.Processing* table that has following information:
-  Schema name
-  Table name
-  Primary key values
-  One of the colors: RED, GREEN, YELLOW or BLUE
-  Depth

Finding of neighbours of graph nodes is done in bulks and depends on the color in order to optimize number of queries needed.

Colors have following meaning:
 - Blue: find all rows that are required to remove that row
 - Red: find all rows that are referenced by the row (recursively) 
 - Green: find all dependent rows on the row
 - Yellow: find all related data to the row

# Prerequisites

```powershell
Install-Module dbatools -Scope CurrentUser
```

# How to start?
Please take a look at examples in *Examples* folder.

# Example
```powershell
# Import of module
Import-Module ..\MSSQL-SqlSizer -Verbose


# Connection settings
$server = "localhost"
$database = "AdventureWorks2019"
$login = "someuser"
$password = "pass"

# Create connection
$connection = Get-SqlConnectionInfo -Server $server -Login $login -Password $password


# Get database info
$info = Get-DatabaseInfo -Database $database -ConnectionInfo $connection

# Init SqlSizer structures
Init-Structures -Database $database -ConnectionInfo $connection -DatabaseInfo $info

# Define start set

# Query 1: All persons with first name = 'Mary'
$query = New-Object -TypeName Query
$query.Color = [Color]::Yellow
$query.Schema = "Person"
$query.Table = "Person"
$query.KeyColumns = @('BusinessEntityID')
$query.Where = "[`$table].FirstName = 'Mary'"

# Query 2: All employees with SickLeaveHours > 30
$query2 = New-Object -TypeName Query
$query2.Color = [Color]::Yellow
$query2.Schema = "HumanResources"
$query2.Table = "Employee"
$query2.KeyColumns = @('BusinessEntityID')
$query2.Where = "[`$table].SickLeaveHours > 30"

Init-StartSet -Database $database -ConnectionInfo $connection -Queries @($query, $query2)

# Find subset
Get-Subset -Database $database -ConnectionInfo $connection -Return $false


# Create a new db with found subset of data
Copy-Database -Database $database -Prefix "S." -ConnectionInfo $connection
Disable-IntegrityChecks -Database ("S." + $database) -ConnectionInfo $connection
Truncate-Database -Database ("S." + $database) -ConnectionInfo $connection
Copy-Data -Source $database -Destination ("S." + $database) -ConnectionInfo $connection
Enable-IntegrityChecks -Database ("S." + $database) -ConnectionInfo $connection


# end of script
```

