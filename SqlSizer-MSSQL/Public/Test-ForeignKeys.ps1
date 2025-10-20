function Test-ForeignKeys
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

    Write-Progress -Activity "Testing foreign keys" -PercentComplete 0

    $i = 0
    foreach ($table in $DatabaseInfo.Tables)
    {
        Write-Progress -Activity "Testing foreign keys" -PercentComplete (100 * ($i / $DatabaseInfo.Tables.Count))

        foreach ($fk in $table.ForeignKeys)
        {
            $sql = "ALTER TABLE $($table.SchemaName).$($table.TableName) WITH CHECK CHECK CONSTRAINT $($fk.Name)"
            $ok = Invoke-SqlcmdEx -Sql $sql -Database $Database -ConnectionInfo $ConnectionInfo -Silent $false -Statistics $false

            if ($ok -eq $false)
            {
                Write-Verbose "Problem with FK $($fk.Name)"
            }
        }
        $i += 1
    }

    Write-Progress -Activity "Testing foreign keys" -Completed
}
