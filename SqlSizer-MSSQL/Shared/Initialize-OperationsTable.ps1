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
        [SqlConnectionInfo]$ConnectionInfo,

        [Parameter(Mandatory = $false)]
        [bool]$Statistics = $true
    )

    # load meta data
    $structure = [Structure]::new($DatabaseInfo)
    $sqlSizerInfo = Get-SqlSizerInfo -Database $Database -ConnectionInfo $ConnectionInfo -Statistics $Statistics
    $allTablesGroupedByName = $sqlSizerInfo.Tables | Group-Object -Property SchemaName, TableName -AsHashTable -AsString

    # initialize operations
    $tables = @($DatabaseInfo.Tables | Where-Object {
        ($_.PrimaryKey.Count -gt 0) -and
        ($_.SchemaName -notin @('SqlSizer', 'SqlSizerHistory')) -and
        (-not $_.SchemaName.StartsWith('SqlSizer'))
    })

    $tableIndex = 0
    $batchBuilder = [System.Text.StringBuilder]::new()
    foreach ($table in $tables)
    {
        $tableIndex++
        Write-Progress -Activity "Initializing traversal operations $SessionId" `
                       -Status "Building batched INSERTs" `
                       -CurrentOperation "$($table.SchemaName).$($table.TableName)" `
                       -PercentComplete ([int][Math]::Round(100 * ($tableIndex / [Math]::Max(1, $tables.Count))))

        $signature = $structure.Tables[$table]
        $processing = $structure.GetProcessingName($signature, $SessionId)
        $sqlSizerTable = $allTablesGroupedByName[$table.SchemaName + ", " + $table.TableName]

        if ($null -eq $sqlSizerTable)
        {
            continue
        }

        $tableId = $sqlSizerTable.Id

        [void]$batchBuilder.AppendLine("INSERT INTO SqlSizer.Operations([Table], [ToProcess], [Processed], [Status], [State], [Depth], [Created], [SessionId], [FoundIteration])
        SELECT $tableId, COUNT_BIG(*), 0, NULL, p.[State], 0, GETDATE(), '$SessionId', $StartIteration
        FROM $($processing) p
        WHERE p.Iteration >= $StartIteration
        GROUP BY [State];")
    }

    if ($batchBuilder.Length -gt 0)
    {
        $null = Invoke-SqlcmdEx -Sql $batchBuilder.ToString() -Database $Database -ConnectionInfo $ConnectionInfo -Statistics $Statistics
    }

    Write-Progress -Activity "Initializing traversal operations $SessionId" -Completed
}

