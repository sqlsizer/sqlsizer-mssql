function Copy-Constraints
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

    if ($ConnectionInfo.IsSynapse -eq $true)
    {
        throw "Feature not supported in Synapse"
    }

    Write-Progress -Activity "Copy constraints" -PercentComplete 0

    $sql = "SELECT s.name as [schema], object_name(o.object_id) as constraintName, object_name(o.parent_object_id) as tableName, object_definition(o.object_id) as [definition]
    FROM sys.objects o
    INNER JOIN sys.schemas s ON o.schema_id = s.schema_id
    WHERE type='C'"
    $rows = Invoke-SqlcmdEx -Sql $sql -Database $SourceDatabase -ConnectionInfo $ConnectionInfo

    foreach ($row in $rows)
    {
        $schema = $row.schema
        $tableName = $row.tableName
        $constraintName = $row.constraintName
        $definition = $row.definition

        $schemaExists = Test-SchemaExists -SchemaName $schema -Database $TargetDatabase -ConnectionInfo $ConnectionInfo
        if ($schemaExists -eq $false)
        {
            $tmp = "CREATE SCHEMA $schema"
            Invoke-SqlcmdEx -Sql $tmp -Database $TargetDatabase -ConnectionInfo $ConnectionInfo -Statistics $false
        }

        $sql = "ALTER TABLE $schema.$tableName ADD CONSTRAINT $constraintName CHECK ($definition)"
        $null = Invoke-SqlcmdEx -Sql $sql -Database $TargetDatabase -ConnectionInfo $ConnectionInfo

        $sql = "ALTER TABLE $schema.$tableName CHECK CONSTRAINT $constraintName"
        $null = Invoke-SqlcmdEx -Sql $sql -Database $TargetDatabase -ConnectionInfo $ConnectionInfo
    }

    Write-Progress -Activity "Copy constraints" -Completed
}
