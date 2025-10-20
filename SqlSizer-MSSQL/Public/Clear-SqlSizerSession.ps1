function Clear-SqlSizerSession
{
    [cmdletbinding()]
    param
    (
        [Parameter(Mandatory = $true)]
        [string]$SessionId,

        [Parameter(Mandatory = $true)]
        [string]$Database,

        [Parameter(Mandatory = $true)]
        [DatabaseInfo]$DatabaseInfo,

        [Parameter(Mandatory = $true)]
        [SqlConnectionInfo]$ConnectionInfo
    )
    # remove session
    Write-Verbose "SqlSizer: Remove session: $SessionId"

    Update-DatabaseInfo -DatabaseInfo $DatabaseInfo -Database $Database -ConnectionInfo $ConnectionInfo
    Remove-Schema -Database $Database -SchemaName "SqlSizer_$SessionId" -ConnectionInfo $ConnectionInfo -DatabaseInfo $DatabaseInfo -DropFks $false
    
    $sql = "DELETE FROM SqlSizer.Sessions WHERE SessionId = '$SessionId'"
    $null = Invoke-SqlcmdEx -Sql $sql -Database $Database -ConnectionInfo $ConnectionInfo
}
