function Get-SubsetUnreachableEdges
{
    [cmdletbinding()]
    param
    (
        [Parameter(Mandatory = $true)]
        [string]$Database,

        [Parameter(Mandatory = $true)]
        [DatabaseInfo]$DatabaseInfo,

        [Parameter(Mandatory = $true)]
        [SqlConnectionInfo]$ConnectionInfo
    )

    $structure = [Structure]::new($DatabaseInfo)

    $reachedEdges = New-Object 'System.Collections.Generic.HashSet[int]'
    $allEdges = New-Object 'System.Collections.Generic.HashSet[int]'

    $tmp = "SELECT DISTINCT [Id] FROM SqlSizer.ForeignKeys"
    $results = Invoke-SqlcmdEx -Sql $tmp -Database $Database -ConnectionInfo $ConnectionInfo

    foreach ($row in $results)
    {
        $null = $allEdges.Add($row.Id)
    }

    foreach ($signature in $structure.Signatures.Keys)
    {
        $processing = $structure.GetProcessingName($signature, $SessionId)

        $tmp = "SELECT DISTINCT [Fk] FROM $($processing) WHERE [FK] IS NOT NULL"
        $results = Invoke-SqlcmdEx -Sql $tmp -Database $Database -ConnectionInfo $ConnectionInfo

        foreach ($row in $results)
        {
            $null = $reachedEdges.Add($row.Fk)
        }
    }

    $allEdges.ExceptWith($reachedEdges)
    if ($allEdges.Count -gt 0)
    {
        $ids = ""
        foreach ($id in $allEdges)
        {
            if ($ids -ne "")
            {
                $ids += ","
            }
            $ids += (" " + $id)
        }

        $tmp = "SELECT f.[Name], t.[Schema] as FkSchema, t.[TableName] as FkTable, t2.[Schema], t2.[TableName]
                FROM SqlSizer.ForeignKeys f
                INNER JOIN SqlSizer.Tables t ON t.Id = f.FkTableId
                INNER JOIN SqlSizer.Tables t2 ON t2.Id = f.TableId
                WHERE f.[Id] IN ($($ids))"
        $results = Invoke-SqlcmdEx -Sql $tmp -Database $Database -ConnectionInfo $ConnectionInfo

        return $results
    }

    return $null
}
