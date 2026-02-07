function Test-Queries
{
    [cmdletbinding()]
    [outputtype([System.Boolean])]
    param
    (
        [Parameter(Mandatory = $true)]
        [string]$Database,

        [Parameter(Mandatory = $true)]
        [Query[]]$Queries,

        [Parameter(Mandatory = $false)]
        [ColorMap]$ColorMap = $null,

        [Parameter(Mandatory = $true)]
        [DatabaseInfo]$DatabaseInfo,

        [Parameter(Mandatory = $true)]
        [SqlConnectionInfo]$ConnectionInfo
    )

    $unreachable = Find-UnreachableTables -Queries $Queries -DatabaseInfo $DatabaseInfo -ColorMap $ColorMap

    if ($unreachable.Count -gt 0)
    {
        Write-Verbose "$($unreachable.Length) are not reachable by queries:"
        foreach ($item in $unreachable)
        {
            Write-Verbose $item
        }
        return $false
    }
    else
    {
        return $true
    }
}
