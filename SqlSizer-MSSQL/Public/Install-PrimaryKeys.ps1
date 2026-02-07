function Install-PrimaryKeys
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

    foreach ($table in $DatabaseInfo.Tables)
    {
        if (($null -ne $table.PrimaryKey) -and ($table.PrimaryKey[0].IsPresent -eq $false))
        {
            $names = @()
            foreach ($pkColumn in $table.PrimaryKey)
            {
                $names += $pkColumn.Name
                $sql = "ALTER TABLE $($table.SchemaName).$($table.TableName) ALTER COLUMN $($pkColumn.Name) int NOT NULL"
                $null = Invoke-SqlcmdEx -Sql $sql -Database $Database -ConnectionInfo $ConnectionInfo
            }
            $sql = "ALTER TABLE $($table.SchemaName).$($table.TableName) ADD CONSTRAINT PK_$($table.SchemaName)_$($table.TableName) PRIMARY KEY NONCLUSTERED ($([string]::Join(',', $names))) NOT ENFORCED"
            $null = Invoke-SqlcmdEx -Sql $sql -Database $Database -ConnectionInfo $ConnectionInfo

            foreach ($pkColumn in $table.PrimaryKey)
            {
                $pkColumn.IsPresent = $true
            }
        }
    }

}

