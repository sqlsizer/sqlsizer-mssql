function Start-SqlSizerSession
{
    [outputtype([System.String])]
    [cmdletbinding()]
    param
    (
        [Parameter(Mandatory = $true)]
        [string]$Database,

        [Parameter(Mandatory = $true)]
        [DatabaseInfo]$DatabaseInfo,

        [Parameter(Mandatory = $false)]
        [bool]$ForceInstallation = $false,

        [Parameter(Mandatory = $false)]
        [bool]$Installation = $true,

        [Parameter(Mandatory = $false)]
        [bool]$SecureViews = $true,

        [Parameter(Mandatory = $false)]
        [bool]$ExportViews = $true,

        [Parameter(Mandatory = $false)]
        [bool]$Removal = $false,

        [Parameter(Mandatory = $true)]
        [SqlConnectionInfo]$ConnectionInfo
    )
    $sessionId = (New-Guid).ToString().Replace("-", "_")

    Write-Verbose "SqlSizer: Starting new session: $sessionId"

    if ($Installation)
    {
        Write-Verbose "SqlSizer: Installation verification"

        Install-SqlSizer -Database $Database -ConnectionInfo $ConnectionInfo -DatabaseInfo $DatabaseInfo -Force $ForceInstallation
    }

    # save session id
    $sql = "INSERT INTO SqlSizer.Sessions(SessionId) VALUES('$SessionId')"
    $null = Invoke-SqlcmdEx -Sql $sql -Database $Database -ConnectionInfo $ConnectionInfo

    Write-Verbose "SqlSizer: Installation of session views and tables"
    # install session structures
    Install-SqlSizerSessionTables -SessionId $sessionId -Database $Database -DatabaseInfo $DatabaseInfo -ConnectionInfo $ConnectionInfo -Removal $Removal
    Install-SqlSizerResultViews -SessionId $sessionId -Database $Database -DatabaseInfo $DatabaseInfo -ConnectionInfo $ConnectionInfo

    if ($ExportViews)
    {
        Install-SqlSizerExportViews -SessionId $sessionId -Database $Database -DatabaseInfo $DatabaseInfo -ConnectionInfo $ConnectionInfo
    }

    if ($SecureViews)
    {
        Install-SqlSizerSecureViews -SessionId $sessionId -Database $Database -DatabaseInfo $DatabaseInfo -ConnectionInfo $ConnectionInfo
    }

    return $sessionId
}
