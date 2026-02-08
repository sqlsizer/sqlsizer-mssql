function Enable-AllTablesTriggers
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

    Write-Progress -Activity "Enabling all triggers on all tables" -PercentComplete 0

    foreach ($table in $DatabaseInfo.Tables)
    {
        Disable-TableTriggers -Database $Database -ConnectionInfo $ConnectionInfo -SchemaName $table.SchemaName -TableName $table.TableName
    }

    Write-Progress -Activity "Enabling all triggers on all tables" -Completed
}
