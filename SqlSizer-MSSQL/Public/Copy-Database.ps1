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

    Write-Progress -Activity "Copy database" -PercentComplete 0

    # Get default backup path from SQL Server
    $backupPathResult = Invoke-SqlcmdEx -Sql "SELECT SERVERPROPERTY('InstanceDefaultBackupPath') AS BackupPath" `
        -Database 'master' -ConnectionInfo $ConnectionInfo -Statistics $false
    $backupPath = $backupPathResult.BackupPath

    $backupFile = Join-Path $backupPath "$($Database)_copy_$(Get-Date -Format 'yyyyMMddHHmmss').bak"

    # Backup source database
    Write-Progress -Activity "Copy database" -Status "Backing up $Database..." -PercentComplete 25
    $backupSql = "BACKUP DATABASE [$Database] TO DISK = N'$backupFile' WITH FORMAT, INIT, SKIP, NOREWIND, NOUNLOAD, COMPRESSION"
    Invoke-SqlcmdEx -Sql $backupSql -Database 'master' -ConnectionInfo $ConnectionInfo -Statistics $false

    try {
        # Get logical file names from backup
        Write-Progress -Activity "Copy database" -Status "Restoring as $NewDatabase..." -PercentComplete 50
        $fileList = Invoke-SqlcmdEx -Sql "RESTORE FILELISTONLY FROM DISK = N'$backupFile'" `
            -Database 'master' -ConnectionInfo $ConnectionInfo -Statistics $false

        # Get default data and log paths
        $defaultPaths = Invoke-SqlcmdEx -Sql "SELECT SERVERPROPERTY('InstanceDefaultDataPath') AS DataPath, SERVERPROPERTY('InstanceDefaultLogPath') AS LogPath" `
            -Database 'master' -ConnectionInfo $ConnectionInfo -Statistics $false

        # Build MOVE clauses for each file
        $moveClauses = @()
        foreach ($file in $fileList) {
            $logicalName = $file.LogicalName
            $extension = if ($file.Type -eq 'L') { '.ldf' } else { '.mdf' }
            $targetPath = if ($file.Type -eq 'L') { $defaultPaths.LogPath } else { $defaultPaths.DataPath }
            $newFilePath = Join-Path $targetPath "$($NewDatabase)$extension"
            $moveClauses += "MOVE N'$logicalName' TO N'$newFilePath'"
        }

        $moveClause = $moveClauses -join ", "
        $restoreSql = "RESTORE DATABASE [$NewDatabase] FROM DISK = N'$backupFile' WITH $moveClause, REPLACE, RECOVERY"
        Invoke-SqlcmdEx -Sql $restoreSql -Database 'master' -ConnectionInfo $ConnectionInfo -Statistics $false
    }
    finally {
        # Clean up backup file
        Write-Progress -Activity "Copy database" -Status "Cleaning up..." -PercentComplete 90
        $cleanupSql = "EXEC master.dbo.xp_delete_files N'$backupFile'"
        Invoke-SqlcmdEx -Sql $cleanupSql -Database 'master' -ConnectionInfo $ConnectionInfo -Statistics $false -Silent $true
    }

    Write-Progress -Activity "Copy database" -Completed
}
