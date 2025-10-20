function Get-SubsetHashSummary
{
    [cmdletbinding()]
    param
    (
        [Parameter(Mandatory = $true)]
        [string]$SessionId,

        [Parameter(Mandatory = $true)]
        [string]$Database,

        [Parameter(Mandatory = $true)]
        [SqlConnectionInfo]$ConnectionInfo
    )

    $sql = "SELECT [Schema]
                ,[Table]
                ,[TableHash_SHA_1]
                ,[TableHash_SHA_256]
                ,[TableHash_SHA_512]
        FROM [SqlSizer_$SessionId].[Secure_Summary]
        WHERE TableHash_SHA_1 IS NOT NULL
        ORDER BY [Schema], [Table]"

    $rows = Invoke-SqlcmdEx -Sql $sql -Database $Database -ConnectionInfo $ConnectionInfo

    $hashes = @()
    foreach ($row in $rows)
    {
        $hashes += [pscustomobject] @{
            SchemaName = $row.Schema
            TableName  = $row.Table
            Hash_SHA512 = $row.TableHash_SHA_512
            Hash_SHA256 = $row.TableHash_SHA_256
            Hash_SHA1 = $row.TableHash_SHA_1
        }
    }
    return $hashes

}
