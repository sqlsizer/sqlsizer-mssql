function Update-DatabaseInfo
{
    [cmdletbinding()]
    param
    (
        [Parameter(Mandatory = $true)]
        [DatabaseInfo]$DatabaseInfo,

        [Parameter(Mandatory = $true)]
        [string]$Database,

        [Parameter(Mandatory = $false)]
        [bool]$MeasureSize = $false,

        [Parameter(Mandatory = $true)]
        [SqlConnectionInfo]$ConnectionInfo
    )

    $info = Get-DatabaseInfo -Database $Database -ConnectionInfo $ConnectionInfo -MeasureSize $MeasureSize

    $DatabaseInfo.Views.Clear()
    if ($null -ne $info.Views)
    {
        foreach ($view in $info.Views)
        {
            $null = $DatabaseInfo.Views.Add($view)
        }
    }

    $DatabaseInfo.Tables.Clear()
    if ($null -ne $info.Tables)
    {
        foreach ($table in $info.Tables)
        {
            $null = $DatabaseInfo.Tables.Add($table)
        }
    }

    $DatabaseInfo.StoredProcedures.Clear()
    if ($null -ne $info.StoredProcedures)
    {
        foreach ($sp in $info.StoredProcedures)
        {
            $null = $DatabaseInfo.StoredProcedures.Add($sp)
        }
    }

    $DatabaseInfo.Schemas.Clear()
    if ($null -ne $info.Schemas)
    {
        foreach ($schema in $info.Schemas)
        {
            $null = $DatabaseInfo.Schemas.Add($schema)
        }
    }

    return
}
