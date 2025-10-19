# ColorMap to TraversalConfiguration Migration Guide

## Overview

The `ColorMap` class and related types have been modernized with clearer, more descriptive names that better reflect their purpose in the refactored algorithm.

## New Class Names

| Legacy | `[Color]::Green` | `[TraversalState]::Include` | Include in subset |
| `[Color]::Red` | `[TraversalState]::Exclude` | Exclude from subset |
| `[Color]::Yellow` | `[TraversalState]::Pending` | Needs resolution |
| `[Color]::Blue` | `[TraversalState]::InboundOnly` | Only incoming FKs |
| `[Color]::Purple` | `[TraversalState]::Exclude` | *(Deprecated - was Bidirectional)* || Modern Name | Purpose |
|-------------|-------------|---------|
| `ColorMap` | `TraversalConfiguration` | Main configuration object |
| `ColorItem` | `TraversalRule` | Rule for a specific table |
| `ForcedColor` | `StateOverride` | Override traversal state |
| `Condition` | `TraversalConstraints` | Depth/count limits |

## Why the Change?

### Legacy Problems
- **ColorMap**: Implies color-based logic (confusing in refactored algorithm)
- **ColorItem**: Vague - what kind of item?
- **ForcedColor**: References deprecated color concept
- **Condition**: Too generic - condition for what?

### Modern Solutions
- **TraversalConfiguration**: Clear - configures traversal behavior
- **TraversalRule**: Explicit - a rule for traversal
- **StateOverride**: Precise - overrides the traversal state
- **TraversalConstraints**: Specific - constraints on traversal

## Backwards Compatibility

### ✅ 100% Compatible!

The legacy `ColorMap` classes **still work**. They exist in `SqlSizer-MSSQL-Types.ps1` unchanged:
- Old code continues to work without modification
- New code can use better names
- Conversion functions handle migrations

### Conversion Functions

Two helper functions provide seamless conversion:

```powershell
# Convert old to new
$colorMap = New-Object ColorMap
# ... configure ...
$config = New-TraversalConfigurationFromColorMap -ColorMap $colorMap

# Convert new to old (for backwards compatibility)
$config = New-Object TraversalConfiguration
# ... configure ...
$colorMap = New-ColorMapFromTraversalConfiguration -Configuration $config
```

## Migration Examples

### Example 1: Basic Configuration

**Before (ColorMap):**
```powershell
$colorMap = New-Object ColorMap

$item = New-Object ColorItem
$item.SchemaName = "Sales"
$item.TableName = "Orders"

$item.ForcedColor = New-Object ForcedColor
$item.ForcedColor.Color = [Color]::Green

$item.Condition = New-Object Condition
$item.Condition.MaxDepth = 3
$item.Condition.Top = 1000

$colorMap.Items = @($item)
```

**After (TraversalConfiguration):**
```powershell
$config = New-Object TraversalConfiguration

$rule = New-Object TraversalRule
$rule.SchemaName = "Sales"
$rule.TableName = "Orders"

$rule.StateOverride = New-Object StateOverride
$rule.StateOverride.State = [TraversalState]::Include

$rule.Constraints = New-Object TraversalConstraints
$rule.Constraints.MaxDepth = 3
$rule.Constraints.Top = 1000

$config.Rules = @($rule)
```

**Much clearer!**
- `Color.Green` → `TraversalState.Include` (self-documenting)
- `ColorItem` → `TraversalRule` (explicit purpose)
- `ForcedColor` → `StateOverride` (clear intent)
- `Condition` → `TraversalConstraints` (specific meaning)

### Example 2: Multiple Tables

**Before:**
```powershell
$colorMap = New-Object ColorMap
$items = @()

# Orders table
$item1 = New-Object ColorItem
$item1.SchemaName = "Sales"
$item1.TableName = "Orders"
$item1.ForcedColor = New-Object ForcedColor
$item1.ForcedColor.Color = [Color]::Green
$items += $item1

# OrderDetails table
$item2 = New-Object ColorItem
$item2.SchemaName = "Sales"
$item2.TableName = "OrderDetails"
$item2.ForcedColor = New-Object ForcedColor
$item2.ForcedColor.Color = [Color]::Red
$item2.Condition = New-Object Condition
$item2.Condition.MaxDepth = 2
$items += $item2

$colorMap.Items = $items
```

**After:**
```powershell
$config = New-Object TraversalConfiguration
$rules = @()

# Orders table - include with dependencies
$rule1 = New-Object TraversalRule -ArgumentList "Sales", "Orders"
$rule1.StateOverride = New-Object StateOverride -ArgumentList ([TraversalState]::Include)
$rules += $rule1

# OrderDetails table - exclude with depth limit
$rule2 = New-Object TraversalRule -ArgumentList "Sales", "OrderDetails"
$rule2.StateOverride = New-Object StateOverride -ArgumentList ([TraversalState]::Exclude)
$rule2.Constraints = New-Object TraversalConstraints
$rule2.Constraints.MaxDepth = 2
$rules += $rule2

$config.Rules = $rules
```

### Example 3: Foreign Key Filtering

**Before:**
```powershell
$item = New-Object ColorItem
$item.SchemaName = "Sales"
$item.TableName = "Orders"
$item.Condition = New-Object Condition
$item.Condition.SourceSchemaName = "Sales"
$item.Condition.SourceTableName = "Customers"
$item.Condition.FkName = "FK_Orders_Customers"
```

**After:**
```powershell
$rule = New-Object TraversalRule "Sales", "Orders"
$rule.Constraints = New-Object TraversalConstraints
$rule.Constraints.SourceSchemaName = "Sales"
$rule.Constraints.SourceTableName = "Customers"
$rule.Constraints.ForeignKeyName = "FK_Orders_Customers"  # Note: better property name!
```

## Using in Find-Subset-Refactored

### Option 1: Use Legacy ColorMap (Still Works!)

```powershell
# Your existing code
$colorMap = New-Object ColorMap
# ... configure as before ...

# Works with refactored algorithm!
Find-Subset-Refactored `
    -Database $database `
    -DatabaseInfo $dbInfo `
    -ConnectionInfo $connInfo `
    -ColorMap $colorMap `  # ✅ Still accepted!
    -SessionId $sessionId
```

### Option 2: Use Modern TraversalConfiguration

```powershell
# New modern code
$config = New-Object TraversalConfiguration
# ... configure with clear names ...

# Also works!
Find-Subset-Refactored `
    -Database $database `
    -DatabaseInfo $dbInfo `
    -ConnectionInfo $connInfo `
    -TraversalConfiguration $config `  # ✅ New parameter name!
    -SessionId $sessionId
```

### Option 3: Hybrid Approach

```powershell
# Have legacy ColorMap from existing code
$colorMap = Get-LegacyConfiguration

# Convert to modern
$config = New-TraversalConfigurationFromColorMap -ColorMap $colorMap

# Use modern API
Find-Subset-Refactored -TraversalConfiguration $config ...
```

## Helper Methods

### TraversalConstraints Methods

The new `TraversalConstraints` class includes helpful methods:

```powershell
$constraints = New-Object TraversalConstraints
$constraints.Top = 1000
$constraints.MaxDepth = 3

# Check what's configured
$constraints.HasTopLimit()          # True
$constraints.HasDepthLimit()        # True
$constraints.HasSourceFilter()      # False
$constraints.HasForeignKeyFilter()  # False
```

### TraversalRule Constructors

Convenient constructors for quick setup:

```powershell
# Empty constructor
$rule = New-Object TraversalRule

# With schema and table
$rule = New-Object TraversalRule -ArgumentList "Sales", "Orders"

# With state override
$override = New-Object StateOverride -ArgumentList ([TraversalState]::Include)
```

## Property Name Changes

| Old Property | New Property | Notes |
|--------------|--------------|-------|
| `ColorMap.Items` | `TraversalConfiguration.Rules` | More descriptive |
| `ColorItem.ForcedColor` | `TraversalRule.StateOverride` | Clearer intent |
| `ColorItem.Condition` | `TraversalRule.Constraints` | More specific |
| `Condition.FkName` | `TraversalConstraints.ForeignKeyName` | Full name |

## State Name Mapping

When using `StateOverride` instead of `ForcedColor`:

| Old Color | New State | Meaning |
|-----------|-----------|---------|
| `[Color]::Green` | `[TraversalState]::Include` | Include in subset |
| `[Color]::Red` | `[TraversalState]::Exclude` | Exclude from subset |
| `[Color]::Yellow` | `[TraversalState]::Pending` | Needs evaluation |
| `[Color]::Purple` | `[TraversalState]::Bidirectional` | Both directions |
| `[Color]::Blue` | `[TraversalState]::InboundOnly` | Incoming FKs only |

## Migration Strategies

### Strategy 1: No Changes (Easiest)
**Keep using ColorMap** - it still works!
```powershell
# No code changes needed
$colorMap = New-Object ColorMap
# ... existing code ...
Find-Subset-Refactored -ColorMap $colorMap ...
```

### Strategy 2: Gradual Migration
**Convert during maintenance:**
1. Keep existing ColorMap creation code
2. Add conversion before using:
   ```powershell
   $colorMap = ... # existing code
   $config = New-TraversalConfigurationFromColorMap -ColorMap $colorMap
   Find-Subset-Refactored -TraversalConfiguration $config ...
   ```
3. Refactor creation code over time

### Strategy 3: Full Modernization
**Rewrite for new projects:**
1. Replace all `ColorMap` with `TraversalConfiguration`
2. Replace all `ColorItem` with `TraversalRule`
3. Replace all `ForcedColor` with `StateOverride`
4. Replace all `Condition` with `TraversalConstraints`
5. Use `[TraversalState]` instead of `[Color]`

## Testing Migration

### Validation Script

```powershell
# Test conversion round-trip
$original = New-Object ColorMap
$item = New-Object ColorItem
$item.SchemaName = "Sales"
$item.TableName = "Orders"
$item.ForcedColor = New-Object ForcedColor
$item.ForcedColor.Color = [Color]::Green
$original.Items = @($item)

# Convert to modern
$modern = New-TraversalConfigurationFromColorMap -ColorMap $original

# Convert back
$restored = New-ColorMapFromTraversalConfiguration -Configuration $modern

# Compare
if ($restored.Items[0].SchemaName -eq $original.Items[0].SchemaName -and
    $restored.Items[0].TableName -eq $original.Items[0].TableName -and
    $restored.Items[0].ForcedColor.Color -eq $original.Items[0].ForcedColor.Color)
{
    Write-Host "✅ Conversion successful!" -ForegroundColor Green
}
else
{
    Write-Host "❌ Conversion failed!" -ForegroundColor Red
}
```

## Benefits Summary

### Code Clarity
| Aspect | Before | After | Improvement |
|--------|--------|-------|-------------|
| Purpose | ColorMap | TraversalConfiguration | Self-documenting |
| Rules | ColorItem | TraversalRule | Explicit meaning |
| Override | ForcedColor | StateOverride | Clear intent |
| Limits | Condition | TraversalConstraints | Specific purpose |
| States | Color enum | TraversalState enum | Descriptive names |

### Developer Experience
- ✅ **Intellisense**: Better property name suggestions
- ✅ **Readability**: Code documents itself
- ✅ **Maintainability**: Clear purpose at a glance
- ✅ **Onboarding**: New developers understand immediately
- ✅ **Backwards Compatible**: No breaking changes!

## Recommendation

**For New Code:**
- Use `TraversalConfiguration` and related modern classes
- More readable and self-documenting
- Better IDE support

**For Existing Code:**
- Keep using `ColorMap` if it works
- Migrate gradually during maintenance
- No urgent need to change

**For Mixed Projects:**
- Use conversion functions at boundaries
- Modern code internally, legacy at interfaces
- Best of both worlds

## Related Documentation

- `ColorMap-Compatibility-Guide.md` - Original Color enum compatibility
- `Find-Subset-Refactoring-Guide.md` - Algorithm improvements
- `README.md` - Updated with modern terminology

---

**Version**: 1.0  
**Date**: October 2025  
**Status**: Production Ready
