function Get-SubsetTableJson
{
    [cmdletbinding()]
    param
    (
        [Parameter(Mandatory = $true)]
        [string]$SessionId,

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

    $type = "Export"
    if ($Secure -eq $true)
    {
        $type = "Secure"
    }

    foreach ($table in $DatabaseInfo.Tables)
    {
        if (($table.SchemaName -eq $SchemaName) -and ($table.TableName -eq $TableName))
        {
            $sql = "SELECT * FROM SqlSizer_$($SessionId).$($type)_$($SchemaName)_$($TableName) FOR JSON PATH, INCLUDE_NULL_VALUES"

            $rows = Invoke-SqlcmdEx -Sql $sql -Database $Database -ConnectionInfo $ConnectionInfo
            $json = ($rows | Select-Object ItemArray -ExpandProperty ItemArray) -join ""
            return $json
        }
    }

    return $null
}
