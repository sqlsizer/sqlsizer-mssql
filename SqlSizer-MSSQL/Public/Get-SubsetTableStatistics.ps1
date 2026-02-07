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

    $sql = "SELECT t.[Schema] as [SchemaName],
                   t.TableName,
                   SUM([ToProcess]) as [Count]
            FROM [SqlSizer].[Operations] o
            INNER JOIN [SqlSizer].[Tables] t ON o.[Table] = t.Id
            WHERE (o.FoundIteration = $Iteration OR $Iteration = -1) AND o.FoundIteration >= $StartIteration AND o.ToProcess <> 0 AND o.SessionId = '$SessionId'
            GROUP BY t.[Schema], t.TableName
            ORDER BY [Schema], [TableName]"

    $rows = Invoke-SqlcmdEx -Sql $sql -Database $Database -ConnectionInfo $ConnectionInfo

    $result = [System.Collections.Generic.List[SubsettingTableResult]]@()
    foreach ($row in $rows)
    {
        $tableInfo = $DatabaseInfo.Tables | Where-Object { ($_.SchemaName -eq $row.SchemaName) -and ($_.TableName -eq $row.TableName) }

        if ($null -eq $tableInfo)
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

    return $result
}
