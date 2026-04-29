function Get-SubsetUnreachableEdges
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
        [SqlConnectionInfo]$ConnectionInfo
    )

    $impact = Get-SubsetRelationshipImpact `
        -SessionId $SessionId `
        -Database $Database `
        -DatabaseInfo $DatabaseInfo `
        -ConnectionInfo $ConnectionInfo

    if ($impact.Unreached.Count -gt 0)
    {
        return $impact.Unreached | ForEach-Object {
            [pscustomobject]@{
                Name     = $_.Name
                FkSchema = $_.FromSchema
                FkTable  = $_.FromTable
                Schema   = $_.ToSchema
                TableName = $_.ToTable
            }
        }
    }

    return $null
}
