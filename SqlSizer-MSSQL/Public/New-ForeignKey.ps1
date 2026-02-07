function New-ForeignKey
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
        [ColumnInfo[]]$Columns,

        [Parameter(Mandatory = $true)]
        [ColumnInfo[]]$FkColumns,

        [Parameter(Mandatory = $true)]
        [ForeignKeyRule]$DeleteRule,

        [Parameter(Mandatory = $true)]
        [ForeignKeyRule]$UpdateRule,

        [Parameter(Mandatory = $true)]
        [SqlConnectionInfo]$ConnectionInfo
    )
    Write-Progress -Activity "Creating FK $FkName on $SchemaName.$TableName" -PercentComplete 0

    $fkNames = @()
    foreach ($column in $FkColumns)
    {
        $fkNames += $column.Name
    }
    $sql += " FOREIGN KEY (" + [string]::Join(',', $fkNames) + ")"

    $names = @()
    foreach ($column in $Columns)
    {
        $names += $column.Name
    }
    $sql += " REFERENCES $($fk.Schema).$($fk.Table) (" + [string]::Join(',', $names) + ")"

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

    $null = Invoke-SqlcmdEx -Sql ($sql + $rules) -Database $Database -ConnectionInfo $ConnectionInfo

    Write-Progress -Activity "Creating FK $FkName on $SchemaName.$TableName" -Completed
}

