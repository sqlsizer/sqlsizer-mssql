function New-SqlConnectionInfo
{
    [cmdletbinding()]
    param
    (
        [Parameter(Mandatory = $true)]
        [string]$Server,
        [string]$Username,
        [SecureString]$Password,
        [string]$AccessToken,
        [bool]$EncryptConnection = $false
    )

    $connection = New-Object -TypeName SqlConnectionInfo
    $connection.Server = $Server
    $connection.EncryptConnection = $EncryptConnection
    $connection.Statistics = New-Object -Type SqlConnectionStatistics

    if (($Username -ne $null) -and ($Password -ne $null))
    {
        $connection.Credential = New-Object -TypeName System.Management.Automation.PSCredential -ArgumentList $Username, $Password
    }

    if (($AccessToken -ne "") -and ($AccessToken -ne $null))
    {
        $connection.AccessToken = $AccessToken
    }
    else
    {
        $connection.AccessToken = $null
    }

    return $connection
}

