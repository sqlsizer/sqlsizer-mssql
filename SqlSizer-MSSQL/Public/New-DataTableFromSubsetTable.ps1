function New-DataTableFromSubsetTable
{
    [cmdletbinding()]
    param
    (
        [Parameter(Mandatory = $true)]
        [string]$SessionId,

        [Parameter(Mandatory = $true)]
        [string]$Database,

        [Parameter(Mandatory = $true)]
        [string]$NewSchemaName,

        [Parameter(Mandatory = $true)]
        [string]$NewTableName,

        [Parameter(Mandatory = $true)]
        [string]$SchemaName,

        [Parameter(Mandatory = $true)]
        [string]$TableName,

        [Parameter(Mandatory = $true)]
        [bool]$CopyData,

        [Parameter(Mandatory = $true)]
        [DatabaseInfo]$DatabaseInfo,

        [Parameter(Mandatory = $true)]
        [SqlConnectionInfo]$ConnectionInfo
    )

    $null = New-DataTableFromView -Database $Database -NewSchemaName $NewSchemaName -NewTableName $NewTableName `
        -ViewSchemaName "SqlSizer_$($SessionId)" -ViewName "Result_$($SchemaName)_$($TableName)" `
        -CopyData $CopyData -ConnectionInfo $ConnectionInfo

    # setup primary key
    foreach ($table in $DatabaseInfo.Tables)
    {
        if (($table.SchemaName -eq $SchemaName) -and ($table.TableName -eq $TableName))
        {
            $sql = "ALTER TABLE [$NewSchemaName].[$NewTableName] ADD PRIMARY KEY ($([string]::Join(',', $table.PrimaryKey)))"
            $null = Invoke-SqlcmdEx -Sql $sql -Database $Database -ConnectionInfo $ConnectionInfo -Statistics $false
        }
    }
}
