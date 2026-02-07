function Restore-View
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
        [DatabaseInfo]$DatabaseInfo,

        [Parameter(Mandatory = $true)]
        [SqlConnectionInfo]$ConnectionInfo
    )

    $schemaExists = Test-SchemaExists -SchemaName $SchemaName -Database $Database -ConnectionInfo $ConnectionInfo
    if ($schemaExists -eq $false)
    {
        Write-Host "Schema $SchemaName doesn't exist"
        return $false
    }

    $view = $DatabaseInfo.Views | Where-Object { ($_.ViewName -eq $ViewName) -and ($_.SchemaName -eq $SchemaName)}

    $sql = "$($view.Definition)"
    $null = Invoke-SqlcmdEx -Sql $sql -Database $Database -ConnectionInfo $ConnectionInfo

    return $true
}
