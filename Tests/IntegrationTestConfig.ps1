<#
.SYNOPSIS
    Configuration and scaling logic for Find-Subset integration tests.
    
.DESCRIPTION
    Defines data size presets and calculates scaled row counts for test data generation.
#>

# Size preset multipliers (base = Small = 1.0)
$script:SizeMultipliers = @{
    'Tiny'   = 0.1
    'Small'  = 1.0
    'Medium' = 10.0
    'Large'  = 50.0
    'XLarge' = 250.0
}

# Base row counts for Small preset (~2,000 total rows)
$script:BaseRowCounts = @{
    # Core Business Entities
    Categories           = 10
    SubCategories        = 20
    Products             = 50
    ProductVariants      = 150
    Suppliers            = 10
    ProductSuppliers     = 100
    Warehouses           = 5
    Inventory            = 200
    
    # Organization & HR
    Employees            = 30
    Departments          = 8
    JobTitles            = 10
    EmployeeJobHistory   = 50
    Teams                = 6
    TeamMembers          = 40
    EmployeeSkills       = 60
    Skills               = 15
    
    # Customer & Sales
    Contacts             = 50
    Customers            = 25
    CustomerAddresses    = 60
    Orders               = 100
    OrderDetails         = 300
    OrderNotes           = 30
    Invoices             = 80
    Payments             = 100
    
    # Content & Documents
    Documents            = 40
    DocumentVersions     = 80
    Comments             = 60
    Attachments          = 50
    Tags                 = 15
    
    # Junction Tables
    ProductTags          = 80
    DocumentTags         = 50
    CustomerTags         = 40
    EmployeeCertifications = 40
    
    # Metadata & System
    AuditLog             = 100
    Settings             = 20
    Certifications       = 15
    Organizations        = 20
    
    # Stress Test Tables
    WideTable            = 20
    DeepChainA           = 5
    DeepChainB           = 5
    DeepChainC           = 5
    DeepChainD           = 5
    DeepChainE           = 5
    DeepChainF           = 5
    DeepChainG           = 5
    DeepChainH           = 5
    HighFanoutParent     = 2
    HighFanoutChildren   = 200
    
    # Multi-Tenant
    Tenants              = 3
    TenantProducts       = 75
}

# Scaling behavior per table type
$script:ScalingBehavior = @{
    # Reference tables scale slowly (sqrt)
    SlowGrowth = @('Categories', 'JobTitles', 'Tags', 'Skills', 'Certifications', 
                   'Departments', 'Warehouses', 'Settings', 'Tenants')
    
    # Main entities scale linearly
    Linear = @('Products', 'Employees', 'Customers', 'Orders', 'Documents', 
               'Contacts', 'Suppliers', 'Organizations')
    
    # Child/detail tables scale faster (1.5x parent rate)
    FastGrowth = @('ProductVariants', 'OrderDetails', 'DocumentVersions', 
                   'CustomerAddresses', 'Comments', 'Attachments', 'Payments')
    
    # Junction tables scale at higher rate
    Junction = @('ProductSuppliers', 'TeamMembers', 'EmployeeSkills', 
                 'ProductTags', 'DocumentTags', 'CustomerTags', 
                 'EmployeeCertifications', 'TenantProducts')
    
    # Stress tables have special scaling
    Stress = @('HighFanoutChildren', 'WideTable')
}

function Get-ScaledRowCounts {
    <#
    .SYNOPSIS
        Calculates row counts for each table based on data size preset.
    
    .PARAMETER DataSize
        Size preset: Tiny, Small, Medium, Large, XLarge, or Custom.
    
    .PARAMETER CustomRowCount
        Target total row count when DataSize is Custom.
    
    .OUTPUTS
        Hashtable with table names as keys and row counts as values.
    #>
    param(
        [ValidateSet('Tiny', 'Small', 'Medium', 'Large', 'XLarge', 'Custom')]
        [string]$DataSize = 'Small',
        
        [ValidateRange(100, 1000000)]
        [int]$CustomRowCount = 5000
    )
    
    # Calculate base multiplier
    if ($DataSize -eq 'Custom') {
        $baseTotal = ($script:BaseRowCounts.Values | Measure-Object -Sum).Sum
        $multiplier = $CustomRowCount / $baseTotal
    }
    else {
        $multiplier = $script:SizeMultipliers[$DataSize]
    }
    
    $scaledCounts = @{}
    
    foreach ($table in $script:BaseRowCounts.Keys) {
        $baseCount = $script:BaseRowCounts[$table]
        
        # Apply scaling based on table type
        if ($table -in $script:ScalingBehavior.SlowGrowth) {
            # Slow growth: sqrt scaling
            $scaled = [int]($baseCount * [Math]::Sqrt($multiplier))
        }
        elseif ($table -in $script:ScalingBehavior.FastGrowth) {
            # Fast growth: 1.2x linear
            $scaled = [int]($baseCount * $multiplier * 1.2)
        }
        elseif ($table -in $script:ScalingBehavior.Junction) {
            # Junction: 1.5x linear
            $scaled = [int]($baseCount * $multiplier * 1.5)
        }
        elseif ($table -in $script:ScalingBehavior.Stress) {
            # Stress tables: quadratic for extreme testing
            $scaled = [int]($baseCount * $multiplier * $multiplier * 0.1)
            $scaled = [Math]::Max($scaled, $baseCount)  # Don't go below base
        }
        else {
            # Linear scaling (default)
            $scaled = [int]($baseCount * $multiplier)
        }
        
        # Enforce minimums to ensure tests work
        $minimum = Get-MinimumRowCount -TableName $table
        $scaledCounts[$table] = [Math]::Max($scaled, $minimum)
    }
    
    return $scaledCounts
}

function Get-MinimumRowCount {
    <#
    .SYNOPSIS
        Returns minimum row count for a table to ensure tests work.
    #>
    param([string]$TableName)
    
    $minimums = @{
        Categories       = 3
        SubCategories    = 3
        Products         = 5
        ProductVariants  = 5
        Suppliers        = 2
        Employees        = 8   # Need for 5-level hierarchy
        Departments      = 2
        Customers        = 3
        Orders           = 5
        OrderDetails     = 10
        Contacts         = 5
        Documents        = 5
        Tags             = 3
        DeepChainA       = 2
        DeepChainB       = 2
        DeepChainC       = 2
        DeepChainD       = 2
        DeepChainE       = 2
        DeepChainF       = 2
        DeepChainG       = 2
        DeepChainH       = 2
        HighFanoutParent = 1
        HighFanoutChildren = 10
    }
    
    if ($minimums.ContainsKey($TableName)) {
        return $minimums[$TableName]
    }
    return 1
}

function Get-EstimatedRowCount {
    <#
    .SYNOPSIS
        Returns estimated total row count for a data size preset.
    #>
    param(
        [ValidateSet('Tiny', 'Small', 'Medium', 'Large', 'XLarge', 'Custom')]
        [string]$DataSize = 'Small',
        
        [int]$CustomRowCount = 5000
    )
    
    $counts = Get-ScaledRowCounts -DataSize $DataSize -CustomRowCount $CustomRowCount
    return ($counts.Values | Measure-Object -Sum).Sum
}

function Get-EstimatedRuntime {
    <#
    .SYNOPSIS
        Returns estimated test runtime based on data size.
    #>
    param(
        [ValidateSet('Tiny', 'Small', 'Medium', 'Large', 'XLarge', 'Custom')]
        [string]$DataSize = 'Small'
    )
    
    $runtimes = @{
        'Tiny'   = '30 seconds'
        'Small'  = '1-2 minutes'
        'Medium' = '5-10 minutes'
        'Large'  = '15-30 minutes'
        'XLarge' = '45-90 minutes'
        'Custom' = 'Varies'
    }
    
    return $runtimes[$DataSize]
}
