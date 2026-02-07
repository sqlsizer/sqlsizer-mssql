function Clear-Database
{
    [cmdletbinding()]
    param
    (
        [Parameter(Mandatory = $true)]
        [string]$Database,

        [Parameter(Mandatory = $false)]
        [bool]$UseTruncate = $false,

        [Parameter(Mandatory = $true)]
        [DatabaseInfo]$DatabaseInfo,

        [Parameter(Mandatory = $true)]
        [SqlConnectionInfo]$ConnectionInfo
    )

    if ($true -eq $UseTruncate)
    {
        Remove-ForeignKeys -Database $Database -DatabaseInfo $DatabaseInfo -ConnectionInfo $ConnectionInfo
    }

    $i = 0
    foreach ($table in $DatabaseInfo.Tables)
    {
        $i += 1
        Write-Progress -Activity "Database truncate" -PercentComplete (100 * ($i / ($DatabaseInfo.Tables.Count)))

        if ($table.IsHistoric -eq $true)
        {
            continue
        }

        if ($table.HasHistory -eq $true)
        {
            $historyTable = $DatabaseInfo.Tables | Where-Object { ($_.IsHistoric -eq $true) -and ($_.HistoryOwner -eq $table.TableName) -and ($_.HistoryOwnerSchema -eq $table.SchemaName) }

            $sql = "ALTER TABLE " + $table.SchemaName + ".[" + $table.TableName + "] SET ( SYSTEM_VERSIONING = OFF )"
            $null = Invoke-SqlcmdEx -Sql $sql -Database $Database -ConnectionInfo $ConnectionInfo

            $sql = "DELETE FROM " + $table.SchemaName + "." + $table.TableName
            $null = Invoke-SqlcmdEx -Sql $sql -Database $Database -ConnectionInfo $ConnectionInfo

            $sql = "DELETE FROM " + $historyTable.SchemaName + "." + $historyTable.TableName
            $null = Invoke-SqlcmdEx -Sql $sql -Database $Database -ConnectionInfo $ConnectionInfo

            $sql = "ALTER TABLE " + $table.SchemaName + ".[" + $table.TableName + "] SET ( SYSTEM_VERSIONING = ON  (HISTORY_TABLE = " + $historyTable.SchemaName + ".[" + $historyTable.TableName + "] ))"
            $null = Invoke-SqlcmdEx -Sql $sql -Database $Database -ConnectionInfo $ConnectionInfo
        }
        else
        {
            if ($true -eq $UseTruncate)
            {
                $sql = "TRUNCATE TABLE " + $table.SchemaName + "." + $table.TableName
                $null = Invoke-SqlcmdEx -Sql $sql -Database $Database -ConnectionInfo $ConnectionInfo
            }
            else
            {
                $sql = "DELETE FROM " + $table.SchemaName + "." + $table.TableName
                $null = Invoke-SqlcmdEx -Sql $sql -Database $Database -ConnectionInfo $ConnectionInfo
            }
        }
    }

    if ($true -eq $UseTruncate)
    {
        Restore-ForeignKeys -Database $Database -DatabaseInfo $DatabaseInfo -ConnectionInfo $ConnectionInfo
    }

    Write-Progress -Activity "Database truncate" -Completed
}
