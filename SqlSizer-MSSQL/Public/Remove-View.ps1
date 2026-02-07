function Remove-View
{
    [outputtype([System.Boolean])]
    [cmdletbinding()]
    param
    (
        [Parameter(Mandatory = $true)]
        [string]$Database,

        [Parameter(Mandatory = $true)]
        [string]$SchemaName,

        [Parameter(Mandatory = $true)]
        [string]$ViewName,

        [Parameter(Mandatory = $true)]
        [SqlConnectionInfo]$ConnectionInfo
    )

    $schemaExists = Test-SchemaExists -SchemaName $SchemaName -Database $Database -ConnectionInfo $ConnectionInfo
    if ($schemaExists -eq $false)
    {
        Write-Verbose "Schema $SchemaName doesn't exist"
        return $false
    }

    if ($ConnectionInfo.IsSynapse -eq $true)
    {
        $sql = "DROP VIEW [$($SchemaName)].[$($ViewName)]"
    }
    else
    {
        $sql = "DROP VIEW IF EXISTS [$($SchemaName)].[$($ViewName)]"
    }
    $null = Invoke-SqlcmdEx -Sql $sql -Database $Database -ConnectionInfo $ConnectionInfo

    return $true
}
