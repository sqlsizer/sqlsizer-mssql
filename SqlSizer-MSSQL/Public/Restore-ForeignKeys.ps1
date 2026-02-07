function Restore-ForeignKeys
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
    Write-Progress -Activity "Restoring foreign keys" -PercentComplete 0

    # create all foreign keys
    foreach ($table in $DatabaseInfo.Tables)
    {
        foreach ($fk in $table.ForeignKeys)
        {
            New-ForeignKey -Database $Database -ConnectionInfo $ConnectionInfo `
                            -SchemaName $table.SchemaName -TableName $table.TableName -FkName $fk.Name `
                            -Columns $fk.Columns `
                            -FkColumns $fk.FkColumns `
                            -DeleteRule $fk.DeleteRule `
                            -UpdateRule $fk.UpdateRule
        }
    }


    Write-Progress -Activity "Restoring foreign keys" -Completed
}
