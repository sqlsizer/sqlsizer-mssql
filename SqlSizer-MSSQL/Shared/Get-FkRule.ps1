function Get-FkRule
{
    param
    (
        [string]$Rule
    )

    if ($Rule -eq "SET DEFAULT")
    {
        return [ForeignKeyRule]::SetDefault
    }

    if ($Rule -eq "SET NULL")
    {
        return [ForeignKeyRule]::SetNull
    }

    if ($Rule -eq "CASCADE")
    {
        return [ForeignKeyRule]::Cascade
    }

    return [ForeignKeyRule]::NoAction
}
