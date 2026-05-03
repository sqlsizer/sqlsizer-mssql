function Copy-Functions
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

    Write-Progress -Activity "Copy functions" -PercentComplete 0

    $sql = "SELECT s.name as [schema], OBJECT_DEFINITION(o.object_id) as definition
    FROM sys.objects o
    INNER JOIN sys.schemas s ON o.schema_id = s.schema_id
    WHERE o.type IN ('FN', 'IF', 'TF', 'FS', 'FT')
        AND OBJECT_DEFINITION(o.object_id) IS NOT NULL"
    $rows = Invoke-SqlcmdEx -Sql $sql -Database $SourceDatabase -ConnectionInfo $ConnectionInfo

    foreach ($row in $rows)
    {
        $schema = $row.schema

        $schemaExists = Test-SchemaExists -SchemaName $schema -Database $TargetDatabase -ConnectionInfo $ConnectionInfo
        if ($schemaExists -eq $false)
        {
            $tmp = "CREATE SCHEMA $(ConvertTo-SqlIdentifier $schema)"
            Invoke-SqlcmdEx -Sql $tmp -Database $TargetDatabase -ConnectionInfo $ConnectionInfo -Statistics $false
        }

        $definition = $row.definition
        $definition = $definition.Replace("'", "''")

        $sql = "EXEC ('$definition')"
        $null = Invoke-SqlcmdEx -Sql $sql -Database $TargetDatabase -ConnectionInfo $ConnectionInfo
    }

    Write-Progress -Activity "Copy functions" -Completed
}
