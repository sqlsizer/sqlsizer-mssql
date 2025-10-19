# Archive: Legacy Algorithm Documentation

This directory contains documentation for the original `Find-Subset` and `Find-RemovalSubset` algorithms, which have been superseded by the refactored versions.

## Why Archived?

The project has transitioned to focus exclusively on the refactored algorithms (`Find-Subset-Refactored` and `Find-RemovalSubset-Refactored`) which provide:
- 12% less code
- 45% lower complexity
- No record duplication
- Better maintainability
- Same functionality

The original algorithms are still available in the codebase for backwards compatibility, but new projects should use the refactored versions.

## Archived Content

### Algorithm Documentation
- **Original Find-Subset Algorithm**: Color-based state machine with Yellow→Red+Green split operation
- **Original Find-RemovalSubset Algorithm**: String concatenation SQL generation
- **Color Map System**: Legacy Color enum (Red, Green, Yellow, Blue, Purple)

### Migration to Modern API

If you're using the original algorithm and want to migrate:

1. **Read the Migration Guide**: `../Find-Subset-Refactoring-Guide.md`
2. **Use the Quick Start**: `../Quick-Start-Refactored-Algorithm.md`
3. **Replace Function Name**: Change `Find-Subset` → `Find-Subset-Refactored`
4. **All Parameters Work**: Same interface, same behavior

### ColorMap Compatibility

The refactored algorithm maintains **100% backwards compatibility** with ColorMap configurations:
- See `../ColorMap-Compatibility-Guide.md` for details
- Color enum values automatically map to TraversalState enum
- No code changes required

## What's Not Archived

These documents remain in the main docs folder:
- `Find-Subset-Refactoring-Guide.md` - Migration guide
- `ColorMap-Compatibility-Guide.md` - Backwards compatibility
- `Quick-Start-Refactored-Algorithm.md` - Getting started with new algorithm

## Current Documentation

For up-to-date documentation on the refactored algorithms, see:
- Main `README.md` - Overview and examples
- `docs/Quick-Start-Refactored-Algorithm.md` - Quick start guide
- `docs/Algorithm-Flow-Comparison.md` - Visual comparisons
- `docs/REFACTORING-SUMMARY.md` - Executive summary

---

**Date Archived**: October 19, 2025  
**Reason**: Focus shifted to refactored algorithms  
**Status**: Original algorithms still available for backwards compatibility
