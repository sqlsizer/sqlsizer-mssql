function Enable-TableTrigger
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
        [string]$TriggerName,

        [Parameter(Mandatory = $true)]
        [SqlConnectionInfo]$ConnectionInfo
    )

    Write-Progress -Activity "Enabling trigger on table $SchemaName.$TableName" -PercentComplete 0

    $sql = "ENABLE TRIGGER $SchemaName.$TriggerName ON $SchemaName.$TableName"
    
    $null = Invoke-SqlcmdEx -Sql $sql -Database $Database -ConnectionInfo $ConnectionInfo -Statistics $false

    Write-Progress -Activity "Enabling trigger on table $SchemaName.$TableName" -Completed
}
