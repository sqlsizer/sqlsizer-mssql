function Invoke-SqlcmdEx
{
    [cmdletbinding()]
    [outputtype([System.Boolean])]
    [outputtype([System.Object])]
    param
    (
        [Parameter(Mandatory = $true)]
        [string]$Sql,

        [Parameter(Mandatory = $true)]
        [string]$Database,

        [Parameter(Mandatory = $false)]
        [bool]$Silent = $false,

        [Parameter(Mandatory = $true)]
        [SqlConnectionInfo]$ConnectionInfo,

        [Parameter(Mandatory = $false)]
        [bool]$Statistics = $true
    )

    try
    {
        Write-Verbose "Invoke SQL [$(Get-Date)] => $($Sql.Substring(0, [Math]::Min(80, $Sql.Length))) ..."
        
        # Determine encryption setting for SQLServer module v22+
        $encryptValue = if ($ConnectionInfo.EncryptConnection) { 'Mandatory' } else { 'Optional' }
        
        $params = @{
            Query             = $Sql
            ServerInstance    = $ConnectionInfo.Server
            Database          = $Database
            QueryTimeout      = 65535
            Verbose           = $true
            Encrypt           = $encryptValue
            TrustServerCertificate = (-not $ConnectionInfo.EncryptConnection)
        }

        if (($null -ne $ConnectionInfo.AccessToken) -and ($ConnectionInfo.AccessToken -ne ""))
        {
            $params.AccessToken = $ConnectionInfo.AccessToken
        }

        if ($null -ne $ConnectionInfo.Credential)
        {
            $params.Credential = $ConnectionInfo.Credential
        }

        if (($true -eq $Statistics) -and ($ConnectionInfo.IsSynapse -eq $false))
        {
            $params.Query = 'SET STATISTICS IO ON
            ' + $Sql + '
            SET STATISTICS IO OFF'

            $verbose = ForEach-Object { $result = Invoke-Sqlcmd @params -ErrorAction Stop } 4>&1
            $message = $verbose.Message
            $logicalReads = Get-LogicalReadsValue -Message $message
            $ConnectionInfo.Statistics.LogicalReads += $logicalReads
            return $result
        }
        else
        {
            $result = Invoke-Sqlcmd @params -ErrorAction Stop
            return $result
        }
    }
    catch
    {
        if ($Silent -eq $false)
        {
            throw [System.Exception]::new("Error '$($_.Exception.Message)' occured when invoking $Sql",  $_.Exception)
        }
        return $false
    }
}

