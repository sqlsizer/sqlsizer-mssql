function Copy-SubsetToDatabaseFileSet
{
    [cmdletbinding()]
    param
    (
        [Parameter(Mandatory = $true)]
        [string]$SessionId,

        [Parameter(Mandatory = $true)]
        [string]$SourceDatabase,

        [Parameter(Mandatory = $true)]
        [string]$TargetDatabase,

        [Parameter(Mandatory = $true)]
        [bool]$Secure,

        [Parameter(Mandatory = $true)]
        [DatabaseInfo]$DatabaseInfo,

        [Parameter(Mandatory = $true)]
        [SqlConnectionInfo]$ConnectionInfo
    )

    $subsetTables = Get-SubsetTables -SessionId $SessionId -Database $SourceDatabase -DatabaseInfo $DatabaseInfo -ConnectionInfo $ConnectionInfo

    $result = @()
    foreach ($table in $subsetTables)
    {
        $tmpFile = New-TemporaryFile
        $csv = Get-SubsetTableJson -SessionId $SessionId -Database $SourceDatabase -SchemaName $table.SchemaName -TableName $table.TableName -ConnectionInfo $ConnectionInfo `
                                    -Secure $Secure -DatabaseInfo $DatabaseInfo

        [System.IO.File]::WriteAllText($tmpFile.FullName, $csv, [Text.Encoding]::GetEncoding("utf-8"))
        $fileId = Copy-FileToDatabase -FilePath $tmpFile.FullName -Database $TargetDatabase -ConnectionInfo $ConnectionInfo

        $result += New-Object TableFile -Property @{ FileId = $fileId; TableContent = $table }

        Remove-Item $tmpFile.FullName -Force
    }

    return $result
}
