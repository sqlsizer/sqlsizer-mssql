﻿$Public  = @( Get-ChildItem -Path .\Public\*.ps1 -ErrorAction SilentlyContinue )
$Private = @( Get-ChildItem -Path .\Private\*.ps1 -ErrorAction SilentlyContinue )

foreach ($import in @($Public + $Private))
{
    Write-Verbose "."
    try
    {
        . $import.fullname

    }
    catch
    {
        Write-Error -Message "Failed to import function $($import.fullname): $_"
    }
}

Export-ModuleMember -Function $Public.Basename