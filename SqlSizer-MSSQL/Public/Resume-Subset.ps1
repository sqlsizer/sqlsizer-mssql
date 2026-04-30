<#
.SYNOPSIS
    Resumes a previously interrupted Find-Subset traversal from a checkpoint file.

.DESCRIPTION
    Convenience wrapper that reads a checkpoint JSON file and calls Find-Subset with
    the -Resume flag. Restores traversal parameters (FullSearch, UseDfs, MaxBatchSize)
    from the checkpoint so the resumed traversal uses consistent settings.

    All traversal state (discovered rows, operations) is stored in SQL Server and
    survives process crashes. The checkpoint file only tracks the iteration counter
    and traversal parameters.

.PARAMETER CheckpointPath
    Path to the checkpoint JSON file created by a previous Find-Subset call.

.PARAMETER DatabaseInfo
    Metadata about the database structure (from Get-DatabaseInfo).

.PARAMETER ConnectionInfo
    SQL connection details (from New-SqlConnectionInfo).

.PARAMETER IgnoredTables
    Optional list of tables to skip during traversal.

.PARAMETER TraversalConfiguration
    Optional traversal configuration with state overrides and constraints.

.PARAMETER CheckpointInterval
    How often (in iterations) to save a checkpoint during the resumed run. Default: 5.

.PARAMETER MaxSubsetPercentOfSource
    Warn when included subset rows exceed this percentage of PK-bearing source rows.
    Default: 20. Set to 0 to disable row-ratio warnings.

.PARAMETER MaxReachableTablePercent
    Warn before traversal when metadata reachability can cover more than this percentage
    of PK-bearing user tables. Default: 80. Set to 0 to disable preflight warnings.

.PARAMETER SubsetGuardCheckInterval
    How often (in traversal iterations) to check the runtime subset-size guard. Default: 5.

.PARAMETER ThrowOnSubsetGuardExceeded
    Throw a terminating error when the runtime subset-size guard is exceeded. Default: false.

.EXAMPLE
    # Resume a crashed traversal
    $info = Get-DatabaseInfo -Database "MyDB" -ConnectionInfo $conn
    Resume-Subset -CheckpointPath "C:\temp\subset_checkpoint.json" `
        -DatabaseInfo $info -ConnectionInfo $conn

.NOTES
    The checkpoint file must have been created by Find-Subset with -CheckpointPath.
    The session (SqlSizer_<SessionId> schema) must still exist in the database.
#>

function Resume-Subset
{
    [cmdletbinding()]
    [outputtype([pscustomobject])]
    param
    (
        [Parameter(Mandatory = $true)]
        [string]$CheckpointPath,

        [Parameter(Mandatory = $true)]
        [DatabaseInfo]$DatabaseInfo,

        [Parameter(Mandatory = $true)]
        [SqlConnectionInfo]$ConnectionInfo,

        [Parameter(Mandatory = $false)]
        [TableInfo2[]]$IgnoredTables,

        [Parameter(Mandatory = $false)]
        [TraversalConfiguration]$TraversalConfiguration = $null,

        [Parameter(Mandatory = $false)]
        [int]$CheckpointInterval = 5,

        [Parameter(Mandatory = $false)]
        [double]$MaxSubsetPercentOfSource = 20.0,

        [Parameter(Mandatory = $false)]
        [double]$MaxReachableTablePercent = 80.0,

        [Parameter(Mandatory = $false)]
        [int]$SubsetGuardCheckInterval = 5,

        [Parameter(Mandatory = $false)]
        [bool]$ThrowOnSubsetGuardExceeded = $false
    )

    if (-not (Test-Path $CheckpointPath))
    {
        throw "Checkpoint file not found: $CheckpointPath"
    }

    $checkpoint = Get-Content -Path $CheckpointPath -Raw | ConvertFrom-Json

    if ($checkpoint.Type -ne 'Subset')
    {
        throw "Invalid checkpoint type '$($checkpoint.Type)'. Expected 'Subset'. Use Resume-RemovalSubset for removal checkpoints."
    }

    if ($checkpoint.Status -eq 'Completed')
    {
        Write-Warning "Checkpoint indicates traversal already completed. Nothing to resume."
        return [pscustomobject]@{
            Finished            = $true
            Initialized         = $true
            CompletedIterations = 0
            SubsetSizeGuard     = $null
        }
    }

    if ((-not $PSBoundParameters.ContainsKey('MaxSubsetPercentOfSource')) -and $checkpoint.PSObject.Properties['MaxSubsetPercentOfSource'])
    {
        $MaxSubsetPercentOfSource = [double]$checkpoint.MaxSubsetPercentOfSource
    }
    if ((-not $PSBoundParameters.ContainsKey('MaxReachableTablePercent')) -and $checkpoint.PSObject.Properties['MaxReachableTablePercent'])
    {
        $MaxReachableTablePercent = [double]$checkpoint.MaxReachableTablePercent
    }
    if ((-not $PSBoundParameters.ContainsKey('SubsetGuardCheckInterval')) -and $checkpoint.PSObject.Properties['SubsetGuardCheckInterval'])
    {
        $SubsetGuardCheckInterval = [int]$checkpoint.SubsetGuardCheckInterval
    }
    if ((-not $PSBoundParameters.ContainsKey('ThrowOnSubsetGuardExceeded')) -and $checkpoint.PSObject.Properties['ThrowOnSubsetGuardExceeded'])
    {
        $ThrowOnSubsetGuardExceeded = [bool]$checkpoint.ThrowOnSubsetGuardExceeded
    }

    $params = @{
        SessionId          = $checkpoint.SessionId
        Database           = $checkpoint.Database
        DatabaseInfo       = $DatabaseInfo
        ConnectionInfo     = $ConnectionInfo
        CheckpointPath     = $CheckpointPath
        CheckpointInterval = $CheckpointInterval
        FullSearch         = [bool]$checkpoint.FullSearch
        UseDfs             = [bool]$checkpoint.UseDfs
        MaxBatchSize       = [int]$checkpoint.MaxBatchSize
        MaxSubsetPercentOfSource = $MaxSubsetPercentOfSource
        MaxReachableTablePercent = $MaxReachableTablePercent
        SubsetGuardCheckInterval = $SubsetGuardCheckInterval
        ThrowOnSubsetGuardExceeded = $ThrowOnSubsetGuardExceeded
        Resume             = $true
    }

    if ($IgnoredTables)
    {
        $params['IgnoredTables'] = $IgnoredTables
    }

    if ($TraversalConfiguration)
    {
        $params['TraversalConfiguration'] = $TraversalConfiguration
    }

    Write-Verbose "Resuming subset traversal for session '$($checkpoint.SessionId)' on database '$($checkpoint.Database)' from iteration $($checkpoint.LastCompletedIteration)"

    return Find-Subset @params
}
