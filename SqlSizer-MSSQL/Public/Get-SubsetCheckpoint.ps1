<#
.SYNOPSIS
    Reads and returns the contents of a traversal checkpoint file.

.DESCRIPTION
    Parses a checkpoint JSON file created by Find-Subset or Find-RemovalSubset
    and returns its contents as a PowerShell object. Useful for inspecting
    traversal progress without resuming.

.PARAMETER CheckpointPath
    Path to the checkpoint JSON file.

.EXAMPLE
    $cp = Get-SubsetCheckpoint -CheckpointPath "C:\temp\subset_checkpoint.json"
    $cp.Status              # "InProgress" or "Completed"
    $cp.LastCompletedIteration  # e.g. 42
    $cp.SessionId           # session GUID

.EXAMPLE
    # Check if a traversal is resumable
    $cp = Get-SubsetCheckpoint -CheckpointPath "C:\temp\checkpoint.json"
    if ($cp -and $cp.Status -ne "Completed") {
        Write-Host "Traversal can be resumed from iteration $($cp.LastCompletedIteration)"
    }

.OUTPUTS
    PSCustomObject with properties: Type, SessionId, Database, LastCompletedIteration,
    FullSearch, UseDfs, MaxBatchSize, Status, CreatedAt, UpdatedAt.
    Returns $null if the file does not exist.
#>

function Get-SubsetCheckpoint
{
    [cmdletbinding()]
    [outputtype([pscustomobject])]
    param
    (
        [Parameter(Mandatory = $true)]
        [string]$CheckpointPath
    )

    if (-not (Test-Path $CheckpointPath))
    {
        Write-Warning "Checkpoint file not found: $CheckpointPath"
        return $null
    }

    $checkpoint = Get-Content -Path $CheckpointPath -Raw | ConvertFrom-Json

    return $checkpoint
}
