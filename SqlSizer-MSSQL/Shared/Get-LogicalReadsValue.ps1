function Get-LogicalReadsValue
{
    [cmdletbinding()]
    [outputtype([System.Int32])]
    param
    (
        [Parameter(Mandatory = $true)]
        [AllowNull()]
        [AllowEmptyString()]
        [string[]]$Message
    )

    if ($null -eq $Message)
    {
        return 0
    }

    $result = 0

    foreach ($row in $Message)
    {
        $position = $row.IndexOf('logical reads');
        if ($position -ne -1)
        {
            $start = $position + 14
            $end = $row.IndexOf(',', $start)

            $logicalReads = $row.Substring($start, $end - $start) -as [int]
            $result += $logicalReads
        }
    }

    return $result
}
