function Enable-ForeignKeys
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

    Write-Progress -Activity "Enabling foreign key checks on database" -PercentComplete 0
    $i = 0
    foreach ($table in $DatabaseInfo.Tables)
    {
        $i += 1
        Write-Progress -Activity "Enabling integrity checks on database" -PercentComplete (100 * ($i / $DatabaseInfo.Tables.Count))

        if ($table.SchemaName.StartsWith("SqlSizer"))
        {
            continue
        }

        if (-not (Test-TableExists -Database $Database -SchemaName $table.SchemaName -TableName $table.TableName -ConnectionInfo $ConnectionInfo))
        {
            continue
        }

        $sql = "ALTER TABLE $(ConvertTo-SqlIdentifier $table.SchemaName).$(ConvertTo-SqlIdentifier $table.TableName) WITH CHECK CHECK CONSTRAINT ALL"
        $null = Invoke-SqlcmdEx -Sql $sql -Database $Database -ConnectionInfo $ConnectionInfo -Statistics $false
    }

    Write-Progress -Activity "Enabling foreign key on database" -Completed
}
