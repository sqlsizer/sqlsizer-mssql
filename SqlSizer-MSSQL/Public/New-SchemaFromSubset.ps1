function New-SchemaFromSubset
{
    [cmdletbinding()]
    param
    (
        [Parameter(Mandatory = $true)]
        [string]$SessionId,

        [Parameter(Mandatory = $true)]
        [string]$Database,

        [Parameter(Mandatory = $true)]
        [string]$NewSchemaPrefix,

        [Parameter(Mandatory = $true)]
        [bool]$CopyData,

        [Parameter(Mandatory = $true)]
        [DatabaseInfo]$DatabaseInfo,

        [Parameter(Mandatory = $true)]
        [SqlConnectionInfo]$ConnectionInfo
    )

    $subsetTables = Get-SubsetTables -Database $Database -ConnectionInfo $ConnectionInfo -DatabaseInfo $DatabaseInfo -SessionId $SessionId

    # create tables
    foreach ($subsetTable in $subsetTables)
    {
        $null = New-DataTableFromSubsetTable -Database $Database -NewSchemaName "$($NewSchemaPrefix)_$($subsetTable.SchemaName)" -NewTableName "$($subsetTable.TableName)" `
            -SchemaName $subsetTable.SchemaName -TableName $subsetTable.TableName -CopyData $CopyData -DatabaseInfo $DatabaseInfo -ConnectionInfo $ConnectionInfo `
            -SessionId $SessionId
    }

    # create foreign keys
    foreach ($table in $DatabaseInfo.Tables)
    {
        $isSubsetTable = $subsetTables | Where-Object { ($_.SchemaName -eq $table.SchemaName) -and ($_.TableName -eq $table.TableName) }

        if ($null -ne $isSubsetTable)
        {
            foreach ($fk in $table.ForeignKeys)
            {
                $sql = "ALTER TABLE $($NewSchemaPrefix)_$($table.SchemaName).$($table.TableName) ADD CONSTRAINT $($fk.Name) FOREIGN KEY ($([string]::Join(',', $fk.FkColumns))) REFERENCES $($NewSchemaPrefix)_$($fk.Schema).$($fk.Table) ($([string]::Join(',', $fk.Columns)))"
                $null = Invoke-SqlcmdEx -Sql $sql -Database $Database -ConnectionInfo $ConnectionInfo -Silent $false
            }
        }
    }
}
