function Get-SubsetTables
{
    [cmdletbinding()]
    [outputtype([System.Object[]])]
    param
    (
        [Parameter(Mandatory = $true)]
        [string]$SessionId,

        [Parameter(Mandatory = $true)]
        [string]$Database,

        [Parameter(Mandatory = $true)]
        [DatabaseInfo]$DatabaseInfo,

        [Parameter(Mandatory = $false)]
        [boolean]$Negation = $false,

        [Parameter(Mandatory = $true)]
        [SqlConnectionInfo]$ConnectionInfo
    )

    $tables = Get-SubsetTableStatistics -Database $Database -Connection $ConnectionInfo -DatabaseInfo $DatabaseInfo -SessionId $SessionId

    if ($Negation -eq $false)
    {
        $filtered = $tables | Where-Object -Property RowCount -GT 0

        return $filtered
    }
    else
    {
        $filtered = $tables | Where-Object -Property RowCount -EQ 0

        return $filtered
    }
}
