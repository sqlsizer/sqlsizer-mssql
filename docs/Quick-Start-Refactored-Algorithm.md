# Quick Start: Using the Refactored Algorithm

## When to Use Which Algorithm?

### Use `Find-Subset-Refactored` (New) When:
- ✅ Starting a new project
- ✅ You want clearer, more maintainable code
- ✅ Memory usage is a concern (large subsets)
- ✅ You want to understand what the algorithm is doing
- ✅ You're comfortable with testing new features

### Use `Find-Subset` (Original) When:
- ✅ You have production code that works
- ✅ You need proven, battle-tested stability
- ✅ You're risk-averse about changes
- ✅ Migration timing isn't right yet

## Simple Example: Switching to Refactored Algorithm

### Before (Original)
```powershell
# Find subset using original algorithm
Find-Subset `
    -Database $database `
    -ConnectionInfo $connection `
    -DatabaseInfo $info `
    -FullSearch $false `
    -UseDfs $false `
    -SessionId $sessionId
```

### After (Refactored) - Just Change the Function Name!
```powershell
# Find subset using refactored algorithm
Find-Subset-Refactored `
    -Database $database `
    -ConnectionInfo $connection `
    -DatabaseInfo $info `
    -FullSearch $false `
    -UseDfs $false `
    -SessionId $sessionId
```

**That's it!** All parameters are identical. The return value is identical. The behavior is identical (but cleaner internally).

## Understanding the New States

### Color to State Mapping

If you're familiar with the original colors, here's how they map:

| Original Color | Refactored State | Meaning |
|---------------|------------------|---------|
| `Green` | `Include` | Records to include in subset |
| `Red` | `Exclude` | Records to exclude from subset |
| `Yellow` | `Pending` | Undecided (resolved automatically) |
| `Blue` | `InboundOnly` | Only incoming FKs |
| `Purple` | `Exclude` | *(Deprecated - was Bidirectional)* |

### When You Define Queries

```powershell
# Original approach (still works!)
$query = New-Object -TypeName Query
$query.Color = [Color]::Yellow
$query.Schema = "Person"
$query.Table = "Person"
# ... rest of query setup

# The refactored algorithm automatically converts Color → TraversalState
# Yellow → Pending
# Green → Include
# Red → Exclude
```

### ColorMap Still Works!

```powershell
# Your existing ColorMap configurations work unchanged
$colorMap = New-Object -TypeName ColorMap
$item = New-Object -TypeName ColorItem
$item.SchemaName = "Sales"
$item.TableName = "Order"
$item.ForcedColor = New-Object -TypeName ForcedColor
$item.ForcedColor.Color = [Color]::Green  # Maps to TraversalState.Include

$colorMap.Items = @($item)

# Works with both algorithms!
Find-Subset-Refactored ... -ColorMap $colorMap
```

## Key Differences You'll Notice

### 1. **No More "Split" Operation**

**Original Algorithm:**
```
Processing Yellow records...
  → Splitting into Red and Green
  → Creating 200 Red records
  → Creating 200 Green records
  → Total: 400 records (duplicated!)
```

**Refactored Algorithm:**
```
Processing Pending records...
  → Marking as Include or Exclude (in place)
  → Total: 200 records (no duplication!)
```

### 2. **Clearer Progress Messages**

**Original:**
```
Processing: Sales.Orders (Color: 3, Depth: 2)
```

**Refactored:**
```
Processing: Sales.Orders (State: Pending, Depth: 2)
```

Much clearer what's happening!

### 3. **Better Memory Usage**

For a subset with 10,000 Yellow/Pending records:

- **Original**: Creates 30,000 records (10k Yellow + 10k Red + 10k Green)
- **Refactored**: Keeps 10,000 records (resolves Pending → Include/Exclude in place)

**Result**: ~67% memory reduction during processing!

## Testing Your Migration

### Step 1: Test Side-by-Side

```powershell
# Test original
$sessionId1 = "test-original-$(Get-Date -Format 'yyyyMMddHHmmss')"
Start-SqlSizerSession ... -SessionId $sessionId1
# ... run original algorithm
$result1 = Get-SubsetTables ... -SessionId $sessionId1

# Test refactored
$sessionId2 = "test-refactored-$(Get-Date -Format 'yyyyMMddHHmmss')"
Start-SqlSizerSession ... -SessionId $sessionId2
# ... run refactored algorithm  
$result2 = Get-SubsetTables ... -SessionId $sessionId2

# Compare results
Compare-Object $result1 $result2 -Property SchemaName, TableName, RowCount
```

### Step 2: Validate Results

```powershell
# Both should find the same subset
foreach ($table in $result1) {
    $table2 = $result2 | Where-Object { 
        $_.SchemaName -eq $table.SchemaName -and 
        $_.TableName -eq $table.TableName 
    }
    
    if ($table.RowCount -ne $table2.RowCount) {
        Write-Warning "Mismatch: $($table.SchemaName).$($table.TableName)"
        Write-Warning "  Original: $($table.RowCount) rows"
        Write-Warning "  Refactored: $($table2.RowCount) rows"
    }
}
```

### Step 3: Performance Testing

```powershell
# Measure original
$start = Get-Date
Find-Subset ... -SessionId $sessionId1
$duration1 = (Get-Date) - $start
Write-Host "Original: $($duration1.TotalSeconds) seconds"

# Measure refactored
$start = Get-Date
Find-Subset-Refactored ... -SessionId $sessionId2
$duration2 = (Get-Date) - $start
Write-Host "Refactored: $($duration2.TotalSeconds) seconds"

# Compare
$improvement = (($duration1.TotalSeconds - $duration2.TotalSeconds) / $duration1.TotalSeconds) * 100
Write-Host "Performance change: $([Math]::Round($improvement, 2))%"
```

## Common Migration Scenarios

### Scenario 1: Simple Script

```powershell
# Change line 47 from:
Find-Subset ...

# To:
Find-Subset-Refactored ...

# That's it! Everything else stays the same.
```

### Scenario 2: Module/Function

```powershell
# Add a parameter to control which algorithm
function Export-DatabaseSubset {
    param(
        # ... existing params
        [bool]$UseRefactoredAlgorithm = $false
    )
    
    if ($UseRefactoredAlgorithm) {
        Find-Subset-Refactored @PSBoundParameters
    } else {
        Find-Subset @PSBoundParameters
    }
}
```

### Scenario 3: Gradual Rollout

```powershell
# Use environment variable or config file
$useNewAlgorithm = [Environment]::GetEnvironmentVariable("SQLSIZER_USE_REFACTORED")

if ($useNewAlgorithm -eq "true") {
    Write-Verbose "Using refactored algorithm"
    Find-Subset-Refactored ...
} else {
    Write-Verbose "Using original algorithm"
    Find-Subset ...
}
```

## Troubleshooting

### "I get different results!"

This shouldn't happen - they should be identical. Please report this!

1. Check if you're using the same `FullSearch` setting
2. Verify ColorMap is the same for both
3. Compare the Operations table contents
4. File an issue with details

### "The refactored version is slower!"

Unexpected - it should be similar or faster. Check:

1. Are you on Azure SQL? (May have query optimization differences)
2. Database statistics up to date?
3. Is it the first run? (Query plan caching)
4. Large or small subset? (Different performance characteristics)

### "I get an error about missing types"

Make sure to load the enhanced types:

```powershell
# At the top of your script
. "$PSScriptRoot\Types\SqlSizer-MSSQL-Types-Enhanced.ps1"
```

Or if using the module:
```powershell
Import-Module SqlSizer-MSSQL -Force
```

## Getting Help

- 📖 Read: `docs/Find-Subset-Refactoring-Guide.md` - Technical details
- 📊 Compare: `docs/Algorithm-Flow-Comparison.md` - Visual diagrams
- 📝 Review: `docs/REFACTORING-SUMMARY.md` - Executive summary
- 💬 Ask: Open an issue on GitHub

## Summary Checklist

Before migrating to refactored algorithm:

- [ ] Read this quick start guide
- [ ] Test on a copy of your database
- [ ] Compare results with original algorithm
- [ ] Measure performance difference
- [ ] Validate memory usage improvement
- [ ] Test with your specific ColorMap configurations
- [ ] Run in non-production first
- [ ] Keep original as fallback (just in case)
- [ ] Monitor first production runs closely
- [ ] Celebrate cleaner, more maintainable code! 🎉

**Remember**: Both algorithms produce identical results. The difference is internal implementation quality. You can switch back and forth safely.
