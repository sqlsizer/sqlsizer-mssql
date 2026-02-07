function Get-DatabaseSchemaJson
{
    [cmdletbinding()]
    param
    (
        [Parameter(Mandatory = $true)]
        [string]$Database,

        [Parameter(Mandatory = $true)]
        [DatabaseInfo]$DatabaseInfo,

        [Parameter(Mandatory = $true)]
        [SqlConnectionInfo]$ConnectionInfo
    )

    $nodes = @()
    $edges = @()
    $colors = New-Object "System.Collections.Generic.Dictionary[[string], [string]]"
    $random = New-Object "System.Random"
    $allColors = @()

    for ($i = 0; $i -lt $DatabaseInfo.Schemas.Count; $i += 1)
    {
        $allColors += """rgb($($random.Next(255)),$($random.Next(255)),$($random.Next(255)))"""
    }

    
    $i = 0
    $tableSize = @()
    foreach ($table in $DatabaseInfo.Tables)
    {    
        $i += 1
        $tableSize += @{Table = $table; Size = $table.Statistics.Rows }
    }

    $sorted = $tableSize | Sort-Object -Property Size
    $sizes = New-Object "System.Collections.Generic.Dictionary[[string], [int]]"
    foreach ($table in $DatabaseInfo.Tables)
    {    
        $t = $sorted | Where-Object { $_.Table -eq $table }
        $index = $sorted.IndexOf($t)
        $sizes[$table.SchemaName + $table.TableName] = $index
    }

    $i = 0
    $j = 0
    foreach ($table in $DatabaseInfo.Tables)
    {
        if ($table.SchemaName.StartsWith("SqlSizer"))
        {
            continue
        }

        $colorForSchema = $null
        if ($colors.ContainsKey($table.SchemaName))
        {
            $colorForSchema = $colors[$table.SchemaName]
        }
        else
        {
            $colorForSchema = $allColors[$random.Next($allColors.Length)]
            $colors[$table.SchemaName] = $colorForSchema
        }

        $nodes += "{ ""data"": { ""id"": $i, ""order"": $($sizes[$table.SchemaName + $table.TableName]), ""color"": $colorForSchema, ""label"": ""$($table.SchemaName).$($table.TableName)""}}"

        foreach ($fk in $table.ForeignKeys)
        {
            $j += 1
            $tableBase = $DatabaseInfo.Tables | Where-Object { ($_.SchemaName -eq $fk.Schema) -and ($_.TableName -eq $fk.Table) }
            $tableIndex = $DatabaseInfo.Tables.IndexOf($tableBase)

            $within = "false"

            if (($fk.Schema -eq $table.SchemaName))
            {
                $within = "true"
            }

            $prefix = Get-Prefix -Value $table.TableName
            $prefix2 = Get-Prefix -Value $tableBase.TableName

            $same_prefix = "false"
            if (($prefix -eq $prefix2) -and ($prefix -ne ""))
            {
                $same_prefix = "true"
            }

            $edges += "{ ""data"": { ""id"": ""e$j"", ""source"": $i, ""target"": $tableIndex, ""same_prefix"": $same_prefix, ""within_schema"": $within}}"
        }
        $i += 1
    }


    $nodesArray = "[$([string]::Join(",", $nodes))]"
    $edgesArray = "[$([string]::Join(",", $edges))]"

    $json = "{""nodes"": $nodesArray, ""edges"": $edgesArray}"

    return $json
}
