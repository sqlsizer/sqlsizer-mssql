function Export-SubsetImpactReport
{
    <#
    .SYNOPSIS
        Exports a SqlSizer subset impact report to JSON, Markdown, or HTML.

    .DESCRIPTION
        Builds the same read-only report returned by Get-SubsetImpactReport and writes it
        to a shareable file. The export does not include row samples or full row data.

    .PARAMETER Path
        Destination file path.

    .PARAMETER FilePath
        Alias for Path, kept for compatibility with older examples.

    .PARAMETER Format
        Output format: Json, Markdown, or Html.

    .OUTPUTS
        FileInfo for the written report file.
    #>
    [cmdletbinding()]
    [outputtype([System.IO.FileInfo])]
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

        [Parameter(Mandatory = $true)]
        [Alias('FilePath')]
        [string]$Path,

        [Parameter(Mandatory = $false)]
        [ValidateSet('Json', 'Markdown', 'Html')]
        [string]$Format = 'Json'
    )

    $report = Get-SubsetImpactReport `
        -SessionId $SessionId `
        -Database $Database `
        -DatabaseInfo $DatabaseInfo `
        -ConnectionInfo $ConnectionInfo

    switch ($Format)
    {
        'Json' {
            $content = $report | ConvertTo-Json -Depth 10
        }
        'Markdown' {
            $content = ConvertTo-SubsetImpactReportMarkdown -Report $report
        }
        'Html' {
            $content = ConvertTo-SubsetImpactReportHtml -Report $report
        }
    }

    $resolvedPath = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($Path)
    $parentPath = Split-Path -Parent $resolvedPath

    if (($null -ne $parentPath) -and ($parentPath -ne '') -and (-not (Test-Path -Path $parentPath)))
    {
        $null = New-Item -ItemType Directory -Path $parentPath -Force
    }

    Set-Content -Path $resolvedPath -Value $content -Encoding UTF8
    return Get-Item -Path $resolvedPath
}
