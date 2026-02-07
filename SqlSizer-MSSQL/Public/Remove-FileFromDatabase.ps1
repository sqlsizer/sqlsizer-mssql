function Remove-FileFromDatabase
{
    [cmdletbinding()]
    [outputtype([System.Boolean])]
    param
    (
        [Parameter(Mandatory = $true)]
        [string]$Database,

        [Parameter(Mandatory = $true)]
        [string]$FileId,

        [Parameter(Mandatory = $true)]
        [SqlConnectionInfo]$ConnectionInfo
    )

    $sql = "DELETE FROM SqlSizer.Files WHERE [FileId] = '$FileId'"
    $null = Invoke-SqlcmdEx -Sql $sql -Database $Database -ConnectionInfo $ConnectionInfo
}
