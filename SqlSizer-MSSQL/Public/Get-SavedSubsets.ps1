function Get-SavedSubsets
{
    [cmdletbinding()]
    param
    (
        [Parameter(Mandatory = $true)]
        [string]$Database,

        [Parameter(Mandatory = $true)]
        [SqlConnectionInfo]$ConnectionInfo
    )

    $sql = "SELECT [Guid],[Name],[Created] FROM [SqlSizerHistory].[Subset]"
    $rows = Invoke-SqlcmdEx -Sql $sql -Database $Database -ConnectionInfo $ConnectionInfo

    $result = @()
    foreach ($row in $rows)
    {
        $result += [pscustomobject]@{
            Guid    = $row.Guid
            Name    = $row.Name
            Created = $row.Created
        }
    }

    return $result
}
