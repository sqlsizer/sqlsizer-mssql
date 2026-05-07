function Copy-UserTypes
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

    Write-Progress -Activity "Copy user types" -PercentComplete 0

    $sql = "select t.user_type_id, SCHEMA_NAME(t.schema_id) as [schema], t.name as [user_type_name], b.name as [data_type], t.max_length as [length], t.[precision], t.scale, t.is_nullable
    from sys.types t
    inner join sys.types b ON t.system_type_id = b.system_type_id and b.system_type_id = b.user_type_id
    where t.is_user_defined = 1 and t.is_table_type = 0"
    $rows = Invoke-SqlcmdEx -Sql $sql -Database $SourceDatabase -ConnectionInfo $ConnectionInfo

    foreach ($row in $rows)
    {
        $schema = $row["schema"]
        $typeName = $row["user_type_name"]
        $schemaExists = Test-SchemaExists -SchemaName $schema -Database $TargetDatabase -ConnectionInfo $ConnectionInfo
        if ($schemaExists -eq $false)
        {
            $tmp = "CREATE SCHEMA $(ConvertTo-SqlIdentifier $schema)"
            Invoke-SqlcmdEx -Sql $tmp -Database $TargetDatabase -ConnectionInfo $ConnectionInfo -Statistics $false
        }

        $dataType = $row["data_type"]

        if ($dataType -in @('char', 'varchar', 'binary', 'varbinary'))
        {
            $length = if ([int]$row["length"] -eq -1) { "max" } else { [string]$row["length"] }
            $dataType += "($length)"
        }
        elseif ($dataType -in @('nchar', 'nvarchar'))
        {
            $length = if ([int]$row["length"] -eq -1) { "max" } else { [string]([int]$row["length"] / 2) }
            $dataType += "($length)"
        }
        elseif ($dataType -in @('decimal', 'numeric'))
        {
            $dataType += "($($row["precision"]),$($row["scale"]))"
        }

        $nullability = if ([bool]$row["is_nullable"]) { "NULL" } else { "NOT NULL" }
        $sql = "CREATE TYPE $(ConvertTo-SqlIdentifier $schema).$(ConvertTo-SqlIdentifier $typeName) FROM $dataType $nullability"
        $result = Invoke-SqlcmdEx -Sql $sql -Database $TargetDatabase -ConnectionInfo $ConnectionInfo -Silent $true
        if ($result -eq $false)
        {
            Write-Warning "Skipped user type [$schema].[$typeName] in [$TargetDatabase]: it may already exist or reference an unavailable type."
        }
    }

    Write-Progress -Activity "Copy user types" -Completed
}
