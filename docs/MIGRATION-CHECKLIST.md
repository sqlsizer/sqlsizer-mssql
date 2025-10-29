# Migration Checklist: Legacy to Refactored Algorithms

Use this checklist when migrating from legacy `Find-Subset` / `Find-RemovalSubset` to the refactored versions.

## Pre-Migration

- [ ] **Read documentation**
  - [ ] [Quick Start Guide](Quick-Start-Refactored-Algorithm.md)
  - [ ] [Algorithm Comparison](Algorithm-Flow-Comparison.md)
  - [ ] [Recent Changes](RECENT-CHANGES.md)

- [ ] **Understand benefits**
  - [ ] 45% lower code complexity
  - [ ] 50% memory reduction
  - [ ] 150+ unit tests for reliability
  - [ ] Better maintainability

- [ ] **Review compatibility**
  - [ ] Same parameters
  - [ ] Same return values
  - [ ] Same behavior
  - [ ] 100% backward compatible

## Testing Phase

### Step 1: Environment Setup
- [ ] Create test database (copy of production)
- [ ] Install/update SqlSizer-MSSQL module
  ```powershell
  Install-Module SqlSizer-MSSQL -Force
  Import-Module SqlSizer-MSSQL
  ```
- [ ] Verify module version
- [ ] Run unit tests
  ```powershell
  .\Tests\Run-Tests.ps1
  ```

### Step 2: Side-by-Side Testing
- [ ] Run original algorithm on test database
  ```powershell
  $sessionId1 = "test-original-$(Get-Date -Format 'yyyyMMddHHmmss')"
  # ... initialize and run Find-Subset
  $result1 = Get-SubsetTables -SessionId $sessionId1 ...
  ```

- [ ] Run refactored algorithm on test database
  ```powershell
  $sessionId2 = "test-refactored-$(Get-Date -Format 'yyyyMMddHHmmss')"
  # ... initialize and run Find-Subset-Refactored
  $result2 = Get-SubsetTables -SessionId $sessionId2 ...
  ```

- [ ] Compare results
  ```powershell
  Compare-Object $result1 $result2 -Property SchemaName, TableName, RowCount
  ```

- [ ] Verify row counts match
- [ ] Verify table lists match
- [ ] Check for any differences

### Step 3: Performance Testing
- [ ] Measure execution time (original)
  ```powershell
  Measure-Command { Find-Subset ... }
  ```

- [ ] Measure execution time (refactored)
  ```powershell
  Measure-Command { Find-Subset-Refactored ... }
  ```

- [ ] Compare memory usage
- [ ] Document performance differences

### Step 4: Edge Case Testing
- [ ] Test with empty start set
- [ ] Test with large start set (1M+ records)
- [ ] Test with deep FK chains (depth > 10)
- [ ] Test with circular FK references
- [ ] Test with multi-column primary keys
- [ ] Test with ColorMap/TraversalConfiguration
- [ ] Test with constraints (MaxDepth, MaxRecords)
- [ ] Test with ignored tables

### Step 5: Integration Testing
- [ ] Test full workflow end-to-end
- [ ] Test with actual queries from production
- [ ] Test data copy operations
- [ ] Test removal operations
- [ ] Test export/import operations
- [ ] Test with Azure SQL (if applicable)
- [ ] Test with Synapse (if applicable)

## Code Migration

### Step 6: Code Changes
- [ ] Identify all `Find-Subset` calls
  ```powershell
  # Search your codebase
  Get-ChildItem -Recurse -Include *.ps1 | Select-String "Find-Subset"
  ```

- [ ] Replace function names
  - [ ] `Find-Subset` → `Find-Subset-Refactored`
  - [ ] `Find-RemovalSubset` → `Find-RemovalSubset-Refactored`

- [ ] (Optional) Modernize ColorMap to TraversalConfiguration
  - [ ] Use `New-TraversalConfiguration` builder
  - [ ] Use `TraversalState` enum instead of `Color`
  - [ ] Use `TraversalRule` instead of `ColorItem`

- [ ] Update comments/documentation

### Step 7: Testing Migrated Code
- [ ] Run all automated tests
- [ ] Test in development environment
- [ ] Test in staging environment
- [ ] Get peer review
- [ ] Document any issues found

## Deployment

### Step 8: Staged Rollout
- [ ] Deploy to development
  - [ ] Monitor for errors
  - [ ] Validate results

- [ ] Deploy to staging
  - [ ] Run full test suite
  - [ ] Performance testing
  - [ ] User acceptance testing

- [ ] Deploy to production (phased)
  - [ ] Start with non-critical workloads
  - [ ] Monitor closely
  - [ ] Gradual expansion

### Step 9: Monitoring
- [ ] Set up alerts for failures
- [ ] Monitor execution times
- [ ] Monitor memory usage
- [ ] Monitor error logs
- [ ] Track performance metrics

### Step 10: Validation
- [ ] Verify results in production
- [ ] Compare with baseline metrics
- [ ] Check data integrity
- [ ] User validation
- [ ] Document success

## Post-Migration

### Step 11: Cleanup
- [ ] Remove legacy code paths (after stability period)
- [ ] Update documentation
- [ ] Update runbooks
- [ ] Update training materials
- [ ] Archive old test results

### Step 12: Optimization
- [ ] Review performance metrics
- [ ] Identify optimization opportunities
- [ ] Fine-tune configuration
- [ ] Update best practices

### Step 13: Knowledge Transfer
- [ ] Train team on new algorithms
- [ ] Share lessons learned
- [ ] Update team documentation
- [ ] Create troubleshooting guides

## Rollback Plan

If issues arise:

- [ ] **Immediate Rollback**
  - [ ] Change function calls back to original
  - [ ] Redeploy previous version
  - [ ] Document issues encountered

- [ ] **Root Cause Analysis**
  - [ ] Identify what went wrong
  - [ ] File bug report with details
  - [ ] Work with maintainers on fix

- [ ] **Retry Migration**
  - [ ] Apply fixes
  - [ ] Restart from testing phase
  - [ ] Document improvements

## Success Criteria

Migration is successful when:

- [ ] ✅ All tests passing
- [ ] ✅ Results match original algorithm
- [ ] ✅ Performance equal or better
- [ ] ✅ No production issues for 30 days
- [ ] ✅ Team trained and comfortable
- [ ] ✅ Documentation updated
- [ ] ✅ Monitoring in place
- [ ] ✅ Rollback plan tested

## Estimated Timeline

- **Small project** (< 10 scripts): 1-2 days
- **Medium project** (10-50 scripts): 1 week
- **Large project** (50+ scripts): 2-4 weeks
- **Enterprise** (complex integrations): 1-2 months

## Resources

### Documentation
- [Quick Start Guide](Quick-Start-Refactored-Algorithm.md)
- [Algorithm Comparison](Algorithm-Flow-Comparison.md)
- [Refactoring Guide](Find-Subset-Refactoring-Guide.md)
- [Testing Guide](Testing-Quick-Reference.md)

### Support
- GitHub Issues: Report problems
- GitHub Discussions: Ask questions
- Examples: `ExamplesNew/` directory

## Notes

Add project-specific notes here:

```
Date: __________
Team: __________
Project: __________

Notes:
-
-
-
```

## Sign-Off

- [ ] **Development Lead:** _________________ Date: _______
- [ ] **QA Lead:** _________________ Date: _______
- [ ] **Operations Lead:** _________________ Date: _______
- [ ] **Project Manager:** _________________ Date: _______

---

*Use this checklist as a guide. Adapt to your specific project needs and organizational requirements.*
