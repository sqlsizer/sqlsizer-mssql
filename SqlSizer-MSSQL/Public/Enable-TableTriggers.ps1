function Enable-TableTriggers
{
    [cmdletbinding()]
    param
    (
        [Parameter(Mandatory = $true)]
        [string]$Database,

        [Parameter(Mandatory = $true)]
        [string]$SchemaName,

        [Parameter(Mandatory = $true)]
        [string]$TableName,

        [Parameter(Mandatory = $true)]
        [SqlConnectionInfo]$ConnectionInfo
    )

    if ($ConnectionInfo.IsSynapse -eq $true)
    {
        throw "Feature not supported in Synapse"
    }
    
    Write-Progress -Activity "Enabling all triggers on table $SchemaName.$TableName" -PercentComplete 0

    $sql = "ENABLE TRIGGER ALL ON $SchemaName.$TableName"

    $null = Invoke-SqlcmdEx -Sql $sql -Database $Database -ConnectionInfo $ConnectionInfo -Statistics $false

    Write-Progress -Activity "Enabling all triggers on table $SchemaName.$TableName" -Completed
}
