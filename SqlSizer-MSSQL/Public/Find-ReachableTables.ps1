function Find-ReachableTables
{
    [cmdletbinding()]
    param
    (
        [Parameter(Mandatory = $true)]
        [Query2[]]$Queries,

        [Parameter(Mandatory = $true)]
        [DatabaseInfo]$DatabaseInfo,

        [Parameter(Mandatory = $true)]
        [SqlConnectionInfo]$ConnectionInfo
    )

    $unreachable = Find-UnreachableTables -DatabaseInfo $DatabaseInfo -Queries $Queries

    $toReturn = @()
    foreach ($table in $DatabaseInfo.Tables)
    {
        $unreachableTable = $unreachable | Where-Object { ($_.SchemaName -eq $table.SchemaName) -and ($_.TableName -eq $table.TableName) }
        $isUnreachable = $null -ne $unreachableTable

        if ($isUnreachable -eq $false)
        {
            $item = New-Object TableInfo2
            $item.SchemaName = $table.SchemaName
            $item.TableName = $table.TableName
            $toReturn += $item
        }
    }

    return $toReturn
}
