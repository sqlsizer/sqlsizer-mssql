function Initialize-StartSet
{
    [cmdletbinding()]
    param
    (
        [Parameter(Mandatory = $true)]
        [Query[]]$Queries,

        [Parameter(Mandatory = $true)]
        [string]$Database,

        [Parameter(Mandatory = $false)]
        [int]$StartIteration = 0,

        [Parameter(Mandatory = $true)]
        [DatabaseInfo]$DatabaseInfo,

        [Parameter(Mandatory = $true)]
        [SqlConnectionInfo]$ConnectionInfo,

        [Parameter(Mandatory = $true)]
        [string]$SessionId
    )

    # get metadata
    $structure = [Structure]::new($DatabaseInfo)
    foreach ($query in $Queries)
    {
        $table = $DatabaseInfo.Tables | Where-Object { ($_.SchemaName -eq $query.Schema) -and ($_.TableName -eq $query.Table) }

        if ($null -eq $table)
        {
            throw "Could not found $($query.Schema).$($query.Table) table to init the start set."
        }

        $signature = $structure.Tables[$table]

        if ($null -eq $signature)
        {
            throw "Table $($query.Schema).$($query.Table) doesn't have the primary key"
        }
        $top = "";
        if ($query.Top -ne 0)
        {
            $top = " TOP " + $query.Top + " "
        }
        $procesing = $Structure.GetProcessingName($signature, $SessionId)
        $tmp = "INSERT INTO $($procesing) SELECT " + $top

        $i = 0
        foreach ($column in $query.KeyColumns)
        {
            $tmp += $column + ","
            $i += 1
        }

        $order = "";
        if ($null -ne $query.OrderBy)
        {
            $order = " ORDER BY " + $query.OrderBy
        }
        $tmp = $tmp + [int]$query.Color + " as Color, NULL, 0, NULL, $StartIteration FROM " + $query.Schema + "." + $query.Table + " as [`$table] "

        if ($null -ne $query.Where)
        {
            $tmp += " WHERE " + $query.Where
        }

        $tmp += " " + $order

        $null = Invoke-SqlcmdEx -Sql $tmp -Database $Database -ConnectionInfo $ConnectionInfo
    }
}
