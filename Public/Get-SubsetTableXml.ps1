function Get-SubsetTableXml
{
    [cmdletbinding()]
    param
    (
        [Parameter(Mandatory=$true)]
        [string]$Database,

        [Parameter(Mandatory=$true)]
        [string]$SchemaName,

        [Parameter(Mandatory=$true)]
        [string]$TableName,

        [Parameter(Mandatory=$true)]
        [bool]$Secure,

        [Parameter(Mandatory=$false)]
        [DatabaseInfo]$DatabaseInfo = $null,

        [Parameter(Mandatory=$true)]
        [SqlConnectionInfo]$ConnectionInfo
    )

    $schema = "SqlSizerExport"
    if ($Secure -eq $true)
    {
        $schema = 'SqlSizerSecure'
    }

    $info = Get-DatabaseInfoIfNull -Database $Database -Connection $ConnectionInfo -DatabaseInfo $DatabaseInfo
    foreach ($table in $info.Tables)
    {
        if (($table.SchemaName -eq $SchemaName) -and ($table.TableName -eq $TableName))
        {
            $sql = "SELECT * FROM $schema.$($SchemaName)_$($TableName) FOR JSON PATH, INCLUDE_NULL_VALUES"
            $rows = Invoke-SqlcmdEx -Sql $sql -Database $Database -ConnectionInfo $ConnectionInfo
            $obj = ($rows | Select-Object ItemArray -ExpandProperty ItemArray) -join "" | ConvertFrom-Json
            $xml = $obj | ConvertTo-Xml -NoTypeInformation

            return $xml
        }
    }

    return $null
}