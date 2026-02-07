function Import-SubsetFromAzStorageContainer
{
    [cmdletbinding()]
    param
    (
        [Parameter(Mandatory = $true)]
        [string]$StorageAccountName,

        [Parameter(Mandatory = $true)]
        [string]$ContainerName,

        [Parameter(Mandatory = $true)]
        [string]$MasterPassword,

        [Parameter(Mandatory = $true)]
        [Object]$StorageContext,

        [Parameter(Mandatory = $true)]
        [string]$Database,

        [Parameter(Mandatory = $true)]
        [string]$OriginalDatabase,

        [Parameter(Mandatory = $true)]
        [DatabaseInfo]$DatabaseInfo,

        [Parameter(Mandatory = $true)]
        [SqlConnectionInfo]$ConnectionInfo
    )

    $token = New-AzStorageAccountSASToken -Service Blob -ResourceType Container, Object -Permission "racwdlup" -Context $StorageContext
    $token = $token.Substring(1)

    $sql = "CREATE MASTER KEY ENCRYPTION BY PASSWORD = '$MasterPassword'"
    $null = Invoke-SqlcmdEx -Sql $sql -Database $Database -ConnectionInfo $ConnectionInfo

    $sql = "CREATE DATABASE SCOPED CREDENTIAL $($ContainerName)_credential
            WITH IDENTITY = 'SHARED ACCESS SIGNATURE',
            SECRET = '$token'"
    $null = Invoke-SqlcmdEx -Sql $sql -Database $Database -ConnectionInfo $ConnectionInfo

    $sql = "CREATE EXTERNAL DATA SOURCE [SqlSizer] WITH
    (
        TYPE = BLOB_STORAGE,
        LOCATION = 'https://$StorageAccountName.blob.core.windows.net/$ContainerName',
        CREDENTIAL = $($ContainerName)_credential
    )"
    $null = Invoke-SqlcmdEx -Sql $sql -Database $Database -ConnectionInfo $ConnectionInfo
    $subsetTables = Get-SubsetTables -Database $OriginalDatabase -DatabaseInfo $DatabaseInfo -ConnectionInfo $ConnectionInfo

    foreach ($table in $subsetTables)
    {
        $tableInfo = $DatabaseInfo.Tables | Where-Object { ($_.SchemaName -eq $table.SchemaName) -and ($_.TableName -eq $table.TableName) }

        if ($tableInfo.IsIdentity)
        {
            $identity = ", KEEPIDENTITY"
        }
        else
        {
            $identity = ""
        }

        $sql = "BULK INSERT $($table.SchemaName).$($table.TableName)
        FROM '$($table.SchemaName).$($table.TableName).csv'
        WITH (DATA_SOURCE = 'SqlSizer', FORMAT = 'CSV', FIELDTERMINATOR = ';', FIELDQUOTE = '""' $identity)"

        $null = Invoke-SqlcmdEx -Sql $sql -Database $Database -ConnectionInfo $ConnectionInfo

        $sql = "SELECT COUNT(*) as Count FROM $($table.SchemaName).$($table.TableName)"
        $result = Invoke-SqlcmdEx -Sql $sql -Database $Database -ConnectionInfo $ConnectionInfo

        Write-Verbose "$($result.Count) added"
    }
}
