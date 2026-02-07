function Test-SchemaExists
{
    [cmdletbinding()]
    [outputtype([System.Boolean])]
    param
    (
        [Parameter(Mandatory = $true)]
        [string]$Database,

        [Parameter(Mandatory = $true)]
        [string]$SchemaName,

        [Parameter(Mandatory = $true)]
        [SqlConnectionInfo]$ConnectionInfo
    )

    $sql = "SELECT 1 as [Result] FROM sys.schemas WHERE name = '$SchemaName'"
    $results = Invoke-SqlcmdEx -Sql $sql -Database $Database -ConnectionInfo $ConnectionInfo

    if (($null -ne $results) -and ($results.Result -eq 1))
    {
        return $true
    }
    return $false
}
