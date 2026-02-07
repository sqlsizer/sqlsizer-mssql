function Format-Indexes
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
    Write-Progress -Activity "Rebuilding indexes on database" -PercentComplete 0

    foreach ($table in $DatabaseInfo.Tables)
    {
        $sql = "SET QUOTED_IDENTIFIER ON; ALTER INDEX ALL ON " + $table.SchemaName + "." + $table.TableName + " REBUILD "
        $null = Invoke-SqlcmdEx -Sql $sql -Database $Database -ConnectionInfo $ConnectionInfo -Statistics $false
    }

    Write-Progress -Activity "Rebuilding indexes on database" -Completed
}
