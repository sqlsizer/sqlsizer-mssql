function Remove-FoundSubsetFromDatabase
{
    [cmdletbinding()]
    param
    (
        [Parameter(Mandatory = $true)]
        [string]$SessionId,

        [Parameter(Mandatory = $true)]
        [string]$Database,
        
        [Parameter(Mandatory = $false)]
        [int]$Step = 100000,

        [Parameter(Mandatory = $true)]
        [DatabaseInfo]$DatabaseInfo,

        [Parameter(Mandatory = $true)]
        [SqlConnectionInfo]$ConnectionInfo
    )

    function GetWhere
    {
        param (
            [string]$Database,
            [SubsettingTableResult]$TableInfo,
            [DatabaseInfo]$DatabaseInfo
        )

        $table = $DatabaseInfo.Tables | Where-Object { ($_.SchemaName -eq $TableInfo.SchemaName) -and ($_.TableName -eq $TableInfo.TableName) }
        $primaryKey = $table.PrimaryKey
        $where = " WHERE EXISTS(SELECT * FROM SqlSizer_$SessionId.$($TableInfo.SchemaName)_$($TableInfo.TableName) e WHERE "

        $conditions = @()
        $i = 0
        foreach ($column in $primaryKey)
        {
            $conditions += " e.Key$i" + " = t." + $column.Name
            $i += 1
        }

        $where += [string]::Join(' AND ', $conditions) 
        $where += ")"
        
        $where
    }

    Write-Progress -Activity "Removing subset $SessionId" -PercentComplete 0

    $subsetTables = Get-SubsetTables -Database $Database -DatabaseInfo $DatabaseInfo -ConnectionInfo $ConnectionInfo -SessionId $SessionId
    
    $i = 0
    foreach ($table in $subsetTables)
    {
        $i += 1

        Write-Progress -Activity "Removing subset $SessionId" -PercentComplete (100 * ($i / ($subsetTables.Count))) -CurrentOperation "Table $($table.SchemaName).$($table.TableName)"

        $schema = $table.SchemaName
        $tableName = $table.TableName

        if ($table.CanBeDeleted -eq $false)
        {
            continue
        }

        $where = GetWhere -Database $Database -TableInfo $table -DatabaseInfo $DatabaseInfo


        if ($ConnectionInfo.IsSynapse -eq $true)
        {
            $sql = "DELETE t FROM " + $schema + ".[" + $tableName + "] t " + $where
            $null = Invoke-SqlcmdEx -Sql $sql -Database $Database -ConnectionInfo $ConnectionInfo
        }
        else
        {
            $top = ""

            if ($Step -ne $null)
            {
                $top = " TOP ($Step) "
            }

            do
            {
                $sql = "DELETE $top t FROM " + $schema + ".[" + $tableName + "] t " + $where + " SELECT @@ROWCOUNT as Removed"
                $result = Invoke-SqlcmdEx -Sql $sql -Database $Database -ConnectionInfo $ConnectionInfo
            }
            while ($result.Removed -gt 0)
        }
    }

    Write-Progress -Activity "Removing subset $SessionId" -Completed
}


