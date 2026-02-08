function Get-SubsetTableXml
{
    [cmdletbinding()]
    param
    (
        [Parameter(Mandatory = $true)]
        [string]$Database,

        [Parameter(Mandatory = $true)]
        [string]$SchemaName,

        [Parameter(Mandatory = $true)]
        [string]$TableName,

        [Parameter(Mandatory = $true)]
        [bool]$Secure,

        [Parameter(Mandatory = $true)]
        [DatabaseInfo]$DatabaseInfo,

        [Parameter(Mandatory = $true)]
        [SqlConnectionInfo]$ConnectionInfo
    )

    $prefix = "_$($SessionId).Export"
    if ($Secure -eq $true)
    {
        $prefix = "_$($SessionId).Secure"
    }

    foreach ($table in $DatabaseInfo.Tables)
    {
        if (($table.SchemaName -eq $SchemaName) -and ($table.TableName -eq $TableName))
        {
            $sql = "SELECT * FROM SqlSizer$($prefix)_$($SchemaName)_$($TableName) FOR JSON PATH, INCLUDE_NULL_VALUES"
            $rows = Invoke-SqlcmdEx -Sql $sql -Database $Database -ConnectionInfo $ConnectionInfo
            $obj = ($rows | Select-Object ItemArray -ExpandProperty ItemArray) -join "" | ConvertFrom-Json
            $xml = $obj | ConvertTo-Xml -NoTypeInformation

            return $xml
        }
    }

    return $null
}
