function Remove-ForeignKeys
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
    Write-Progress -Activity "Removing foreign keys" -PercentComplete 0

    foreach ($view in $DatabaseInfo.Views)
    {
        Remove-View -Database $Database -ViewName $view.ViewName -SchemaName $view.SchemaName -ConnectionInfo $ConnectionInfo
    }

    foreach ($table in $DatabaseInfo.Tables)
    {
        foreach ($fk in $table.ForeignKeys)
        {
            $sql = "ALTER TABLE " + $table.SchemaName + "." + $table.TableName + " DROP CONSTRAINT " + $fk.Name
            $null = Invoke-SqlcmdEx -Sql $sql -Database $Database -ConnectionInfo $ConnectionInfo
        }
    }

    foreach ($view in $DatabaseInfo.Views)
    {
        Restore-View -Database $Database -DatabaseInfo $DatabaseInfo -ViewName $view.ViewName -SchemaName $view.SchemaName -ConnectionInfo $ConnectionInfo
    }

    Write-Progress -Activity "Removing foreign keys" -Completed
}
