# Load types directly in module scope
# This ensures types are available to module functions regardless of how PowerShell scopes them
. (Join-Path $PSScriptRoot "Types\SqlSizer-MSSQL-Types.ps1")

$Public  = @( Get-ChildItem -Path ($PSScriptRoot + ".\Public\*.ps1") -ErrorAction SilentlyContinue )
$Private = @( Get-ChildItem -Path ($PSScriptRoot + ".\Shared\*.ps1") -ErrorAction SilentlyContinue )

foreach ($import in @($Public + $Private))
{
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
