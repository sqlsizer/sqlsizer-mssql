<#
.SYNOPSIS
    Resumes a previously interrupted Find-RemovalSubset traversal from a checkpoint file.

.DESCRIPTION
    Convenience wrapper that reads a checkpoint JSON file and calls Find-RemovalSubset
    with the -Resume flag. Restores traversal parameters (MaxBatchSize) from the
    checkpoint so the resumed traversal uses consistent settings.

    All traversal state (discovered rows, operations) is stored in SQL Server and
    survives process crashes. The checkpoint file only tracks the iteration counter
    and traversal parameters.

.PARAMETER CheckpointPath
    Path to the checkpoint JSON file created by a previous Find-RemovalSubset call.

.PARAMETER DatabaseInfo
    Metadata about the database structure (from Get-DatabaseInfo).

.PARAMETER ConnectionInfo
    SQL connection details (from New-SqlConnectionInfo).

.PARAMETER CheckpointInterval
    How often (in iterations) to save a checkpoint during the resumed run. Default: 5.

.EXAMPLE
    # Resume a crashed removal traversal
    $info = Get-DatabaseInfo -Database "MyDB" -ConnectionInfo $conn
    Resume-RemovalSubset -CheckpointPath "C:\temp\removal_checkpoint.json" `
        -DatabaseInfo $info -ConnectionInfo $conn

.NOTES
    The checkpoint file must have been created by Find-RemovalSubset with -CheckpointPath.
    The session (SqlSizer_<SessionId> schema) must still exist in the database.
#>

function Resume-RemovalSubset
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
        [int]$CheckpointInterval = 5
    )

    if (-not (Test-Path $CheckpointPath))
    {
        throw "Checkpoint file not found: $CheckpointPath"
    }

    $checkpoint = Get-Content -Path $CheckpointPath -Raw | ConvertFrom-Json

    if ($checkpoint.Type -ne 'RemovalSubset')
    {
        throw "Invalid checkpoint type '$($checkpoint.Type)'. Expected 'RemovalSubset'. Use Resume-Subset for subset checkpoints."
    }

    if ($checkpoint.Status -eq 'Completed')
    {
        Write-Warning "Checkpoint indicates traversal already completed. Nothing to resume."
        return [pscustomobject]@{
            Finished            = $true
            Initialized         = $true
            CompletedIterations = 0
        }
    }

    $params = @{
        SessionId          = $checkpoint.SessionId
        Database           = $checkpoint.Database
        DatabaseInfo       = $DatabaseInfo
        ConnectionInfo     = $ConnectionInfo
        CheckpointPath     = $CheckpointPath
        CheckpointInterval = $CheckpointInterval
        MaxBatchSize       = [int]$checkpoint.MaxBatchSize
        Resume             = $true
    }

    Write-Verbose "Resuming removal subset traversal for session '$($checkpoint.SessionId)' on database '$($checkpoint.Database)' from iteration $($checkpoint.LastCompletedIteration)"

    return Find-RemovalSubset @params
}
