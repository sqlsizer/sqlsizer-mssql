function `Copy-Database
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

    # Convert '.' to 'localhost' for dbatools compatibility
    $serverName = if ($ConnectionInfo.Server -eq '.') { 'localhost' } else { $ConnectionInfo.Server }

    # Configure dbatools to trust server certificate if encryption is disabled
    if (-not $ConnectionInfo.EncryptConnection) {
        Set-DbatoolsConfig -FullName sql.connection.trustcert -Value $true -PassThru | Register-DbatoolsConfig
        Set-DbatoolsConfig -FullName sql.connection.encrypt -Value $false -PassThru | Register-DbatoolsConfig
    }

    Write-Progress -Activity "Copy database" -PercentComplete 0
    $sharedPath = (Get-DbaDefaultPath -SqlCredential $ConnectionInfo.Credential -SqlInstance $serverName).Backup
    $null = Copy-DbaDatabase -Database $Database -SourceSqlCredential $ConnectionInfo.Credential -DestinationSqlCredential $ConnectionInfo.Credential `
        -Source $serverName -Destination $serverName -NewName $NewDatabase -BackupRestore -SharedPath $sharedPath

    Write-Progress -Activity "Copy database" -Completed
}
