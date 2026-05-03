function Install-SqlSizerSessionTables
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
        [bool]$Removal = $false
    )

    $schemaExists = Test-SchemaExists -SchemaName "SqlSizer_$SessionId" -Database $Database -ConnectionInfo $ConnectionInfo
    if ($schemaExists -eq $false)
    {
        $tmp = "CREATE SCHEMA SqlSizer_$SessionId"
        $null = Invoke-SqlcmdEx -Sql $tmp -Database $Database -ConnectionInfo $ConnectionInfo -Statistics $false
    }
    $pk = "PRIMARY KEY"
    $structure = [Structure]::new($DatabaseInfo)

    foreach ($signature in $structure.Signatures.Keys)
    {
        $processing = $structure.GetProcessingName($signature, $SessionId)
        $keys = ""
        $columns = ""
        $keysIndex = ""
        $keysInclude = ""
        $i = 0
        $len = $structure.Signatures[$signature].Count

        foreach ($column in $structure.Signatures[$signature])
        {
            $keys += " Key$($i) "
            $columns += " Key$($i) "
            $keysIndex += " Key$($i) ASC "
            $keysInclude += " Key$($i) "

            if ($column.DataType -in @('varchar', 'nvarchar', 'char', 'nchar'))
            {
                $columns += $column.DataType + "(" + $column.Length + ") NOT NULL "
            }
            else
            {
                $columns += $column.DataType + " NOT NULL "
            }

            if ($i -lt ($len - 1))
            {
                $keysIndex += ", "
                $keys += ", "
                $columns += ", "
                $keysInclude += ", "
            }

            $i += 1
        }

        if ($len -gt 0)
        {
            if ($Removal)
            {
                $sql = "CREATE TABLE $($processing) (Id bigint identity(1,1) $pk, $($columns), [State] tinyint NOT NULL, [Source] bigint NULL, [Depth] int NOT NULL, [Fk] bigint, [Iteration] int NOT NULL)"
                $null = Invoke-SqlcmdEx -Sql $sql -Database $Database -ConnectionInfo $ConnectionInfo -Statistics $false

                
                $sql = "CREATE NONCLUSTERED INDEX [Index] ON $($processing) ($($keysIndex), [Depth] ASC)"
                $null = Invoke-SqlcmdEx -Sql $sql -Database $Database -ConnectionInfo $ConnectionInfo -Statistics $false
            }
            else
            {
                $sql = "CREATE TABLE $($processing) (Id bigint identity(1,1) $pk, $($columns), [State] tinyint NOT NULL, [Source] bigint NULL, [Depth] int NOT NULL, [Fk] bigint, [Iteration] int NOT NULL)"
                $null = Invoke-SqlcmdEx -Sql $sql -Database $Database -ConnectionInfo $ConnectionInfo -Statistics $false

                
                $sql = "CREATE NONCLUSTERED INDEX [Index] ON $($processing) ($($keysIndex), [State] ASC)"
                $null = Invoke-SqlcmdEx -Sql $sql -Database $Database -ConnectionInfo $ConnectionInfo -Statistics $false
    
                $sql = "CREATE NONCLUSTERED INDEX [Index_2] ON $($processing) ([Iteration]) INCLUDE ([Depth], [Fk])"
    
                $null = Invoke-SqlcmdEx -Sql $sql -Database $Database -ConnectionInfo $ConnectionInfo -Statistics $false

                $sql = "CREATE NONCLUSTERED INDEX [IX_BatchSource] ON $($processing) ([State] ASC, [Depth] ASC, [Iteration] ASC, [Source] ASC, [Fk] ASC, [Id] ASC) INCLUDE ($keysInclude)"

                $null = Invoke-SqlcmdEx -Sql $sql -Database $Database -ConnectionInfo $ConnectionInfo -Statistics $false
            }

        }
    }
}
