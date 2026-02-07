function Get-ColumnValue
{
    param
    (
        [string]$ColumnName,
        [string]$DataType,
        [string]$Prefix,
        [bool]$Conversion,
        [bool]$OnlyXml,
        [string]$MaxLength = $null
    )

    if ($Conversion -eq $false)
    {
        return "$($Prefix)[" + $ColumnName + "]"
    }

    if ($OnlyXml)
    {
        if ($DataType -in @('xml'))
        {
            if (($null -ne $MaxLength) -and ($MaxLength -ne ""))
            {
                return "CONVERT(nvarchar($MaxLength), " + $Prefix + $ColumnName + ")"
            }
            else
            {
                return "CONVERT(nvarchar(max), " + $Prefix + $ColumnName + ")"
            }
        }
    }
    else
    {
        if ($DataType -in $('image', 'timestamp'))
        {
            return "CONVERT(nvarchar(max), CONVERT(varbinary(max), " + $Prefix + $ColumnName + "))"
        }

        if ($DataType -in @('hierarchyid', 'geography', 'xml'))
        {
            if (($null -ne $MaxLength) -and ($MaxLength -ne ""))
            {
                return "CONVERT(nvarchar($MaxLength), " + $Prefix + $ColumnName + ")"
            }
            else
            {
                return "CONVERT(nvarchar(max), " + $Prefix + $ColumnName + ")"
            }
        }

        if ($DataType -eq 'bit')
        {
            return "CONVERT(char(1), $Prefix[" + $ColumnName + "])"
        }
    }

    if (($null -ne $MaxLength) -and ($MaxLength -ne "") -and ($DataType -eq 'varchar'))
    {
        return "CONVERT(varchar($MaxLength), " + $Prefix + $ColumnName + ")"
    }

    if (($null -ne $MaxLength) -and ($MaxLength -ne "")  -and ($DataType -eq 'nvarchar'))
    {
        return "CONVERT(nvarchar($MaxLength), " + $Prefix + $ColumnName + ")"
    }

    return "$($Prefix)[" + $ColumnName + "]"
}
