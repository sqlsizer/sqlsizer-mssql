function Uninstall-SqlSizer
{
    [cmdletbinding()]
    param
    (
        [Parameter(Mandatory = $true)]
        [string]$Database,

        [Parameter(Mandatory = $false)]
        [string]$RemoveHistory = $false,

        [Parameter(Mandatory = $false)]
        [string]$RemoveSettings = $true,

        [Parameter(Mandatory = $true)]
        [DatabaseInfo]$DatabaseInfo,

        [Parameter(Mandatory = $true)]
        [SqlConnectionInfo]$ConnectionInfo
    )

    if ($RemoveHistory -eq $true)
    {
        Remove-Schema -Database $Database -SchemaName "SqlSizerHistory" -ConnectionInfo $ConnectionInfo -DatabaseInfo $DatabaseInfo
    }

    $tablesToKeep = @()

    if ($RemoveSettings -eq $false)
    {
        $tablesToKeep += "Settings"
    }

    Remove-Schema -Database $Database -SchemaName "SqlSizer" -ConnectionInfo $ConnectionInfo -DatabaseInfo $DatabaseInfo -KeepTables $tablesToKeep
}
