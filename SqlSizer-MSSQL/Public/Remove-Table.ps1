function Remove-Table
{
    [cmdletbinding()]
    param
    (
        [Parameter(Mandatory = $true)]
        [string]$Database,

        [Parameter(Mandatory = $true)]
        [string]$SchemaName,

        [Parameter(Mandatory = $true)]
        [string]$TableName,

        [Parameter(Mandatory = $false)]
        [bool]$RemoveFkColumns = $false,

        [Parameter(Mandatory = $false)]
        [bool]$DropFks = $true,

        [Parameter(Mandatory = $true)]
        [DatabaseInfo]$DatabaseInfo,

        [Parameter(Mandatory = $true)]
        [SqlConnectionInfo]$ConnectionInfo
    )

    $schemaExists = Test-SchemaExists -SchemaName $SchemaName -Database $Database -ConnectionInfo $ConnectionInfo
    if ($schemaExists -eq $false)
    {
        Write-Host "Schema $SchemaName doesn't exist"
        return $false
    }

    $tableExists = Test-TableExists -SchemaName $SchemaName -TableName $TableName -Database $Database -ConnectionInfo $ConnectionInfo
    if ($tableExists -eq $false)
    {
        Write-Host "Table $SchemaName.$TableName doesn't exist"
        return $false
    }

    # verify droping foreign keys columns first
    if ($true -eq $RemoveFkColumns)
    {
        foreach ($table in $DatabaseInfo.Tables)
        {  
            foreach ($fk in $table.ForeignKeys)
            {
                if (($fk.Schema -eq $SchemaName) -and ($fk.Table -eq $TableName))
                {
                    foreach ($fkColumn in $fk.FkColumns)
                    {
                        $isPartofPrimaryKey = $null -ne ($table.PrimaryKey | Where-Object { $_.Name -eq $fkColumn.Name })
                        if ($isPartofPrimaryKey)
                        {
                            throw "Cannot remove fk column $($fkColumn.Name) from table $($table.SchemaName).$($table.TableName). It's a part of primary key."
                        }
                    }
                }
            }
        }
    }

    # drop foreign keys
    if ($DropFks)
    {
        foreach ($table in $DatabaseInfo.Tables)
        { 
            foreach ($fk in $table.ForeignKeys)
            {
                if (($fk.Schema -eq $SchemaName) -and ($fk.Table -eq $TableName))
                {
                    $tableExists = Test-TableExists -SchemaName $table.SchemaName -TableName $table.TableName -Database $Database -ConnectionInfo $ConnectionInfo
                    if ($tableExists -eq $false)
                    {
                        continue
                    }

                    $sql = "ALTER TABLE [" + $table.SchemaName + "].[" + $table.TableName + "] DROP CONSTRAINT IF EXISTS $($fk.Name)"
                    $null = Invoke-SqlcmdEx -Sql $sql -Database $Database -ConnectionInfo $ConnectionInfo
                }
            }
        }
    }

    # drop foreign keys columns if requested
    if ($true -eq $RemoveFkColumns)
    {
        foreach ($table in $DatabaseInfo.Tables)
        { 
            
            
            foreach ($fk in $table.ForeignKeys)
            {
                if (($fk.Schema -eq $SchemaName) -and ($fk.Table -eq $TableName))
                {
                    foreach ($fkColumn in $fk.FkColumns)
                    {
                        # drop dependent indexes
                        foreach ($index in  $table.Indexes)
                        {
                            $isPartofIndex = $null -ne ($index.Columns | Where-Object { $_.Name -eq $fkColumn.Name })

                            if ($isPartofIndex)
                            {
                                $tableExists = Test-TableExists -SchemaName $table.SchemaName -TableName $table.TableName -Database $Database -ConnectionInfo $ConnectionInfo
                                if ($tableExists -eq $false)
                                {
                                    continue
                                }

                                $sql = "DROP INDEX $($index.Name) ON TABLE [" + $table.SchemaName + "].[" + $table.TableName + "]"
                                $null = Invoke-SqlcmdEx -Sql $sql -Database $Database -ConnectionInfo $ConnectionInfo
                            }
                        }

                        # drop column
                        $sql = "ALTER TABLE [" + $table.SchemaName + "].[" + $table.TableName + "] DROP COLUMN $($fkColumn.Name)"
                        $null = Invoke-SqlcmdEx -Sql $sql -Database $Database -ConnectionInfo $ConnectionInfo
                    }
                }
            }
        }
    }

    # drop all views in schema
    $table = $DatabaseInfo.Tables | Where-Object { ($_.SchemaName -eq $SchemaName) -and ($_.TableName -eq $TableName) }
    foreach ($view in $table.Views)
    {
        if ($ConnectionInfo.IsSynapse -eq $true)
        {
            $sql = "DROP VIEW  [$($view.SchemaName)].[$($view.ViewName)]"
        }
        else
        {
            $sql = "DROP VIEW IF EXISTS [$($view.SchemaName)].[$($view.ViewName)]"
        }
        $null = Invoke-SqlcmdEx -Sql $sql -Database $Database -ConnectionInfo $ConnectionInfo -Statistics $false
    }

    # drop table
    if ($ConnectionInfo.IsSynapse -eq $true)
    {
        $sql = "DROP TABLE [$($SchemaName)].[$($TableName)]"
    }
    else
    {
        $sql = "DROP TABLE IF EXISTS [$($SchemaName)].[$($TableName)]"
    }
    $null = Invoke-SqlcmdEx -Sql $sql -Database $Database -ConnectionInfo $ConnectionInfo -Statistics $false

    return $true
}
