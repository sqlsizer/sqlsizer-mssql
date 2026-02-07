function Enable-DatabaseTriggers
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

    Write-Progress -Activity "Enabling all triggers on database $Database" -PercentComplete 0

    $sql = "ENABLE TRIGGER ALL ON DATABASE"

    $null = Invoke-SqlcmdEx -Sql $sql -Database $Database -ConnectionInfo $ConnectionInfo -Statistics $false

    Write-Progress -Activity "Enabling all triggers on database $Database" -Completed
}
