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

    $sql = "select r.ROUTINE_SCHEMA as [schema], r.ROUTINE_DEFINITION as definition from [INFORMATION_SCHEMA].[ROUTINES] r WHERE r.ROUTINE_DEFINITION IS NOT NULL AND r.ROUTINE_TYPE ='FUNCTION'"
    $rows = Invoke-SqlcmdEx -Sql $sql -Database $SourceDatabase -ConnectionInfo $ConnectionInfo

    foreach ($row in $rows)
    {
        $schema = $row.schema

        $schemaExists = Test-SchemaExists -SchemaName $schema -Database $TargetDatabase -ConnectionInfo $ConnectionInfo
        if ($schemaExists -eq $false)
        {
            $tmp = "CREATE SCHEMA $schema"
            Invoke-SqlcmdEx -Sql $tmp -Database $TargetDatabase -ConnectionInfo $ConnectionInfo -Statistics $false
        }

        $definition = $row.definition
        $definition = $definition.Replace("'", "''")

        $sql = "EXEC ('$definition')"
        $null = Invoke-SqlcmdEx -Sql $sql -Database $TargetDatabase -ConnectionInfo $ConnectionInfo
    }

    Write-Progress -Activity "Copy functions" -Completed
}
