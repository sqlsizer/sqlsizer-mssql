function New-EmptyDatabase
{
    [cmdletbinding()]
    param
    (
        [Parameter(Mandatory = $true)]
        [string]$Database,

        [Parameter(Mandatory = $true)]
        [string]$NewDatabase,

        [Parameter(Mandatory = $true)]
        [DatabaseInfo]$DatabaseInfo,

        [Parameter(Mandatory = $true)]
        [SqlConnectionInfo]$ConnectionInfo
    )

    # Copy db
    Copy-Database -Database $Database -NewDatabase $NewDatabase -ConnectionInfo $ConnectionInfo

    # Wait for a copy
    do
    {
        $found = Test-DatabaseOnline -Database $NewDatabase -ConnectionInfo $ConnectionInfo
        Start-Sleep -Seconds 5
    }
    while ($found -eq $false)

    # Clear copy
    Disable-ForeignKeys -Database $NewDatabase -ConnectionInfo $ConnectionInfo -DatabaseInfo $DatabaseInfo
    Clear-Database -Database $NewDatabase -ConnectionInfo $ConnectionInfo -DatabaseInfo $DatabaseInfo
    Enable-ForeignKeys -Database $NewDatabase -ConnectionInfo $ConnectionInfo -DatabaseInfo $DatabaseInfo
    Format-Indexes -Database $NewDatabase -ConnectionInfo $ConnectionInfo -DatabaseInfo $DatabaseInfo
    Compress-Database -Database $NewDatabase -ConnectionInfo $ConnectionInfo
}
