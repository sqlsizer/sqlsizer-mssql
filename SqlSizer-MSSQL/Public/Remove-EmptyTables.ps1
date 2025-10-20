function Remove-EmptyTables
{
    [cmdletbinding()]
    param
    (
        [Parameter(Mandatory = $true)]
        [string]$Database,

        [Parameter(Mandatory = $true)]
        [DatabaseInfo]$DatabaseInfo,

        [Parameter(Mandatory = $true)]
        [SqlConnectionInfo]$ConnectionInfo
    )

    $i = 0
    foreach ($table in $DatabaseInfo.Tables)
    {
        Write-Progress -Activity "Removing empty tables" -PercentComplete (100 * ($i / ($DatabaseInfo.Tables.Count)))

        if ($table.Statistics.Rows -ne 0)
        {
            continue
        }

        $null = Remove-Table -Database $Database -DatabaseInfo $DatabaseInfo -ConnectionInfo $ConnectionInfo `
                    -SchemaName $table.SchemaName -TableName $table.TableName

        $i += 1
    }

    Write-Progress -Activity "Removing empty tables" -Completed
}
