function Get-SavedSubsetTables
{
    [cmdletbinding()]
    param
    (
        [Parameter(Mandatory = $true)]
        [string]$SubsetGuid,

        [Parameter(Mandatory = $true)]
        [string]$Database,

        [Parameter(Mandatory = $true)]
        [SqlConnectionInfo]$ConnectionInfo
    )

    $sql = "SELECT st.Id as [TableId], st.PrimaryKeySize as [PrimaryKeySize], st.SchemaName as [SchemaName], st.TableName as [TableName], st.[RowCount] as [RowCount]
        FROM [SqlSizerHistory].[Subset] s
        INNER JOIN [SqlSizerHistory].[SubsetTable] st ON s.Id = st.SubsetId
        WHERE s.[Guid] = '{0}'"

    $rows = Invoke-SqlcmdEx -Sql $([String]::Format($sql, $SubsetGuid)) -Database $Database -ConnectionInfo $ConnectionInfo
    $tables = @()

    foreach ($row in $rows)
    {
        $tables += [pscustomobject] @{
            TableID        = $row.TableId
            PrimaryKeySize = $row.PrimaryKeySize
            SchemaName     = $row.SchemaName
            TableName      = $row.TableName
            RowCount       = $row.RowCount
        }
    }
    return $tables
}
