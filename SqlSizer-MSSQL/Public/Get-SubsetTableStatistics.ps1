function Get-SubsetTableStatistics
{
    [cmdletbinding()]
    param
    (
        [Parameter(Mandatory = $true)]
        [string]$SessionId,

        [Parameter(Mandatory = $false)]
        [int]$Iteration = -1,

        [Parameter(Mandatory = $false)]
        [int]$StartIteration = 0,

        [Parameter(Mandatory = $true)]
        [string]$Database,

        [Parameter(Mandatory = $true)]
        [DatabaseInfo]$DatabaseInfo,

        [Parameter(Mandatory = $true)]
        [SqlConnectionInfo]$ConnectionInfo
    )

    $result = [System.Collections.Generic.List[SubsettingTableResult]]@()
    $structure = [Structure]::new($DatabaseInfo)
    $includedStates = Get-IncludedTraversalStateSqlList

    foreach ($tableInfo in $DatabaseInfo.Tables)
    {
        if (($tableInfo.PrimaryKey.Count -eq 0) -or ($tableInfo.SchemaName.StartsWith('SqlSizer')))
        {
            continue
        }

        $signature = $structure.Tables[$tableInfo]
        if (($null -eq $signature) -or ($signature -eq ""))
        {
            continue
        }

        $processing = $structure.GetProcessingName($signature, $SessionId)
        $keys = @()
        for ($i = 0; $i -lt $tableInfo.PrimaryKey.Count; $i++)
        {
            $keys += "Key$i"
        }

        $sql = "SELECT COUNT(*) AS [Count]
                FROM (
                    SELECT DISTINCT $([string]::Join(', ', $keys))
                    FROM $processing
                    WHERE ([Iteration] = $Iteration OR $Iteration = -1)
                        AND [Iteration] >= $StartIteration
                        AND [State] IN ($includedStates)
                ) subsetRows"

        $row = Invoke-SqlcmdEx -Sql $sql -Database $Database -ConnectionInfo $ConnectionInfo
        if ($null -eq $row)
        {
            continue
        }

        $obj = New-Object -TypeName SubsettingTableResult
        $obj.SchemaName = $tableInfo.SchemaName
        $obj.TableName = $tableInfo.TableName
        $obj.PrimaryKeySize = $tableInfo.PrimaryKey.Count
        $obj.CanBeDeleted = $tableInfo.IsHistoric -eq $false
        $obj.RowCount = $row.Count
        $null = $result.Add($obj)
    }

    return $result | Sort-Object SchemaName, TableName
}
