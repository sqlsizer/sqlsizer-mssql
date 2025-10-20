function Initialize-OperationsTable
{
    [cmdletbinding()]
    param
    (
        [Parameter(Mandatory = $true)]
        [string]$SessionId,

        [Parameter(Mandatory = $false)]
        [int]$StartIteration = 0,

        [Parameter(Mandatory = $true)]
        [string]$Database,

        [Parameter(Mandatory = $true)]
        [DatabaseInfo]$DatabaseInfo,

        [Parameter(Mandatory = $true)]
        [SqlConnectionInfo]$ConnectionInfo
    )

    # load meta data
    $structure = [Structure]::new($DatabaseInfo)
    $sqlSizerInfo = Get-SqlSizerInfo -Database $Database -ConnectionInfo $ConnectionInfo
    $allTablesGroupedByName = $sqlSizerInfo.Tables | Group-Object -Property SchemaName, TableName -AsHashTable -AsString

    # initialize operations
    foreach ($table in $DatabaseInfo.Tables)
    {
        if ($table.PrimaryKey.Count -eq 0)
        {
            continue
        }
        if ($table.SchemaName -in @('SqlSizer', 'SqlSizerHistory'))
        {
            continue
        }

        if ($table.SchemaName.StartsWith('SqlSizer'))
        {
            continue
        }
        $signature = $structure.Tables[$table]
        $processing = $structure.GetProcessingName($signature, $SessionId)
        $table = $allTablesGroupedByName[$table.SchemaName + ", " + $table.TableName]
        $tableId = $table.Id

        if ($null -eq $table)
        {
            continue
        }

        $sql = "INSERT INTO SqlSizer.Operations([Table], [ToProcess], [Processed], [Status], [Color], [Depth], [Created], [SessionId], [FoundIteration])
        SELECT $tableId, COUNT(*), 0, NULL, p.[Color], 0, GETDATE(), '$SessionId', $StartIteration
        FROM $($processing) p
        WHERE p.Iteration >= $StartIteration
        GROUP BY [Color]"
        $null = Invoke-SqlcmdEx -Sql $sql -Database $Database -ConnectionInfo $ConnectionInfo
    }
}

