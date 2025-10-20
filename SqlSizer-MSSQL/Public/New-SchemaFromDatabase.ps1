function New-SchemaFromDatabase
{
    [cmdletbinding()]
    param
    (
        [Parameter(Mandatory = $true)]
        [string]$SourceDatabase,

        [Parameter(Mandatory = $true)]
        [string]$TargetDatabase,

        [Parameter(Mandatory = $true)]
        [string]$SchemaName,

        [Parameter(Mandatory = $true)]
        [string]$NewSchemaName,

        [Parameter(Mandatory = $true)]
        [bool]$CopyData,

        [Parameter(Mandatory = $true)]
        [DatabaseInfo]$DatabaseInfo,

        [Parameter(Mandatory = $true)]
        [SqlConnectionInfo]$ConnectionInfo
    )

    Write-Progress -Activity "Copy schema $SchemaName to $NewSchemaName in $TargetDatabase database" -PercentComplete 0

    $schemaAlreadyExists = Test-SchemaExists -SchemaName $NewSchemaName -Database $TargetDatabase -ConnectionInfo $ConnectionInfo

    if ($schemaAlreadyExists)
    {
        Write-Progress -Activity "Copy schema $SchemaName to $NewSchemaName in $TargetDatabase database" -Completed
        Write-Verbose "Schema $NewSchemaName already exists in $TargetDatabase database. Provide different name"
        return
    }
    $sql = "CREATE SCHEMA $NewSchemaName"
    $null = Invoke-SqlcmdEx -Sql $sql -Database $TargetDatabase -ConnectionInfo $ConnectionInfo -Statistics $false

    # copy tables
    $i = 0
    foreach ($table in $DatabaseInfo.Tables)
    {
        Write-Progress -Activity "Copy schema $SchemaName to $NewSchemaName in $TargetDatabase database" -PercentComplete (100 * ($i / ($DatabaseInfo.Tables.Count))) -CurrentOperation "Table $($table.SchemaName).$($table.TableName)"
        if ($table.SchemaName -eq $SchemaName)
        {
            $null = New-DataTableClone -SourceDatabase $SourceDatabase -TargetDatabase $TargetDatabase -DatabaseInfo $DatabaseInfo -SchemaName $SchemaName -TableName $table.TableName `
                -CopyData $CopyData -NewSchemaName $NewSchemaName -NewTableName $table.TableName -ConnectionInfo $ConnectionInfo
        }
        $i = $i + 1
    }

    # create foreign keys for new schema
    foreach ($table in $DatabaseInfo.Tables)
    {
        if ($table.SchemaName -eq $SchemaName)
        {
            foreach ($fk in $table.ForeignKeys)
            {
                $schema = $fk.Schema
                if ($schema -eq $SchemaName)
                {
                    $schema = $NewSchemaName
                }

                $sql = "ALTER TABLE $($NewSchemaName).$($table.TableName) ADD CONSTRAINT $($fk.Name) FOREIGN KEY ($([string]::Join(',', $fk.FkColumns))) REFERENCES $($schema).$($fk.Table) ($([string]::Join(',', $fk.Columns)))"
                $null = Invoke-SqlcmdEx -Sql $sql -Database $TargetDatabase -ConnectionInfo $ConnectionInfo -Silent $false -Statistics $false
            }
        }
    }

    Write-Progress -Activity "Copy schema $SchemaName" -Completed
}


