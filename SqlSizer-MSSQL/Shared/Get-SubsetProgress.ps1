function Get-SubsetProgress
{
    [cmdletbinding()]
    param
    (
        [Parameter(Mandatory = $true)]
        [string]$Database,

        [Parameter(Mandatory = $true)]
        [SqlConnectionInfo]$ConnectionInfo
    )

    $result = New-Object -TypeName SubsettingProcess

    $sql = "SELECT ISNULL(SUM(ToProcess), 0) as to_process FROM SqlSizer.Operations WHERE Status = 0 OR Status IS NULL"
    $row = Invoke-SqlcmdEx -Sql $sql -Database $Database -ConnectionInfo $ConnectionInfo
    $result.ToProcess = $row["to_process"]

    $sql = "SELECT ISNULL(SUM(ToProcess), 0) as processed FROM SqlSizer.Operations WHERE Status = 1"
    $row = Invoke-SqlcmdEx -Sql $sql -Database $Database -ConnectionInfo $ConnectionInfo
    $result.Processed = $row["processed"]

    return $result
}
