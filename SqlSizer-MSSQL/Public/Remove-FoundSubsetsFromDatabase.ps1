function Remove-FoundSubsetsFromDatabase
{
    [cmdletbinding()]
    param
    (
        [Parameter(Mandatory = $true)]
        [string[]]$Sessions,
        
        [Parameter(Mandatory = $true)]
        [string]$Database,
        
        [Parameter(Mandatory = $false)]
        [int]$Step = 100000,

        [Parameter(Mandatory = $true)]
        [DatabaseInfo]$DatabaseInfo,

        [Parameter(Mandatory = $true)]
        [SqlConnectionInfo]$ConnectionInfo
    )
    
    Write-Progress -Activity "Removing subsets" -PercentComplete 0

    foreach ($session in $Sessions)
    {
        Remove-FoundSubsetFromDatabase -SessionId $session -Database $Database -Step $Step -DatabaseInfo $DatabaseInfo -ConnectionInfo $ConnectionInfo
    }

    Write-Progress -Activity "Removing subsets" -Completed
}
