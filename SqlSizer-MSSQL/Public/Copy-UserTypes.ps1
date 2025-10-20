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

    $sql = "select t.user_type_id, t.name as [user_type_name], b.name as [data_type], t.max_length as [length]
    from sys.types t
    inner join sys.types b ON t.system_type_id = b.system_type_id and b.system_type_id = b.user_type_id
    where t.is_user_defined = 1"
    $rows = Invoke-SqlcmdEx -Sql $sql -Database $SourceDatabase -ConnectionInfo $ConnectionInfo

    foreach ($row in $rows)
    {
        $dataType = $row["data_type"]

        if ($dataType -in @('char', 'varchar', 'nchar', 'nvarchar'))
        {
            $dataType += "($($row["length"]))"
        }

        $sql = "CREATE TYPE $($row["user_type_name"]) FROM $dataType"
        $null = Invoke-SqlcmdEx -Sql $sql -Database $TargetDatabase -ConnectionInfo $ConnectionInfo
    }

    Write-Progress -Activity "Copy user types" -Completed
}
