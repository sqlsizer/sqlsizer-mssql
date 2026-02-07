function Enable-Indexes
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

    Write-Progress -Activity "Enabling indexes" -PercentComplete 0

    foreach ($table in $DatabaseInfo.Tables)
    {
        foreach ($index in $table.Indexes)
        {
            $isPk = $false
            foreach ($indexColumn in $index.Columns)
            {
                foreach ($pkColumn in $table.PrimaryKey)
                {
                    if ($indexColumn -eq $pkColumn.Name)
                    {
                        $isPk = $true
                        break
                    }
                }
            }

            if ($isPk -eq $false)
            {
                $sql  = "ALTER INDEX $($index.Name) ON $($table.SchemaName).$($table.TableName) REBUILD"
                $null = Invoke-SqlcmdEx -Sql $sql -Database $Database -ConnectionInfo $ConnectionInfo
            }
        }
    }

    Write-Progress -Activity "Enabling indexes" -Completed
}
