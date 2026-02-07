function Get-Prefix
{
    [outputtype([System.String])]
    [cmdletbinding()]
    param
    (
        [Parameter(Mandatory = $true)]
        [string]$Value
    )


    for ($i = 0; $i -lt $Value.Length; $i++)
    {
        if ($Value[$i] -in ('.', ',', '_'))
        {
            return $Value.Substring(0, $i)
        }
    }

    return ""
}
