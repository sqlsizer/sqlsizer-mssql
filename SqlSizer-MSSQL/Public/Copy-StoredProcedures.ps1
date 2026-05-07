function Copy-StoredProcedures
{
    [cmdletbinding()]
    param
    (
        [Parameter(Mandatory = $true)]
        [string]$SourceDatabase,

        [Parameter(Mandatory = $true)]
        [string]$TargetDatabase,

        [Parameter(Mandatory = $true)]
        [SqlConnectionInfo]$ConnectionInfo
    )

    Write-Progress -Activity "Copy stored procedures" -PercentComplete 0

    $sql = "SELECT s.name as [schema], o.name as [procedure_name], object_definition(o.object_id) as [definition]
    FROM sys.objects o
    INNER JOIN sys.schemas s ON o.schema_id = s.schema_id
    WHERE type='P'"
    $rows = Invoke-SqlcmdEx -Sql $sql -Database $SourceDatabase -ConnectionInfo $ConnectionInfo

    foreach ($row in $rows)
    {
        $schema = $row.schema
        $procedureName = $row.procedure_name

        $schemaExists = Test-SchemaExists -SchemaName $schema -Database $TargetDatabase -ConnectionInfo $ConnectionInfo
        if ($schemaExists -eq $false)
        {
            $tmp = "CREATE SCHEMA $(ConvertTo-SqlIdentifier $schema)"
            Invoke-SqlcmdEx -Sql $tmp -Database $TargetDatabase -ConnectionInfo $ConnectionInfo -Statistics $false
        }

        $definition = $row.definition
        $definition = $definition.Replace("'", "''")

        $sql = "EXEC ('$definition')"
        $result = Invoke-SqlcmdEx -Sql $sql -Database $TargetDatabase -ConnectionInfo $ConnectionInfo -Silent $true
        if ($result -eq $false)
        {
            Write-Warning "Skipped stored procedure [$schema].[$procedureName] in [$TargetDatabase]: it may reference features (e.g., full-text search) not configured in the target database."
        }
    }

    Write-Progress -Activity "Copy stored procedures" -Completed
}
