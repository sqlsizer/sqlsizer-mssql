function Copy-Database
{
    [cmdletbinding()]
    param
    (
        [Parameter(Mandatory = $true)]
        [string]$Database,

        [Parameter(Mandatory = $true)]
        [string]$NewDatabase,

        [Parameter(Mandatory = $true)]
        [SqlConnectionInfo]$ConnectionInfo
    )

    if ($ConnectionInfo.IsSynapse -eq $true)
    {
        throw "Feature not supported in Synapse"
    }

    Write-Progress -Activity "Copy database" -PercentComplete 0
    $null = Copy-DbaDatabase -Database $Database -SourceSqlCredential $ConnectionInfo.Credential -DestinationSqlCredential $ConnectionInfo.Credential `
        -Source $ConnectionInfo.Server -Destination $ConnectionInfo.Server -NewName $NewDatabase -BackupRestore -SharedPath (Get-DbaDefaultPath -SqlCredential $ConnectionInfo.Credential -SqlInstance $ConnectionInfo.Server).Backup

    Write-Progress -Activity "Copy database" -Completed
}
