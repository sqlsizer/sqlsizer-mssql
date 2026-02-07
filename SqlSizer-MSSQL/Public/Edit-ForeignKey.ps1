function Edit-ForeignKey
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

        [Parameter(Mandatory = $true)]
        [string]$FkName,

        [Parameter(Mandatory = $true)]
        [ForeignKeyRule]$DeleteRule,

        [Parameter(Mandatory = $true)]
        [ForeignKeyRule]$UpdateRule,

        [Parameter(Mandatory = $true)]
        [DatabaseInfo]$DatabaseInfo,

        [Parameter(Mandatory = $true)]
        [SqlConnectionInfo]$ConnectionInfo
    )
    Write-Progress -Activity "Editing FK $FkName on $SchemaName.$TableName" -PercentComplete 0

    # get info about fk
    $table = $DatabaseInfo.Tables | Where-Object { ($_.SchemaName -eq $SchemaName) -and ($_.TableName -eq $TableName) }
    $fk = $table.ForeignKeys | Where-Object { ($_.Name -eq $FkName) }

    # Drop foreign key
    $sql = "ALTER TABLE " + $SchemaName + "." + $TableName + " DROP CONSTRAINT " + $FkName
    $null = Invoke-SqlcmdEx -Sql $sql -Database $Database -ConnectionInfo $ConnectionInfo

    # Recreate it
    $sql = "ALTER TABLE " + $SchemaName + "." + $TableName + " WITH CHECK ADD CONSTRAINT " + $FkName

    $fkNames = @()
    foreach ($column in $fk.FkColumns)
    {
        $fkNames += $column.Name
    }
    $sql += " FOREIGN KEY (" + [string]::Join(',', $fkNames) + ")"

    $names = @()
    foreach ($column in $fk.Columns)
    {
        $names += $column.Name
    }
    $sql += " REFERENCES $($fk.Schema).$($fk.Table) (" + [string]::Join(',', $names) + ")"

    try
    {
        $rules = ""
        if ($DeleteRule -eq [ForeignKeyRule]::Cascade)
        {
            $rules += " ON DELETE CASCADE"
        }

        if ($DeleteRule -eq [ForeignKeyRule]::SetNull)
        {
            $rules += " ON DELETE SET NULL"
        }

        if ($DeleteRule -eq [ForeignKeyRule]::SetDefault)
        {
            $rules += " ON DELETE SET DEFAULT"
        }

        if ($UpdateRule -eq [ForeignKeyRule]::Cascade)
        {
            $rules += " ON UPDATE CASCADE"
        }

        if ($UpdateRule -eq [ForeignKeyRule]::SetNull)
        {
            $rules += " ON UPDATE SET NULL"
        }

        if ($UpdateRule -eq [ForeignKeyRule]::SetDefault)
        {
            $rules += " ON UPDATE SET DEFAULT"
        }
        $null = Invoke-SqlcmdEx -Sql ($sql + $rules) -Database $Database -ConnectionInfo $ConnectionInfo -Statistics $false
    }
    catch
    {
        $rules = ""
        if ($fk.DeleteRule -eq [ForeignKeyRule]::Cascade)
        {
            $rules += " ON DELETE CASCADE"
        }

        if ($fk.DeleteRule -eq [ForeignKeyRule]::SetNull)
        {
            $rules += " ON DELETE SET NULL"
        }

        if ($fk.DeleteRule -eq [ForeignKeyRule]::SetDefault)
        {
            $rules += " ON DELETE SET DEFAULT"
        }

        if ($fk.UpdateRule -eq [ForeignKeyRule]::Cascade)
        {
            $rules += " ON UPDATE CASCADE"
        }

        if ($fk.UpdateRule -eq [ForeignKeyRule]::SetNull)
        {
            $rules += " ON UPDATE SET NULL"
        }

        if ($fk.UpdateRule -eq [ForeignKeyRule]::SetDefault)
        {
            $rules += " ON UPDATE SET DEFAULT"
        }

        Write-Verbose "Error: $_ Cannot change $FkName. Reverting change..."
        $null = Invoke-SqlcmdEx -Sql ($sql + $rules) -Database $Database -ConnectionInfo $ConnectionInfo -Statistics $false
    }

    Write-Progress -Activity "Editing FK $FkName on $SchemaName.$TableName" -Completed
}

