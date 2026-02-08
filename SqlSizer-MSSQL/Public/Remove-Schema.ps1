function Remove-Schema
{
    [cmdletbinding()]
    param
    (
        [Parameter(Mandatory = $true)]
        [string]$Database,

        [Parameter(Mandatory = $true)]
        [string]$SchemaName,

        [Parameter(Mandatory = $false)]
        [string[]]$KeepTables = $null,

        [Parameter(Mandatory = $false)]
        [bool]$DropFks = $true,

        [Parameter(Mandatory = $true)]
        [DatabaseInfo]$DatabaseInfo,

        [Parameter(Mandatory = $true)]
        [SqlConnectionInfo]$ConnectionInfo
    )

    $schemaExists = Test-SchemaExists -SchemaName $SchemaName -Database $Database -ConnectionInfo $ConnectionInfo
    if ($schemaExists -eq $false)
    {
        Write-Host "Schema $SchemaName doesn't exist"
        return $false
    }

    # drop tables in schema
    foreach ($table in $DatabaseInfo.Tables)
    {
        if (($table.SchemaName -eq $SchemaName) -and ($table.TableName -notin $KeepTables))
        {
            $null = Remove-Table -Database $Database -SchemaName $table.SchemaName -TableName $table.TableName -DatabaseInfo $DatabaseInfo -ConnectionInfo $ConnectionInfo -DropFks $DropFks
        }
    }

    # drop views in schema
    foreach ($view in $DatabaseInfo.Views)
    {
        if ($view.SchemaName -eq $SchemaName)
        {
            $sql = "DROP VIEW IF EXISTS [$($view.SchemaName)].[$($view.ViewName)]"   
            $null = Invoke-SqlcmdEx -Sql $sql -Database $Database -ConnectionInfo $ConnectionInfo
        }
    }

    # drop stored procedures in schema
    foreach ($storedInfo in $DatabaseInfo.StoredProcedures)
    {
        if ($storedInfo.Schema -eq $SchemaName)
        {
            $sql = "DROP PROCEDURE [$SchemaName].[$($storedInfo.Name)]"
            $null = Invoke-SqlcmdEx -Sql $sql -Database $Database -ConnectionInfo $ConnectionInfo
        }
    }

    # drop schema
    if ($null -eq $KeepTables)
    {
        $sql = "DROP SCHEMA IF EXISTS $SchemaName"    
        $null = Invoke-SqlcmdEx -Sql $sql -Database $Database -ConnectionInfo $ConnectionInfo -Statistics $false
    }
}
