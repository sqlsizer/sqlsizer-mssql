function Compress-Database
{
    [cmdletbinding()]
    param
    (
        [Parameter(Mandatory = $true)]
        [string]$Database,

        [Parameter(Mandatory = $true)]
        [SqlConnectionInfo]$ConnectionInfo
    )

    if ($ConnectionInfo.IsSynapse -eq $true)
    {
        throw "Feature not supported in Synapse"
    }

    Write-Progress -Activity "Shrinking database" -PercentComplete 0

    $sql = "DBCC SHRINKDATABASE ([" + ($Database) + "])"
    $null = Invoke-SqlcmdEx -Sql $sql -Database $Database -ConnectionInfo $ConnectionInfo -Statistics $false

    Write-Progress -Activity "Shrinking database" -Completed
}
