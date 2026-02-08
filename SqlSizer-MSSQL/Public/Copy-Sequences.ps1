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
	seq.name,
	seq.current_value,
	seq.increment,
	ISNULL(seq.maximum_value, 2147483647) as maximum_value, -- todo
	t.[name] as [type]
    FROM
        sys.sequences seq
    INNER JOIN
        sys.types t ON seq.system_type_id = t.system_type_id"

    $sequencesRows = Invoke-SqlcmdEx -Sql $sql -Database $SourceDatabase -ConnectionInfo $ConnectionInfo

    foreach ($row in $sequencesRows)
    {
        $sql = "IF NOT EXISTS(SELECT * FROM sys.objects WHERE object_id = OBJECT_ID('$($row["name"])') AND type = 'SO') BEGIN CREATE SEQUENCE [$($row["name"])] AS $($row["type"])  START WITH $($row["current_value"]) INCREMENT BY $($row["increment"]) MAXVALUE $($row["maximum_value"]) END"
        $null = Invoke-SqlcmdEx -Sql $sql -Database $TargetDatabase -ConnectionInfo $ConnectionInfo
    }
    Write-Progress -Activity "Copying sequences" -Completed
}
