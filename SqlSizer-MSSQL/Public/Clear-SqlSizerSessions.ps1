function Clear-SqlSizerSessions
{
    [cmdletbinding()]
    param
    (
        [Parameter(Mandatory = $true)]
        [string]$Database,

        [Parameter(Mandatory = $false)]
        [string[]]$Except,

        [Parameter(Mandatory = $true)]
        [DatabaseInfo]$DatabaseInfo,

        [Parameter(Mandatory = $true)]
        [SqlConnectionInfo]$ConnectionInfo
    )

    Write-Verbose "SqlSizer: Remove sessions"

    Update-DatabaseInfo -DatabaseInfo $DatabaseInfo -Database $Database -ConnectionInfo $ConnectionInfo

    $sql = "SELECT SessionId FROM SqlSizer.Sessions"
    $rows = Invoke-SqlcmdEx -Sql $sql -Database $Database -ConnectionInfo $ConnectionInfo

    foreach ($item in $rows)
    {
        if (($null -ne $Except) -and ($item.SessionId -in $Except))
        {
            continue
        }

        Clear-SqlSizerSession -SessionId $item.SessionId -Database $Database -DatabaseInfo $DatabaseInfo -ConnectionInfo $ConnectionInfo
    }

    Update-DatabaseInfo -DatabaseInfo $DatabaseInfo -Database $Database -ConnectionInfo $ConnectionInfo
}
