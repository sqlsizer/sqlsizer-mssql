function Install-SqlSizerSecureViews
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
        [SqlConnectionInfo]$ConnectionInfo,

        [Parameter(Mandatory = $false)]
        [TableInfo2[]]$IgnoredTables
    )
    $schemaExists = Test-SchemaExists -SchemaName "SqlSizer_$SessionId" -Database $Database -ConnectionInfo $ConnectionInfo
    if ($schemaExists -eq $false)
    {
        $tmp = "CREATE SCHEMA SqlSizer_$SessionId"
        $null = Invoke-SqlcmdEx -Sql $tmp -Database $Database -ConnectionInfo $ConnectionInfo -Statistics $false
    }

    $structure = [Structure]::new($DatabaseInfo)

    $total = [System.Collections.Generic.List[string]]@()
    foreach ($table in $DatabaseInfo.Tables)
    {
        if ($table.SchemaName.StartsWith('SqlSizer'))
        {
            continue
        }


        $tableSelect = Get-TableSelect -TableInfo $table -Conversion $true -IgnoredTables $IgnoredTables -Prefix "t." -AddAs $true -SkipGenerated $false -MaxLength $null
        $hashSelect = Get-TableSelect -TableInfo $table -Conversion $true -IgnoredTables $IgnoredTables -Prefix "t." -AddAs $false -Array $true -SkipGenerated $false -MaxLength $null
        $join = GetSecureViewsTableJoin -TableInfo $table -Structure $structure

        if ($null -eq $join)
        {
            continue
        }

        $hashInput = GetHashInput -hashSelect $hashSelect

        # create a view
        $sql = "CREATE VIEW SqlSizer_$($SessionId).Secure_$($table.SchemaName)_$($table.TableName) AS SELECT ROW_NUMBER() OVER(ORDER BY (SELECT NULL)) AS SqlSizer_RowSequence, $tableSelect, HASHBYTES('SHA2_512', $hashInput) as row_sha2_512 FROM $($table.SchemaName).$($table.TableName) t INNER JOIN $join"
        $null = Invoke-SqlcmdEx -Sql $sql -Database $Database -ConnectionInfo $ConnectionInfo -Statistics $false
        $null = $total.Add("SELECT '$($table.SchemaName)' as [Schema], '$($table.TableName)' as [Table],  CONVERT(VARCHAR(max), HASHBYTES('SHA1', STRING_AGG(CONVERT(VARCHAR(max), row_sha2_512, 2), '|')), 2) as [TableHash_SHA_1], CONVERT(VARCHAR(max), HASHBYTES('SHA2_256', STRING_AGG(CONVERT(VARCHAR(max), row_sha2_512, 2), '|')), 2) as [TableHash_SHA_256],  CONVERT(VARCHAR(max), HASHBYTES('SHA2_512', STRING_AGG(CONVERT(VARCHAR(max), row_sha2_512, 2), '|')), 2) as [TableHash_SHA_512] FROM SqlSizer_$($SessionId).Secure_$($table.SchemaName)_$($table.TableName)")
    }

    if ($total.Count -ne 0)
    {
        $sql = "CREATE VIEW SqlSizer_$($SessionId).Secure_Summary AS $([string]::Join(' UNION ALL ', $total))"
        $null = Invoke-SqlcmdEx -Sql $sql -Database $Database -ConnectionInfo $ConnectionInfo -Statistics $false
    }
}

function GetHashInput
{
    param (
        [string[]]$hashSelect
    )

    # prepare $hashInput
    $hashGroups = [System.Collections.ArrayList]@()
    $hashGroupSize = 50

    for ($i = 0; $i -lt ($hashSelect.Length / $hashGroupSize); $i += 1)
    {
        $group = $hashSelect | Select-Object -First $hashGroupSize -Skip ($hashGroupSize * $i)
        $item = @()
        $item += $group

        $null = $hashGroups.Add($item)
    }

    $hashInputs = @()
    foreach ($hashGroup in $hashGroups)
    {
        if ($hashGroup.Length -gt 1)
        {
            $hashInputs += "CONCAT($([string]::Join(', ''|'', ', $hashGroup)))"
        }
        else
        {
            $hashInputs += "CONCAT($($hashGroup[0]), '|')"
        }
    }

    if ($hashInputs.Length -gt 1)
    {
        $hashInput = "CONCAT($([string]::Join(', ''|'', ', $hashInputs)))"
    }
    else
    {
        $hashInput = $hashInputs[0]
    }

    return $hashInput
}

function GetSecureViewsTableJoin
{
    param (
        [TableInfo]$TableInfo,
        [Structure]$Structure
    )

    $primaryKey = $TableInfo.PrimaryKey
    $signature = $Structure.Tables[$TableInfo]

    if (($null -eq $signature) -or ($signature -eq ""))
    {
        return $null
    }

    $processing = $Structure.GetProcessingName($signature, $SessionId)

    $select = @()
    $join = @()

    $i = 0
    foreach ($column in $primaryKey)
    {
        $select += "p.Key$i"
        $join += "t.$column = rr.Key$i"
        $i = $i + 1
    }

    $sql = " (SELECT DISTINCT $([string]::Join(',', $select))
            FROM $($processing) p) rr ON $([string]::Join(' and ', $join))"

    return $sql
}
