function New-EmptyCompactDatabase
{
    [outputtype([System.Boolean])]
    [cmdletbinding()]
    param
    (
        [Parameter(Mandatory = $true)]
        [string]$Database,

        [Parameter(Mandatory = $true)]
        [string]$NewDatabase,

        [Parameter(Mandatory = $true)]
        [DatabaseInfo]$DatabaseInfo,

        [Parameter(Mandatory = $true)]
        [SqlConnectionInfo]$ConnectionInfo
    )

    if ((Test-DatabaseOnline -Database $NewDatabase -ConnectionInfo $ConnectionInfo))
    {
        return $false
    }

    $sql = "CREATE DATABASE $NewDatabase"
    Invoke-SqlcmdEx -Sql $sql -Database $Database -ConnectionInfo $ConnectionInfo -Silent $false

    Copy-UserTypes -SourceDatabase $Database -TargetDatabase $NewDatabase -ConnectionInfo $ConnectionInfo
    Copy-Functions -SourceDatabase $Database -TargetDatabase $NewDatabase -ConnectionInfo $ConnectionInfo
    Copy-StoredProcedures -SourceDatabase $Database -TargetDatabase $NewDatabase -ConnectionInfo $ConnectionInfo

    foreach ($table in $DatabaseInfo.Tables)
    {
        New-DataTableClone -SourceDatabase $Database -TargetDatabase $NewDatabase -DatabaseInfo $DatabaseInfo -SchemaName $table.SchemaName -TableName $table.TableName `
            -CopyData $false -NewSchemaName $table.SchemaName -NewTableName $table.TableName -ConnectionInfo $ConnectionInfo
    }

    Copy-Constraints -SourceDatabase $Database -TargetDatabase $NewDatabase -ConnectionInfo $ConnectionInfo
    Copy-Sequences -SourceDatabase $Database -TargetDatabase $NewDatabase -ConnectionInfo $ConnectionInfo

    foreach ($table in $DatabaseInfo.Tables)
    {
        foreach ($fk in $table.ForeignKeys)
        {
            $sql = "ALTER TABLE $($table.SchemaName).$($table.TableName) ADD CONSTRAINT $($fk.Name) FOREIGN KEY ($([string]::Join(',', $fk.FkColumns))) REFERENCES $($fk.Schema).$($fk.Table) ($([string]::Join(',', $fk.Columns)))"
            Invoke-SqlcmdEx -Sql $sql -Database $NewDatabase -ConnectionInfo $ConnectionInfo -Silent $false
        }
    }

    return $true
}
