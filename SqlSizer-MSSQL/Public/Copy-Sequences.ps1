function Copy-Sequences
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

    Write-Progress -Activity "Copying sequences" -PercentComplete 0

    $sql = "SELECT
    SCHEMA_NAME(seq.schema_id) as [schema],
	seq.name,
	seq.current_value,
	seq.increment,
	seq.minimum_value,
	seq.maximum_value,
    seq.is_cycling,
	t.[name] as [type]
    FROM
        sys.sequences seq
    INNER JOIN
        sys.types t ON seq.system_type_id = t.system_type_id"

    $sequencesRows = Invoke-SqlcmdEx -Sql $sql -Database $SourceDatabase -ConnectionInfo $ConnectionInfo

    foreach ($row in $sequencesRows)
    {
        $schema = $row["schema"]
        $name = $row["name"]
        $schemaExists = Test-SchemaExists -SchemaName $schema -Database $TargetDatabase -ConnectionInfo $ConnectionInfo
        if ($schemaExists -eq $false)
        {
            $tmp = "CREATE SCHEMA $(ConvertTo-SqlIdentifier $schema)"
            Invoke-SqlcmdEx -Sql $tmp -Database $TargetDatabase -ConnectionInfo $ConnectionInfo -Statistics $false
        }

        $minimum = if ($null -eq $row["minimum_value"]) { "NO MINVALUE" } else { "MINVALUE $($row["minimum_value"])" }
        $maximum = if ($null -eq $row["maximum_value"]) { "NO MAXVALUE" } else { "MAXVALUE $($row["maximum_value"])" }
        $cycle = if ([bool]$row["is_cycling"]) { "CYCLE" } else { "NO CYCLE" }
        $qualifiedName = "$(ConvertTo-SqlIdentifier $schema).$(ConvertTo-SqlIdentifier $name)"
        $qualifiedLiteral = ConvertTo-SqlStringLiteral "$schema.$name"
        $sql = "IF OBJECT_ID($qualifiedLiteral, 'SO') IS NULL BEGIN CREATE SEQUENCE $qualifiedName AS $($row["type"]) START WITH $($row["current_value"]) INCREMENT BY $($row["increment"]) $minimum $maximum $cycle END"
        $null = Invoke-SqlcmdEx -Sql $sql -Database $TargetDatabase -ConnectionInfo $ConnectionInfo
    }
    Write-Progress -Activity "Copying sequences" -Completed
}
