# Quick Reference: Testing SqlSizer-MSSQL

## Running Tests

### All Tests
```powershell
.\Tests\Run-Tests.ps1
```

### With Code Coverage
```powershell
.\Tests\Run-Tests.ps1 -CodeCoverage
```

### Specific Test File
```powershell
Invoke-Pester -Path .\Tests\TraversalHelpers.Tests.ps1
```

### Watch Mode (Auto-run on changes)
```powershell
# Install if needed
Install-Module -Name Pester.Watch

# Watch and auto-run
Invoke-PesterWatch -Path .\Tests\
```

## Common Test Commands

### Run Single Test
```powershell
Invoke-Pester -Path .\Tests\TraversalHelpers.Tests.ps1 -TestName "Get-NewTraversalState*"
```

### Run Tests by Tag
```powershell
# Run only integration tests
Invoke-Pester -Path .\Tests\ -Tag Integration

# Exclude integration tests
Invoke-Pester -Path .\Tests\ -ExcludeTag Integration
```

### Debug Tests
```powershell
# Enable debugging
$PesterDebugPreference_Debug = $true
Invoke-Pester -Path .\Tests\TraversalHelpers.Tests.ps1 -Output Diagnostic
```

## Test Structure Quick Reference

### Basic Test Template
```powershell
Describe 'FunctionName' {
    It 'Should do something' {
        $result = FunctionName -Parameter 'value'
        $result | Should -Be 'expected'
    }
}
```

### With Setup/Teardown
```powershell
Describe 'FunctionName' {
    BeforeAll {
        # Run once before all tests
        $script:sharedData = Initialize-TestData
    }
    
    BeforeEach {
        # Run before each test
        $testData = Get-FreshCopy
    }
    
    AfterEach {
        # Run after each test
        Clear-TestData
    }
    
    It 'Should do something' {
        # Test code
    }
}
```

### Using Context
```powershell
Describe 'FunctionName' {
    Context 'When condition A' {
        It 'Should behave this way' { }
    }
    
    Context 'When condition B' {
        It 'Should behave that way' { }
    }
}
```

## Common Assertions

```powershell
# Equality
$result | Should -Be $expected
$result | Should -Not -Be $unexpected

# Type checking
$result | Should -BeOfType [string]

# Null/Empty
$result | Should -BeNullOrEmpty
$result | Should -Not -BeNullOrEmpty

# Numeric comparisons
$result | Should -BeGreaterThan 10
$result | Should -BeLessThan 100
$result | Should -BeGreaterOrEqual 5

# String matching
$result | Should -Match 'pattern'
$result | Should -MatchExactly 'CaseSensitive'

# Collection assertions
$result | Should -HaveCount 5
$result | Should -Contain 'item'

# Boolean
$result | Should -BeTrue
$result | Should -BeFalse

# Exception testing
{ FunctionName } | Should -Throw
{ FunctionName } | Should -Throw -ExceptionType ([ArgumentException])
{ FunctionName } | Should -Not -Throw
```

## Mocking

### Basic Mock
```powershell
Mock Get-Something { return 'mocked value' }
```

### Mock with Parameters
```powershell
Mock Get-Something { return 'value' } -ParameterFilter { $Name -eq 'Test' }
```

### Verify Mock Called
```powershell
Mock Get-Something { }

# Test code that should call Get-Something

Should -Invoke Get-Something -Times 1
Should -Invoke Get-Something -Times 1 -ParameterFilter { $Name -eq 'Test' }
```

## Test Data Helpers

### Create Test Objects
```powershell
# Simple object
$testObj = [PSCustomObject]@{
    Property1 = 'value1'
    Property2 = 'value2'
}

# With type name
$testObj.PSObject.TypeNames.Insert(0, 'CustomType')

# Mock with method
$mockObj = [PSCustomObject]@{} | Add-Member -MemberType ScriptMethod -Name MethodName -Value {
    param($param1)
    return 'result'
} -PassThru
```

## Debugging Failed Tests

### Get Detailed Output
```powershell
Invoke-Pester -Path .\Tests\TestFile.Tests.ps1 -Output Detailed
```

### Show Error Details
```powershell
$config = New-PesterConfiguration
$config.Run.Path = '.\Tests\TestFile.Tests.ps1'
$config.Output.Verbosity = 'Diagnostic'
$result = Invoke-Pester -Configuration $config

# Show error details
$result.Failed | ForEach-Object {
    Write-Host $_.ErrorRecord.Exception.Message -ForegroundColor Red
    Write-Host $_.ErrorRecord.ScriptStackTrace -ForegroundColor Yellow
}
```

### Interactive Debugging
```powershell
# Add breakpoint in test
It 'Should do something' {
    $result = FunctionName
    Wait-Debugger  # Breaks here
    $result | Should -Be $expected
}
```

## Performance Testing

### Measure Test Execution Time
```powershell
$result = Invoke-Pester -Path .\Tests\ -PassThru
Write-Host "Total time: $($result.Duration.TotalSeconds)s"
```

### Find Slow Tests
```powershell
$result = Invoke-Pester -Path .\Tests\ -PassThru
$result.Tests | 
    Where-Object { $_.Duration.TotalSeconds -gt 1 } |
    Sort-Object -Property Duration -Descending |
    Select-Object Name, Duration
```

## Code Coverage Analysis

### Basic Coverage
```powershell
$config = New-PesterConfiguration
$config.CodeCoverage.Enabled = $true
$config.CodeCoverage.Path = '.\SqlSizer-MSSQL\Shared\*.ps1'
$result = Invoke-Pester -Configuration $config

Write-Host "Coverage: $($result.CodeCoverage.CoveragePercent)%"
```

### Find Uncovered Lines
```powershell
$result.CodeCoverage.MissedCommands | 
    Select-Object File, Line, Command |
    Format-Table -AutoSize
```

## CI/CD Integration

### GitHub Actions
```yaml
- name: Run tests
  run: |
    $config = New-PesterConfiguration
    $config.Run.Path = './Tests/'
    $config.TestResult.Enabled = $true
    $config.TestResult.OutputPath = './testResults.xml'
    Invoke-Pester -Configuration $config
```

### Azure DevOps
```yaml
- task: PowerShell@2
  inputs:
    targetType: 'inline'
    script: |
      Install-Module Pester -Force
      Invoke-Pester -Path ./Tests/ -OutputFile testResults.xml -OutputFormat NUnitXml
      
- task: PublishTestResults@2
  inputs:
    testResultsFormat: 'NUnit'
    testResultsFiles: '**/testResults.xml'
```

## Troubleshooting

### "Module not found"
```powershell
# Ensure module is in path
$env:PSModulePath -split ';'

# Or import explicitly
Import-Module .\SqlSizer-MSSQL\SqlSizer-MSSQL.psd1 -Force
```

### "Type not found"
```powershell
# Load types before running tests
. .\SqlSizer-MSSQL\Types\TypeDefinitions.ps1
```

### "Mock not working"
```powershell
# Ensure using Pester 5+ syntax
Get-Module Pester | Select-Object Version

# Update Pester
Install-Module Pester -Force -SkipPublisherCheck
```

## Best Practices

1. ✅ **One assertion per test** - tests should be focused
2. ✅ **Descriptive names** - "Should return X when Y"
3. ✅ **Arrange-Act-Assert** - clear test structure
4. ✅ **Independent tests** - no dependencies between tests
5. ✅ **Fast tests** - avoid slow operations in unit tests
6. ✅ **Clean up** - use AfterEach/AfterAll to clean up
7. ✅ **Test edge cases** - null, empty, boundary values
8. ✅ **Use tags** - separate unit/integration tests

## Resources

- [Pester Documentation](https://pester.dev/)
- [Pester Best Practices](https://pester.dev/docs/usage/best-practices)
- [PowerShell Testing Best Practices](https://github.com/PoshCode/PowerShellPracticeAndStyle)

## Quick Commands Summary

```powershell
# Run all tests
.\Tests\Run-Tests.ps1

# Run with coverage
.\Tests\Run-Tests.ps1 -CodeCoverage

# Run specific test
Invoke-Pester -Path .\Tests\TraversalHelpers.Tests.ps1

# Run by name
Invoke-Pester -Path .\Tests\ -TestName "*Get-NewTraversalState*"

# Run by tag
Invoke-Pester -Path .\Tests\ -Tag Unit

# Debug mode
Invoke-Pester -Path .\Tests\ -Output Diagnostic

# Generate reports
$config = New-PesterConfiguration
$config.TestResult.Enabled = $true
$config.CodeCoverage.Enabled = $true
Invoke-Pester -Configuration $config
```
