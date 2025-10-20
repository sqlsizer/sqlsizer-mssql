function Get-SubsetTableCsv
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

        [Parameter(Mandatory = $false)]
        [bool]$SkipHeader = $true,

        [Parameter(Mandatory = $true)]
        [SqlConnectionInfo]$ConnectionInfo
    )

    $json = Get-SubsetTableJson -SessionId $SessionId -Database $database -ConnectionInfo $ConnectionInfo -SchemaName $SchemaName -TableName $TableName -DatabaseInfo $DatabaseInfo -Secure $Secure
    $obj = $json | ConvertFrom-Json
    $csv = $obj | ConvertTo-Csv  -Delimiter ';' -NoTypeInformation
    if ($SkipHeader)
    {
        $csv = $csv | select-object -skip 1
    }
    return [string]::Join("`r`n", $csv)
}

