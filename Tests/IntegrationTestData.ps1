<#
.SYNOPSIS
    Database schema and test data for Find-Subset integration tests.
    
.DESCRIPTION
    Creates 32+ tables with diverse FK patterns and seeds scalable test data.
#>

function Get-SchemaCreationSql {
    <#
    .SYNOPSIS
        Returns SQL to create the test database schema.
    #>
    return @"
-- =====================================================
-- Core Business Entities
-- =====================================================

-- Categories (hierarchical with self-reference)
IF OBJECT_ID('dbo.Categories', 'U') IS NULL
CREATE TABLE dbo.Categories (
    CategoryId INT IDENTITY(1,1) PRIMARY KEY,
    Name NVARCHAR(100) NOT NULL,
    ParentCategoryId INT NULL,
    CONSTRAINT FK_Categories_Parent FOREIGN KEY (ParentCategoryId) REFERENCES dbo.Categories(CategoryId)
);

-- SubCategories
IF OBJECT_ID('dbo.SubCategories', 'U') IS NULL
CREATE TABLE dbo.SubCategories (
    SubCategoryId INT IDENTITY(1,1) PRIMARY KEY,
    Name NVARCHAR(100) NOT NULL,
    CategoryId INT NOT NULL,
    CONSTRAINT FK_SubCategories_Category FOREIGN KEY (CategoryId) REFERENCES dbo.Categories(CategoryId)
);

-- Suppliers (will reference Contacts after Contacts is created)
IF OBJECT_ID('dbo.Suppliers', 'U') IS NULL
CREATE TABLE dbo.Suppliers (
    SupplierId INT IDENTITY(1,1) PRIMARY KEY,
    Name NVARCHAR(100) NOT NULL,
    PrimaryContactId INT NULL
);

-- Products
IF OBJECT_ID('dbo.Products', 'U') IS NULL
CREATE TABLE dbo.Products (
    ProductId INT IDENTITY(1,1) PRIMARY KEY,
    Name NVARCHAR(100) NOT NULL,
    SubCategoryId INT NOT NULL,
    PrimarySupplierId INT NULL,
    CONSTRAINT FK_Products_SubCategory FOREIGN KEY (SubCategoryId) REFERENCES dbo.SubCategories(SubCategoryId),
    CONSTRAINT FK_Products_Supplier FOREIGN KEY (PrimarySupplierId) REFERENCES dbo.Suppliers(SupplierId)
);

-- ProductVariants
IF OBJECT_ID('dbo.ProductVariants', 'U') IS NULL
CREATE TABLE dbo.ProductVariants (
    VariantId INT IDENTITY(1,1) PRIMARY KEY,
    ProductId INT NOT NULL,
    SKU NVARCHAR(50) NOT NULL,
    Size NVARCHAR(20) NULL,
    Color NVARCHAR(30) NULL,
    CONSTRAINT FK_ProductVariants_Product FOREIGN KEY (ProductId) REFERENCES dbo.Products(ProductId)
);

-- ProductSuppliers (many-to-many junction)
IF OBJECT_ID('dbo.ProductSuppliers', 'U') IS NULL
CREATE TABLE dbo.ProductSuppliers (
    ProductId INT NOT NULL,
    SupplierId INT NOT NULL,
    IsPreferred BIT DEFAULT 0,
    CONSTRAINT PK_ProductSuppliers PRIMARY KEY (ProductId, SupplierId),
    CONSTRAINT FK_ProductSuppliers_Product FOREIGN KEY (ProductId) REFERENCES dbo.Products(ProductId),
    CONSTRAINT FK_ProductSuppliers_Supplier FOREIGN KEY (SupplierId) REFERENCES dbo.Suppliers(SupplierId)
);

-- =====================================================
-- Organization & HR
-- =====================================================

-- Departments (will have circular ref with Employees)
IF OBJECT_ID('dbo.Departments', 'U') IS NULL
CREATE TABLE dbo.Departments (
    DeptId INT IDENTITY(1,1) PRIMARY KEY,
    Name NVARCHAR(100) NOT NULL,
    ParentDeptId INT NULL,
    HeadId INT NULL,
    CONSTRAINT FK_Departments_Parent FOREIGN KEY (ParentDeptId) REFERENCES dbo.Departments(DeptId)
);

-- Employees (self-ref + circular with Departments)
IF OBJECT_ID('dbo.Employees', 'U') IS NULL
CREATE TABLE dbo.Employees (
    EmployeeId INT IDENTITY(1,1) PRIMARY KEY,
    FirstName NVARCHAR(50) NOT NULL,
    LastName NVARCHAR(50) NOT NULL,
    ManagerId INT NULL,
    DeptId INT NULL,
    HiredById INT NULL,
    CONSTRAINT FK_Employees_Manager FOREIGN KEY (ManagerId) REFERENCES dbo.Employees(EmployeeId),
    CONSTRAINT FK_Employees_Dept FOREIGN KEY (DeptId) REFERENCES dbo.Departments(DeptId),
    CONSTRAINT FK_Employees_HiredBy FOREIGN KEY (HiredById) REFERENCES dbo.Employees(EmployeeId)
);

-- Add circular FK from Departments to Employees
IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = 'FK_Departments_Head')
ALTER TABLE dbo.Departments ADD CONSTRAINT FK_Departments_Head FOREIGN KEY (HeadId) REFERENCES dbo.Employees(EmployeeId);

-- Warehouses
IF OBJECT_ID('dbo.Warehouses', 'U') IS NULL
CREATE TABLE dbo.Warehouses (
    WarehouseId INT IDENTITY(1,1) PRIMARY KEY,
    Name NVARCHAR(100) NOT NULL,
    ManagerId INT NULL,
    CONSTRAINT FK_Warehouses_Manager FOREIGN KEY (ManagerId) REFERENCES dbo.Employees(EmployeeId)
);

-- Inventory (composite key)
IF OBJECT_ID('dbo.Inventory', 'U') IS NULL
CREATE TABLE dbo.Inventory (
    WarehouseId INT NOT NULL,
    ProductVariantId INT NOT NULL,
    Quantity INT NOT NULL DEFAULT 0,
    CONSTRAINT PK_Inventory PRIMARY KEY (WarehouseId, ProductVariantId),
    CONSTRAINT FK_Inventory_Warehouse FOREIGN KEY (WarehouseId) REFERENCES dbo.Warehouses(WarehouseId),
    CONSTRAINT FK_Inventory_Variant FOREIGN KEY (ProductVariantId) REFERENCES dbo.ProductVariants(VariantId)
);

-- JobTitles (reference table)
IF OBJECT_ID('dbo.JobTitles', 'U') IS NULL
CREATE TABLE dbo.JobTitles (
    JobTitleId INT IDENTITY(1,1) PRIMARY KEY,
    Name NVARCHAR(100) NOT NULL
);

-- EmployeeJobHistory
IF OBJECT_ID('dbo.EmployeeJobHistory', 'U') IS NULL
CREATE TABLE dbo.EmployeeJobHistory (
    HistoryId INT IDENTITY(1,1) PRIMARY KEY,
    EmployeeId INT NOT NULL,
    JobTitleId INT NOT NULL,
    DeptId INT NOT NULL,
    StartDate DATE NOT NULL,
    EndDate DATE NULL,
    CONSTRAINT FK_JobHistory_Employee FOREIGN KEY (EmployeeId) REFERENCES dbo.Employees(EmployeeId),
    CONSTRAINT FK_JobHistory_Title FOREIGN KEY (JobTitleId) REFERENCES dbo.JobTitles(JobTitleId),
    CONSTRAINT FK_JobHistory_Dept FOREIGN KEY (DeptId) REFERENCES dbo.Departments(DeptId)
);

-- Skills (reference table)
IF OBJECT_ID('dbo.Skills', 'U') IS NULL
CREATE TABLE dbo.Skills (
    SkillId INT IDENTITY(1,1) PRIMARY KEY,
    Name NVARCHAR(100) NOT NULL
);

-- EmployeeSkills (junction with composite key)
IF OBJECT_ID('dbo.EmployeeSkills', 'U') IS NULL
CREATE TABLE dbo.EmployeeSkills (
    EmployeeId INT NOT NULL,
    SkillId INT NOT NULL,
    Proficiency TINYINT DEFAULT 1,
    CONSTRAINT PK_EmployeeSkills PRIMARY KEY (EmployeeId, SkillId),
    CONSTRAINT FK_EmpSkills_Employee FOREIGN KEY (EmployeeId) REFERENCES dbo.Employees(EmployeeId),
    CONSTRAINT FK_EmpSkills_Skill FOREIGN KEY (SkillId) REFERENCES dbo.Skills(SkillId)
);

-- Teams
IF OBJECT_ID('dbo.Teams', 'U') IS NULL
CREATE TABLE dbo.Teams (
    TeamId INT IDENTITY(1,1) PRIMARY KEY,
    Name NVARCHAR(100) NOT NULL,
    LeaderId INT NOT NULL,
    DeptId INT NOT NULL,
    CONSTRAINT FK_Teams_Leader FOREIGN KEY (LeaderId) REFERENCES dbo.Employees(EmployeeId),
    CONSTRAINT FK_Teams_Dept FOREIGN KEY (DeptId) REFERENCES dbo.Departments(DeptId)
);

-- TeamMembers (junction)
IF OBJECT_ID('dbo.TeamMembers', 'U') IS NULL
CREATE TABLE dbo.TeamMembers (
    TeamId INT NOT NULL,
    EmployeeId INT NOT NULL,
    JoinedDate DATE NOT NULL DEFAULT GETDATE(),
    CONSTRAINT PK_TeamMembers PRIMARY KEY (TeamId, EmployeeId),
    CONSTRAINT FK_TeamMembers_Team FOREIGN KEY (TeamId) REFERENCES dbo.Teams(TeamId),
    CONSTRAINT FK_TeamMembers_Employee FOREIGN KEY (EmployeeId) REFERENCES dbo.Employees(EmployeeId)
);

-- =====================================================
-- Customer & Sales
-- =====================================================

-- Contacts (shared entity for diamond pattern)
IF OBJECT_ID('dbo.Contacts', 'U') IS NULL
CREATE TABLE dbo.Contacts (
    ContactId INT IDENTITY(1,1) PRIMARY KEY,
    Email NVARCHAR(255) NOT NULL,
    Phone NVARCHAR(20) NULL,
    FirstName NVARCHAR(50) NULL,
    LastName NVARCHAR(50) NULL
);

-- Add FK from Suppliers to Contacts
IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = 'FK_Suppliers_Contact')
ALTER TABLE dbo.Suppliers ADD CONSTRAINT FK_Suppliers_Contact FOREIGN KEY (PrimaryContactId) REFERENCES dbo.Contacts(ContactId);

-- Customers (diamond pattern: 3 FKs to Contacts)
IF OBJECT_ID('dbo.Customers', 'U') IS NULL
CREATE TABLE dbo.Customers (
    CustomerId INT IDENTITY(1,1) PRIMARY KEY,
    Name NVARCHAR(100) NOT NULL,
    PrimaryContactId INT NOT NULL,
    BillingContactId INT NULL,
    ShippingContactId INT NULL,
    AccountManagerId INT NULL,
    CONSTRAINT FK_Customers_PrimaryContact FOREIGN KEY (PrimaryContactId) REFERENCES dbo.Contacts(ContactId),
    CONSTRAINT FK_Customers_BillingContact FOREIGN KEY (BillingContactId) REFERENCES dbo.Contacts(ContactId),
    CONSTRAINT FK_Customers_ShippingContact FOREIGN KEY (ShippingContactId) REFERENCES dbo.Contacts(ContactId),
    CONSTRAINT FK_Customers_AccountManager FOREIGN KEY (AccountManagerId) REFERENCES dbo.Employees(EmployeeId)
);

-- CustomerAddresses
IF OBJECT_ID('dbo.CustomerAddresses', 'U') IS NULL
CREATE TABLE dbo.CustomerAddresses (
    AddressId INT IDENTITY(1,1) PRIMARY KEY,
    CustomerId INT NOT NULL,
    AddressType NVARCHAR(20) NOT NULL,
    Street NVARCHAR(200) NOT NULL,
    City NVARCHAR(100) NOT NULL,
    CONSTRAINT FK_CustAddr_Customer FOREIGN KEY (CustomerId) REFERENCES dbo.Customers(CustomerId)
);

-- Orders (multiple FKs)
IF OBJECT_ID('dbo.Orders', 'U') IS NULL
CREATE TABLE dbo.Orders (
    OrderId INT IDENTITY(1,1) PRIMARY KEY,
    CustomerId INT NOT NULL,
    SalesRepId INT NULL,
    ShippingAddressId INT NULL,
    BillingAddressId INT NULL,
    OrderDate DATE NOT NULL DEFAULT GETDATE(),
    TotalAmount DECIMAL(18,2) NULL,
    CONSTRAINT FK_Orders_Customer FOREIGN KEY (CustomerId) REFERENCES dbo.Customers(CustomerId),
    CONSTRAINT FK_Orders_SalesRep FOREIGN KEY (SalesRepId) REFERENCES dbo.Employees(EmployeeId),
    CONSTRAINT FK_Orders_ShippingAddr FOREIGN KEY (ShippingAddressId) REFERENCES dbo.CustomerAddresses(AddressId),
    CONSTRAINT FK_Orders_BillingAddr FOREIGN KEY (BillingAddressId) REFERENCES dbo.CustomerAddresses(AddressId)
);

-- OrderDetails (composite key)
IF OBJECT_ID('dbo.OrderDetails', 'U') IS NULL
CREATE TABLE dbo.OrderDetails (
    OrderId INT NOT NULL,
    LineNum INT NOT NULL,
    ProductVariantId INT NOT NULL,
    Quantity INT NOT NULL,
    UnitPrice DECIMAL(18,2) NOT NULL,
    CONSTRAINT PK_OrderDetails PRIMARY KEY (OrderId, LineNum),
    CONSTRAINT FK_OrderDetails_Order FOREIGN KEY (OrderId) REFERENCES dbo.Orders(OrderId),
    CONSTRAINT FK_OrderDetails_Variant FOREIGN KEY (ProductVariantId) REFERENCES dbo.ProductVariants(VariantId)
);

-- OrderNotes (nullable FK)
IF OBJECT_ID('dbo.OrderNotes', 'U') IS NULL
CREATE TABLE dbo.OrderNotes (
    NoteId INT IDENTITY(1,1) PRIMARY KEY,
    OrderId INT NULL,
    NoteText NVARCHAR(MAX) NOT NULL,
    CreatedById INT NULL,
    CreatedDate DATETIME NOT NULL DEFAULT GETDATE(),
    CONSTRAINT FK_OrderNotes_Order FOREIGN KEY (OrderId) REFERENCES dbo.Orders(OrderId),
    CONSTRAINT FK_OrderNotes_CreatedBy FOREIGN KEY (CreatedById) REFERENCES dbo.Employees(EmployeeId)
);

-- Invoices
IF OBJECT_ID('dbo.Invoices', 'U') IS NULL
CREATE TABLE dbo.Invoices (
    InvoiceId INT IDENTITY(1,1) PRIMARY KEY,
    OrderId INT NOT NULL,
    BillingAddressId INT NULL,
    InvoiceDate DATE NOT NULL DEFAULT GETDATE(),
    DueDate DATE NULL,
    CONSTRAINT FK_Invoices_Order FOREIGN KEY (OrderId) REFERENCES dbo.Orders(OrderId),
    CONSTRAINT FK_Invoices_BillingAddr FOREIGN KEY (BillingAddressId) REFERENCES dbo.CustomerAddresses(AddressId)
);

-- Payments
IF OBJECT_ID('dbo.Payments', 'U') IS NULL
CREATE TABLE dbo.Payments (
    PaymentId INT IDENTITY(1,1) PRIMARY KEY,
    InvoiceId INT NOT NULL,
    ProcessedById INT NULL,
    Amount DECIMAL(18,2) NOT NULL,
    PaymentDate DATE NOT NULL DEFAULT GETDATE(),
    CONSTRAINT FK_Payments_Invoice FOREIGN KEY (InvoiceId) REFERENCES dbo.Invoices(InvoiceId),
    CONSTRAINT FK_Payments_ProcessedBy FOREIGN KEY (ProcessedById) REFERENCES dbo.Employees(EmployeeId)
);

-- =====================================================
-- Content & Documents
-- =====================================================

-- Documents (hierarchical)
IF OBJECT_ID('dbo.Documents', 'U') IS NULL
CREATE TABLE dbo.Documents (
    DocumentId INT IDENTITY(1,1) PRIMARY KEY,
    Title NVARCHAR(200) NOT NULL,
    OwnerId INT NOT NULL,
    ParentDocId INT NULL,
    CreatedDate DATETIME NOT NULL DEFAULT GETDATE(),
    CONSTRAINT FK_Documents_Owner FOREIGN KEY (OwnerId) REFERENCES dbo.Employees(EmployeeId),
    CONSTRAINT FK_Documents_Parent FOREIGN KEY (ParentDocId) REFERENCES dbo.Documents(DocumentId)
);

-- DocumentVersions
IF OBJECT_ID('dbo.DocumentVersions', 'U') IS NULL
CREATE TABLE dbo.DocumentVersions (
    VersionId INT IDENTITY(1,1) PRIMARY KEY,
    DocumentId INT NOT NULL,
    VersionNum INT NOT NULL,
    CreatedById INT NOT NULL,
    CreatedDate DATETIME NOT NULL DEFAULT GETDATE(),
    CONSTRAINT FK_DocVersions_Document FOREIGN KEY (DocumentId) REFERENCES dbo.Documents(DocumentId),
    CONSTRAINT FK_DocVersions_CreatedBy FOREIGN KEY (CreatedById) REFERENCES dbo.Employees(EmployeeId)
);

-- Comments (threaded with self-ref)
IF OBJECT_ID('dbo.Comments', 'U') IS NULL
CREATE TABLE dbo.Comments (
    CommentId INT IDENTITY(1,1) PRIMARY KEY,
    ParentCommentId INT NULL,
    AuthorId INT NOT NULL,
    EntityType NVARCHAR(50) NOT NULL,
    EntityId INT NOT NULL,
    CommentText NVARCHAR(MAX) NOT NULL,
    CreatedDate DATETIME NOT NULL DEFAULT GETDATE(),
    CONSTRAINT FK_Comments_Parent FOREIGN KEY (ParentCommentId) REFERENCES dbo.Comments(CommentId),
    CONSTRAINT FK_Comments_Author FOREIGN KEY (AuthorId) REFERENCES dbo.Employees(EmployeeId)
);

-- Attachments (polymorphic)
IF OBJECT_ID('dbo.Attachments', 'U') IS NULL
CREATE TABLE dbo.Attachments (
    AttachmentId INT IDENTITY(1,1) PRIMARY KEY,
    EntityType NVARCHAR(50) NOT NULL,
    EntityId INT NOT NULL,
    FileName NVARCHAR(255) NOT NULL,
    UploadedById INT NOT NULL,
    UploadedDate DATETIME NOT NULL DEFAULT GETDATE(),
    CONSTRAINT FK_Attachments_UploadedBy FOREIGN KEY (UploadedById) REFERENCES dbo.Employees(EmployeeId)
);

-- Tags
IF OBJECT_ID('dbo.Tags', 'U') IS NULL
CREATE TABLE dbo.Tags (
    TagId INT IDENTITY(1,1) PRIMARY KEY,
    Name NVARCHAR(50) NOT NULL UNIQUE
);

-- ProductTags (junction)
IF OBJECT_ID('dbo.ProductTags', 'U') IS NULL
CREATE TABLE dbo.ProductTags (
    ProductId INT NOT NULL,
    TagId INT NOT NULL,
    CONSTRAINT PK_ProductTags PRIMARY KEY (ProductId, TagId),
    CONSTRAINT FK_ProductTags_Product FOREIGN KEY (ProductId) REFERENCES dbo.Products(ProductId),
    CONSTRAINT FK_ProductTags_Tag FOREIGN KEY (TagId) REFERENCES dbo.Tags(TagId)
);

-- DocumentTags (junction)
IF OBJECT_ID('dbo.DocumentTags', 'U') IS NULL
CREATE TABLE dbo.DocumentTags (
    DocumentId INT NOT NULL,
    TagId INT NOT NULL,
    CONSTRAINT PK_DocumentTags PRIMARY KEY (DocumentId, TagId),
    CONSTRAINT FK_DocumentTags_Document FOREIGN KEY (DocumentId) REFERENCES dbo.Documents(DocumentId),
    CONSTRAINT FK_DocumentTags_Tag FOREIGN KEY (TagId) REFERENCES dbo.Tags(TagId)
);

-- CustomerTags (junction)
IF OBJECT_ID('dbo.CustomerTags', 'U') IS NULL
CREATE TABLE dbo.CustomerTags (
    CustomerId INT NOT NULL,
    TagId INT NOT NULL,
    CONSTRAINT PK_CustomerTags PRIMARY KEY (CustomerId, TagId),
    CONSTRAINT FK_CustomerTags_Customer FOREIGN KEY (CustomerId) REFERENCES dbo.Customers(CustomerId),
    CONSTRAINT FK_CustomerTags_Tag FOREIGN KEY (TagId) REFERENCES dbo.Tags(TagId)
);

-- =====================================================
-- Metadata & System
-- =====================================================

-- Organizations (external, hierarchical)
IF OBJECT_ID('dbo.Organizations', 'U') IS NULL
CREATE TABLE dbo.Organizations (
    OrgId INT IDENTITY(1,1) PRIMARY KEY,
    Name NVARCHAR(100) NOT NULL,
    ParentOrgId INT NULL,
    PrimaryContactId INT NULL,
    CONSTRAINT FK_Orgs_Parent FOREIGN KEY (ParentOrgId) REFERENCES dbo.Organizations(OrgId),
    CONSTRAINT FK_Orgs_Contact FOREIGN KEY (PrimaryContactId) REFERENCES dbo.Contacts(ContactId)
);

-- Certifications
IF OBJECT_ID('dbo.Certifications', 'U') IS NULL
CREATE TABLE dbo.Certifications (
    CertificationId INT IDENTITY(1,1) PRIMARY KEY,
    Name NVARCHAR(100) NOT NULL,
    IssuingBodyId INT NULL,
    CONSTRAINT FK_Certs_IssuingBody FOREIGN KEY (IssuingBodyId) REFERENCES dbo.Organizations(OrgId)
);

-- EmployeeCertifications (3-column composite key)
IF OBJECT_ID('dbo.EmployeeCertifications', 'U') IS NULL
CREATE TABLE dbo.EmployeeCertifications (
    EmployeeId INT NOT NULL,
    CertificationId INT NOT NULL,
    DateEarned DATE NOT NULL,
    ExpirationDate DATE NULL,
    CONSTRAINT PK_EmpCerts PRIMARY KEY (EmployeeId, CertificationId, DateEarned),
    CONSTRAINT FK_EmpCerts_Employee FOREIGN KEY (EmployeeId) REFERENCES dbo.Employees(EmployeeId),
    CONSTRAINT FK_EmpCerts_Cert FOREIGN KEY (CertificationId) REFERENCES dbo.Certifications(CertificationId)
);

-- AuditLog (for ignored table testing)
IF OBJECT_ID('dbo.AuditLog', 'U') IS NULL
CREATE TABLE dbo.AuditLog (
    LogId INT IDENTITY(1,1) PRIMARY KEY,
    TableName NVARCHAR(100) NOT NULL,
    RecordId INT NOT NULL,
    Action NVARCHAR(20) NOT NULL,
    UserId INT NULL,
    ActionDate DATETIME NOT NULL DEFAULT GETDATE(),
    CONSTRAINT FK_AuditLog_User FOREIGN KEY (UserId) REFERENCES dbo.Employees(EmployeeId)
);

-- Settings (orphan table - no FKs)
IF OBJECT_ID('dbo.Settings', 'U') IS NULL
CREATE TABLE dbo.Settings (
    SettingId INT IDENTITY(1,1) PRIMARY KEY,
    SettingKey NVARCHAR(100) NOT NULL UNIQUE,
    SettingValue NVARCHAR(MAX) NULL
);

-- =====================================================
-- Multi-Tenant Pattern
-- =====================================================

IF OBJECT_ID('dbo.Tenants', 'U') IS NULL
CREATE TABLE dbo.Tenants (
    TenantId INT IDENTITY(1,1) PRIMARY KEY,
    Name NVARCHAR(100) NOT NULL
);

IF OBJECT_ID('dbo.TenantProducts', 'U') IS NULL
CREATE TABLE dbo.TenantProducts (
    TenantId INT NOT NULL,
    ProductId INT NOT NULL,
    IsActive BIT DEFAULT 1,
    CONSTRAINT PK_TenantProducts PRIMARY KEY (TenantId, ProductId),
    CONSTRAINT FK_TenantProducts_Tenant FOREIGN KEY (TenantId) REFERENCES dbo.Tenants(TenantId),
    CONSTRAINT FK_TenantProducts_Product FOREIGN KEY (ProductId) REFERENCES dbo.Products(ProductId)
);

-- =====================================================
-- Deep Chain Tables (8 levels)
-- =====================================================

IF OBJECT_ID('dbo.DeepChainA', 'U') IS NULL
CREATE TABLE dbo.DeepChainA (
    Id INT IDENTITY(1,1) PRIMARY KEY,
    Name NVARCHAR(50) NOT NULL
);

IF OBJECT_ID('dbo.DeepChainB', 'U') IS NULL
CREATE TABLE dbo.DeepChainB (
    Id INT IDENTITY(1,1) PRIMARY KEY,
    Name NVARCHAR(50) NOT NULL,
    ParentId INT NOT NULL,
    CONSTRAINT FK_ChainB_A FOREIGN KEY (ParentId) REFERENCES dbo.DeepChainA(Id)
);

IF OBJECT_ID('dbo.DeepChainC', 'U') IS NULL
CREATE TABLE dbo.DeepChainC (
    Id INT IDENTITY(1,1) PRIMARY KEY,
    Name NVARCHAR(50) NOT NULL,
    ParentId INT NOT NULL,
    CONSTRAINT FK_ChainC_B FOREIGN KEY (ParentId) REFERENCES dbo.DeepChainB(Id)
);

IF OBJECT_ID('dbo.DeepChainD', 'U') IS NULL
CREATE TABLE dbo.DeepChainD (
    Id INT IDENTITY(1,1) PRIMARY KEY,
    Name NVARCHAR(50) NOT NULL,
    ParentId INT NOT NULL,
    CONSTRAINT FK_ChainD_C FOREIGN KEY (ParentId) REFERENCES dbo.DeepChainC(Id)
);

IF OBJECT_ID('dbo.DeepChainE', 'U') IS NULL
CREATE TABLE dbo.DeepChainE (
    Id INT IDENTITY(1,1) PRIMARY KEY,
    Name NVARCHAR(50) NOT NULL,
    ParentId INT NOT NULL,
    CONSTRAINT FK_ChainE_D FOREIGN KEY (ParentId) REFERENCES dbo.DeepChainD(Id)
);

IF OBJECT_ID('dbo.DeepChainF', 'U') IS NULL
CREATE TABLE dbo.DeepChainF (
    Id INT IDENTITY(1,1) PRIMARY KEY,
    Name NVARCHAR(50) NOT NULL,
    ParentId INT NOT NULL,
    CONSTRAINT FK_ChainF_E FOREIGN KEY (ParentId) REFERENCES dbo.DeepChainE(Id)
);

IF OBJECT_ID('dbo.DeepChainG', 'U') IS NULL
CREATE TABLE dbo.DeepChainG (
    Id INT IDENTITY(1,1) PRIMARY KEY,
    Name NVARCHAR(50) NOT NULL,
    ParentId INT NOT NULL,
    CONSTRAINT FK_ChainG_F FOREIGN KEY (ParentId) REFERENCES dbo.DeepChainF(Id)
);

IF OBJECT_ID('dbo.DeepChainH', 'U') IS NULL
CREATE TABLE dbo.DeepChainH (
    Id INT IDENTITY(1,1) PRIMARY KEY,
    Name NVARCHAR(50) NOT NULL,
    ParentId INT NOT NULL,
    CONSTRAINT FK_ChainH_G FOREIGN KEY (ParentId) REFERENCES dbo.DeepChainG(Id)
);

-- =====================================================
-- High Fanout Tables
-- =====================================================

IF OBJECT_ID('dbo.HighFanoutParent', 'U') IS NULL
CREATE TABLE dbo.HighFanoutParent (
    ParentId INT IDENTITY(1,1) PRIMARY KEY,
    Name NVARCHAR(50) NOT NULL
);

IF OBJECT_ID('dbo.HighFanoutChildren', 'U') IS NULL
CREATE TABLE dbo.HighFanoutChildren (
    ChildId INT IDENTITY(1,1) PRIMARY KEY,
    ParentId INT NOT NULL,
    Name NVARCHAR(50) NOT NULL,
    CONSTRAINT FK_HighFanout_Parent FOREIGN KEY (ParentId) REFERENCES dbo.HighFanoutParent(ParentId)
);

-- =====================================================
-- Wide Table (10 FKs)
-- =====================================================

IF OBJECT_ID('dbo.WideTable', 'U') IS NULL
CREATE TABLE dbo.WideTable (
    Id INT IDENTITY(1,1) PRIMARY KEY,
    Name NVARCHAR(100) NOT NULL,
    CategoryId INT NULL,
    SupplierId INT NULL,
    EmployeeId INT NULL,
    CustomerId INT NULL,
    DeptId INT NULL,
    ContactId INT NULL,
    WarehouseId INT NULL,
    TeamId INT NULL,
    DocumentId INT NULL,
    TagId INT NULL,
    CONSTRAINT FK_Wide_Category FOREIGN KEY (CategoryId) REFERENCES dbo.Categories(CategoryId),
    CONSTRAINT FK_Wide_Supplier FOREIGN KEY (SupplierId) REFERENCES dbo.Suppliers(SupplierId),
    CONSTRAINT FK_Wide_Employee FOREIGN KEY (EmployeeId) REFERENCES dbo.Employees(EmployeeId),
    CONSTRAINT FK_Wide_Customer FOREIGN KEY (CustomerId) REFERENCES dbo.Customers(CustomerId),
    CONSTRAINT FK_Wide_Dept FOREIGN KEY (DeptId) REFERENCES dbo.Departments(DeptId),
    CONSTRAINT FK_Wide_Contact FOREIGN KEY (ContactId) REFERENCES dbo.Contacts(ContactId),
    CONSTRAINT FK_Wide_Warehouse FOREIGN KEY (WarehouseId) REFERENCES dbo.Warehouses(WarehouseId),
    CONSTRAINT FK_Wide_Team FOREIGN KEY (TeamId) REFERENCES dbo.Teams(TeamId),
    CONSTRAINT FK_Wide_Document FOREIGN KEY (DocumentId) REFERENCES dbo.Documents(DocumentId),
    CONSTRAINT FK_Wide_Tag FOREIGN KEY (TagId) REFERENCES dbo.Tags(TagId)
);
"@
}

function New-TestDatabase {
    <#
    .SYNOPSIS
        Creates the test database if it doesn't exist.
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$Database,
        
        [Parameter(Mandatory = $true)]
        $ConnectionInfo
    )
    
    $checkQuery = "SELECT DB_ID('$Database') AS DbId"
    $result = Invoke-SqlcmdEx -Sql $checkQuery -Database 'master' -ConnectionInfo $ConnectionInfo
    
    # Handle both $null and DBNull (which is what SQL Server returns for NULL)
    $dbExists = ($null -ne $result.DbId) -and ($result.DbId -isnot [System.DBNull])
    
    if (-not $dbExists) {
        Write-Host "Creating database $Database..."
        $createQuery = "CREATE DATABASE [$Database]"
        Invoke-SqlcmdEx -Sql $createQuery -Database 'master' -ConnectionInfo $ConnectionInfo
        Start-Sleep -Seconds 2  # Wait for database to be ready
    }
    else {
        Write-Host "Database $Database already exists."
    }
}

function Initialize-TestSchema {
    <#
    .SYNOPSIS
        Creates all test tables (idempotent).
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$Database,
        
        [Parameter(Mandatory = $true)]
        $ConnectionInfo
    )
    
    Write-Host "Creating schema (32 tables)..."
    $schemaSql = Get-SchemaCreationSql
    
    # Split and execute in batches (GO statements)
    $batches = $schemaSql -split '\r?\nGO\r?\n'
    foreach ($batch in $batches) {
        if ($batch.Trim() -ne '') {
            try {
                Invoke-SqlcmdEx -Sql $batch -Database $Database -ConnectionInfo $ConnectionInfo
            }
            catch {
                Write-Warning "Schema batch error: $_"
            }
        }
    }
}

function Clear-TestData {
    <#
    .SYNOPSIS
        Clears all data from test tables (respects FK order).
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$Database,
        
        [Parameter(Mandatory = $true)]
        $ConnectionInfo
    )
    
    Write-Host "Clearing existing data..."
    
    # Delete in reverse dependency order
    $deleteOrder = @(
        'WideTable', 'HighFanoutChildren', 'HighFanoutParent',
        'DeepChainH', 'DeepChainG', 'DeepChainF', 'DeepChainE', 'DeepChainD', 'DeepChainC', 'DeepChainB', 'DeepChainA',
        'TenantProducts', 'Tenants',
        'AuditLog', 'Settings',
        'EmployeeCertifications', 'Certifications', 'Organizations',
        'CustomerTags', 'DocumentTags', 'ProductTags',
        'Attachments', 'Comments', 'DocumentVersions', 'Documents',
        'Payments', 'Invoices', 'OrderNotes', 'OrderDetails', 'Orders',
        'CustomerAddresses', 'Customers',
        'TeamMembers', 'Teams',
        'EmployeeSkills', 'Skills',
        'EmployeeJobHistory', 'JobTitles',
        'Inventory', 'Warehouses',
        'ProductSuppliers', 'ProductVariants', 'Products',
        'SubCategories'
    )
    
    # First, break circular refs
    $breakCircular = @"
UPDATE dbo.Departments SET HeadId = NULL;
UPDATE dbo.Categories SET ParentCategoryId = NULL;
UPDATE dbo.Employees SET ManagerId = NULL, HiredById = NULL, DeptId = NULL;
"@
    try { Invoke-SqlcmdEx -Sql $breakCircular -Database $Database -ConnectionInfo $ConnectionInfo } catch {}
    
    foreach ($table in $deleteOrder) {
        try {
            Invoke-SqlcmdEx -Sql "DELETE FROM dbo.$table" -Database $Database -ConnectionInfo $ConnectionInfo
        }
        catch {
            # Ignore errors for tables that may not exist
        }
    }
    
    # Delete remaining tables (order matters: Suppliers references Contacts)
    $remainingTables = @('Tags', 'Suppliers', 'Contacts', 'Departments', 'Employees', 'Categories')
    foreach ($table in $remainingTables) {
        try {
            Invoke-SqlcmdEx -Sql "DELETE FROM dbo.$table" -Database $Database -ConnectionInfo $ConnectionInfo
        }
        catch {}
    }
    
    # Reseed identity columns so IDs start from 1 again
    # This is required because Invoke-DataSeeding assumes IDs start from 1
    $allTables = $deleteOrder + $remainingTables
    foreach ($table in $allTables) {
        try {
            Invoke-SqlcmdEx -Sql "DBCC CHECKIDENT ('dbo.$table', RESEED, 0)" -Database $Database -ConnectionInfo $ConnectionInfo
        }
        catch {
            # Ignore errors for tables that may not exist or don't have identity columns
        }
    }
}

function Invoke-DataSeeding {
    <#
    .SYNOPSIS
        Seeds test data at the specified scale.
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$Database,
        
        [Parameter(Mandatory = $true)]
        $ConnectionInfo,
        
        [Parameter(Mandatory = $true)]
        [hashtable]$RowCounts
    )
    
    Write-Host "Seeding data..."
    
    # Helper to generate random items
    function Get-RandomItem($array) { $array | Get-Random }
    function Get-RandomItems($array, $count) { $array | Get-Random -Count ([Math]::Min($count, $array.Count)) }
    
    # 1. Categories (hierarchical: 3 levels)
    $catCount = $RowCounts['Categories']
    $level1Count = [Math]::Max(2, [int]($catCount / 3))
    $level2Count = [Math]::Max(2, [int]($catCount / 3))
    $level3Count = $catCount - $level1Count - $level2Count
    
    Write-Host "  Categories: $catCount rows"
    for ($i = 1; $i -le $level1Count; $i++) {
        Invoke-SqlcmdEx -Sql "INSERT INTO dbo.Categories (Name) VALUES ('Category_L1_$i')" -Database $Database -ConnectionInfo $ConnectionInfo
    }
    for ($i = 1; $i -le $level2Count; $i++) {
        $parentId = (($i - 1) % $level1Count) + 1
        Invoke-SqlcmdEx -Sql "INSERT INTO dbo.Categories (Name, ParentCategoryId) VALUES ('Category_L2_$i', $parentId)" -Database $Database -ConnectionInfo $ConnectionInfo
    }
    for ($i = 1; $i -le $level3Count; $i++) {
        $parentId = $level1Count + (($i - 1) % $level2Count) + 1
        Invoke-SqlcmdEx -Sql "INSERT INTO dbo.Categories (Name, ParentCategoryId) VALUES ('Category_L3_$i', $parentId)" -Database $Database -ConnectionInfo $ConnectionInfo
    }
    
    # 2. SubCategories
    $subCatCount = $RowCounts['SubCategories']
    Write-Host "  SubCategories: $subCatCount rows"
    for ($i = 1; $i -le $subCatCount; $i++) {
        $catId = (($i - 1) % $catCount) + 1
        Invoke-SqlcmdEx -Sql "INSERT INTO dbo.SubCategories (Name, CategoryId) VALUES ('SubCat_$i', $catId)" -Database $Database -ConnectionInfo $ConnectionInfo
    }
    
    # 3. Contacts
    $contactCount = $RowCounts['Contacts']
    Write-Host "  Contacts: $contactCount rows"
    for ($i = 1; $i -le $contactCount; $i++) {
        Invoke-SqlcmdEx -Sql "INSERT INTO dbo.Contacts (Email, FirstName, LastName) VALUES ('contact$i@test.com', 'First$i', 'Last$i')" -Database $Database -ConnectionInfo $ConnectionInfo
    }
    
    # 4. Suppliers
    $supplierCount = $RowCounts['Suppliers']
    Write-Host "  Suppliers: $supplierCount rows"
    for ($i = 1; $i -le $supplierCount; $i++) {
        $contactId = (($i - 1) % $contactCount) + 1
        Invoke-SqlcmdEx -Sql "INSERT INTO dbo.Suppliers (Name, PrimaryContactId) VALUES ('Supplier_$i', $contactId)" -Database $Database -ConnectionInfo $ConnectionInfo
    }
    
    # 5. Products
    $productCount = $RowCounts['Products']
    Write-Host "  Products: $productCount rows"
    for ($i = 1; $i -le $productCount; $i++) {
        $subCatId = (($i - 1) % $subCatCount) + 1
        $supplierId = if ($i % 3 -eq 0) { 'NULL' } else { (($i - 1) % $supplierCount) + 1 }
        Invoke-SqlcmdEx -Sql "INSERT INTO dbo.Products (Name, SubCategoryId, PrimarySupplierId) VALUES ('Product_$i', $subCatId, $supplierId)" -Database $Database -ConnectionInfo $ConnectionInfo
    }
    
    # 6. ProductVariants
    $variantCount = $RowCounts['ProductVariants']
    Write-Host "  ProductVariants: $variantCount rows"
    $colors = @('Red', 'Blue', 'Green', 'Black', 'White')
    $sizes = @('S', 'M', 'L', 'XL')
    for ($i = 1; $i -le $variantCount; $i++) {
        $productId = (($i - 1) % $productCount) + 1
        $color = $colors[$i % $colors.Count]
        $size = $sizes[$i % $sizes.Count]
        Invoke-SqlcmdEx -Sql "INSERT INTO dbo.ProductVariants (ProductId, SKU, Size, Color) VALUES ($productId, 'SKU-$i', '$size', '$color')" -Database $Database -ConnectionInfo $ConnectionInfo
    }
    
    # 7. Departments (hierarchical)
    $deptCount = $RowCounts['Departments']
    Write-Host "  Departments: $deptCount rows"
    $level1Depts = [Math]::Max(2, [int]($deptCount / 2))
    for ($i = 1; $i -le $level1Depts; $i++) {
        Invoke-SqlcmdEx -Sql "INSERT INTO dbo.Departments (Name) VALUES ('Dept_L1_$i')" -Database $Database -ConnectionInfo $ConnectionInfo
    }
    for ($i = 1; $i -le ($deptCount - $level1Depts); $i++) {
        $parentId = (($i - 1) % $level1Depts) + 1
        Invoke-SqlcmdEx -Sql "INSERT INTO dbo.Departments (Name, ParentDeptId) VALUES ('Dept_L2_$i', $parentId)" -Database $Database -ConnectionInfo $ConnectionInfo
    }
    
    # 8. Employees (5-level hierarchy)
    $empCount = $RowCounts['Employees']
    Write-Host "  Employees: $empCount rows"
    # Create root employees first (no manager)
    $rootCount = [Math]::Max(2, [int]($empCount / 5))
    for ($i = 1; $i -le $rootCount; $i++) {
        $deptId = (($i - 1) % $deptCount) + 1
        Invoke-SqlcmdEx -Sql "INSERT INTO dbo.Employees (FirstName, LastName, DeptId) VALUES ('Root$i', 'Employee', $deptId)" -Database $Database -ConnectionInfo $ConnectionInfo
    }
    # Create remaining employees with managers
    for ($i = $rootCount + 1; $i -le $empCount; $i++) {
        $managerId = [Math]::Max(1, $i - [Math]::Ceiling($empCount / 5))
        $deptId = (($i - 1) % $deptCount) + 1
        $hiredById = if ($i % 4 -eq 0) { 'NULL' } else { (($i - 1) % $rootCount) + 1 }
        Invoke-SqlcmdEx -Sql "INSERT INTO dbo.Employees (FirstName, LastName, ManagerId, DeptId, HiredById) VALUES ('Emp$i', 'Worker', $managerId, $deptId, $hiredById)" -Database $Database -ConnectionInfo $ConnectionInfo
    }
    
    # Update department heads (circular reference)
    for ($i = 1; $i -le $deptCount; $i++) {
        $headId = (($i - 1) % $empCount) + 1
        Invoke-SqlcmdEx -Sql "UPDATE dbo.Departments SET HeadId = $headId WHERE DeptId = $i" -Database $Database -ConnectionInfo $ConnectionInfo
    }
    
    # 9. Warehouses
    $warehouseCount = $RowCounts['Warehouses']
    Write-Host "  Warehouses: $warehouseCount rows"
    for ($i = 1; $i -le $warehouseCount; $i++) {
        $managerId = (($i - 1) % $empCount) + 1
        Invoke-SqlcmdEx -Sql "INSERT INTO dbo.Warehouses (Name, ManagerId) VALUES ('Warehouse_$i', $managerId)" -Database $Database -ConnectionInfo $ConnectionInfo
    }
    
    # 10. Customers
    $customerCount = $RowCounts['Customers']
    Write-Host "  Customers: $customerCount rows"
    for ($i = 1; $i -le $customerCount; $i++) {
        $primaryContactId = (($i - 1) % $contactCount) + 1
        # First customer has BillingContactId = PrimaryContactId for deduplication test
        $billingContactId = if ($i -eq 1) { $primaryContactId } elseif ($i % 2 -eq 0) { (($i) % $contactCount) + 1 } else { 'NULL' }
        $shippingContactId = if ($i % 3 -eq 0) { (($i + 1) % $contactCount) + 1 } else { 'NULL' }
        $accountManagerId = if ($i % 4 -eq 0) { (($i - 1) % $empCount) + 1 } else { 'NULL' }
        Invoke-SqlcmdEx -Sql "INSERT INTO dbo.Customers (Name, PrimaryContactId, BillingContactId, ShippingContactId, AccountManagerId) VALUES ('Customer_$i', $primaryContactId, $billingContactId, $shippingContactId, $accountManagerId)" -Database $Database -ConnectionInfo $ConnectionInfo
    }
    
    # 11. CustomerAddresses
    $addrCount = $RowCounts['CustomerAddresses']
    Write-Host "  CustomerAddresses: $addrCount rows"
    $addrTypes = @('Billing', 'Shipping', 'Main')
    for ($i = 1; $i -le $addrCount; $i++) {
        $custId = (($i - 1) % $customerCount) + 1
        $addrType = $addrTypes[$i % $addrTypes.Count]
        Invoke-SqlcmdEx -Sql "INSERT INTO dbo.CustomerAddresses (CustomerId, AddressType, Street, City) VALUES ($custId, '$addrType', 'Street $i', 'City $i')" -Database $Database -ConnectionInfo $ConnectionInfo
    }
    
    # 12. Orders
    $orderCount = $RowCounts['Orders']
    Write-Host "  Orders: $orderCount rows"
    for ($i = 1; $i -le $orderCount; $i++) {
        $custId = (($i - 1) % $customerCount) + 1
        $salesRepId = if ($i % 3 -eq 0) { 'NULL' } else { (($i - 1) % $empCount) + 1 }
        # Get first address for customer if available
        $shippingAddrId = if ($i % 2 -eq 0 -and $addrCount -gt 0) { (($i - 1) % $addrCount) + 1 } else { 'NULL' }
        $billingAddrId = if ($i % 3 -eq 0 -and $addrCount -gt 0) { (($i) % $addrCount) + 1 } else { 'NULL' }
        Invoke-SqlcmdEx -Sql "INSERT INTO dbo.Orders (CustomerId, SalesRepId, ShippingAddressId, BillingAddressId, TotalAmount) VALUES ($custId, $salesRepId, $shippingAddrId, $billingAddrId, $($i * 100))" -Database $Database -ConnectionInfo $ConnectionInfo
    }
    
    # 13. OrderDetails
    $detailCount = $RowCounts['OrderDetails']
    Write-Host "  OrderDetails: $detailCount rows"
    $lineNum = @{}
    for ($i = 1; $i -le $detailCount; $i++) {
        $orderId = (($i - 1) % $orderCount) + 1
        if (-not $lineNum.ContainsKey($orderId)) { $lineNum[$orderId] = 0 }
        $lineNum[$orderId]++
        $variantId = (($i - 1) % $variantCount) + 1
        Invoke-SqlcmdEx -Sql "INSERT INTO dbo.OrderDetails (OrderId, LineNum, ProductVariantId, Quantity, UnitPrice) VALUES ($orderId, $($lineNum[$orderId]), $variantId, $($i % 10 + 1), $($i * 10))" -Database $Database -ConnectionInfo $ConnectionInfo
    }
    
    # 14. OrderNotes (some with NULL OrderId)
    $noteCount = $RowCounts['OrderNotes']
    Write-Host "  OrderNotes: $noteCount rows"
    for ($i = 1; $i -le $noteCount; $i++) {
        $orderId = if ($i % 3 -eq 0) { 'NULL' } else { (($i - 1) % $orderCount) + 1 }
        $createdById = if ($i % 4 -eq 0) { 'NULL' } else { (($i - 1) % $empCount) + 1 }
        Invoke-SqlcmdEx -Sql "INSERT INTO dbo.OrderNotes (OrderId, NoteText, CreatedById) VALUES ($orderId, 'Note $i', $createdById)" -Database $Database -ConnectionInfo $ConnectionInfo
    }
    
    # 15. Invoices
    $invoiceCount = $RowCounts['Invoices']
    Write-Host "  Invoices: $invoiceCount rows"
    for ($i = 1; $i -le $invoiceCount; $i++) {
        $orderId = (($i - 1) % $orderCount) + 1
        $billingAddrId = if ($i % 2 -eq 0 -and $addrCount -gt 0) { (($i - 1) % $addrCount) + 1 } else { 'NULL' }
        Invoke-SqlcmdEx -Sql "INSERT INTO dbo.Invoices (OrderId, BillingAddressId) VALUES ($orderId, $billingAddrId)" -Database $Database -ConnectionInfo $ConnectionInfo
    }
    
    # 16. Payments
    $paymentCount = $RowCounts['Payments']
    Write-Host "  Payments: $paymentCount rows"
    for ($i = 1; $i -le $paymentCount; $i++) {
        $invoiceId = (($i - 1) % $invoiceCount) + 1
        $processedById = if ($i % 3 -eq 0) { 'NULL' } else { (($i - 1) % $empCount) + 1 }
        Invoke-SqlcmdEx -Sql "INSERT INTO dbo.Payments (InvoiceId, ProcessedById, Amount) VALUES ($invoiceId, $processedById, $($i * 50))" -Database $Database -ConnectionInfo $ConnectionInfo
    }
    
    # 17. Tags
    $tagCount = $RowCounts['Tags']
    Write-Host "  Tags: $tagCount rows"
    for ($i = 1; $i -le $tagCount; $i++) {
        Invoke-SqlcmdEx -Sql "INSERT INTO dbo.Tags (Name) VALUES ('Tag_$i')" -Database $Database -ConnectionInfo $ConnectionInfo
    }
    
    # 18. ProductSuppliers (many-to-many)
    $psCount = $RowCounts['ProductSuppliers']
    Write-Host "  ProductSuppliers: $psCount rows"
    $psCombos = @{}
    $psAdded = 0
    for ($p = 1; $p -le $productCount -and $psAdded -lt $psCount; $p++) {
        $numSuppliers = [Math]::Min(3, $supplierCount)
        for ($s = 1; $s -le $numSuppliers -and $psAdded -lt $psCount; $s++) {
            $supplierId = (($p + $s - 1) % $supplierCount) + 1
            $key = "$p-$supplierId"
            if (-not $psCombos.ContainsKey($key)) {
                $psCombos[$key] = $true
                $isPreferred = if ($s -eq 1) { 1 } else { 0 }
                try {
                    Invoke-SqlcmdEx -Sql "INSERT INTO dbo.ProductSuppliers (ProductId, SupplierId, IsPreferred) VALUES ($p, $supplierId, $isPreferred)" -Database $Database -ConnectionInfo $ConnectionInfo
                    $psAdded++
                } catch {}
            }
        }
    }
    
    # 19. ProductTags
    $ptCount = $RowCounts['ProductTags']
    Write-Host "  ProductTags: $ptCount rows"
    $ptAdded = 0
    for ($p = 1; $p -le $productCount -and $ptAdded -lt $ptCount; $p++) {
        for ($t = 1; $t -le 3 -and $ptAdded -lt $ptCount; $t++) {
            $tagId = (($p + $t - 1) % $tagCount) + 1
            try {
                Invoke-SqlcmdEx -Sql "INSERT INTO dbo.ProductTags (ProductId, TagId) VALUES ($p, $tagId)" -Database $Database -ConnectionInfo $ConnectionInfo
                $ptAdded++
            } catch {}
        }
    }
    
    # 20. Documents (hierarchical)
    $docCount = $RowCounts['Documents']
    Write-Host "  Documents: $docCount rows"
    $rootDocs = [Math]::Max(2, [int]($docCount / 3))
    for ($i = 1; $i -le $rootDocs; $i++) {
        $ownerId = (($i - 1) % $empCount) + 1
        Invoke-SqlcmdEx -Sql "INSERT INTO dbo.Documents (Title, OwnerId) VALUES ('Doc_Root_$i', $ownerId)" -Database $Database -ConnectionInfo $ConnectionInfo
    }
    for ($i = $rootDocs + 1; $i -le $docCount; $i++) {
        $ownerId = (($i - 1) % $empCount) + 1
        $parentId = (($i - 1) % $rootDocs) + 1
        Invoke-SqlcmdEx -Sql "INSERT INTO dbo.Documents (Title, OwnerId, ParentDocId) VALUES ('Doc_Child_$i', $ownerId, $parentId)" -Database $Database -ConnectionInfo $ConnectionInfo
    }
    
    # 21. DocumentVersions
    $dvCount = $RowCounts['DocumentVersions']
    Write-Host "  DocumentVersions: $dvCount rows"
    $versionNum = @{}
    for ($i = 1; $i -le $dvCount; $i++) {
        $docId = (($i - 1) % $docCount) + 1
        if (-not $versionNum.ContainsKey($docId)) { $versionNum[$docId] = 0 }
        $versionNum[$docId]++
        $createdById = (($i - 1) % $empCount) + 1
        Invoke-SqlcmdEx -Sql "INSERT INTO dbo.DocumentVersions (DocumentId, VersionNum, CreatedById) VALUES ($docId, $($versionNum[$docId]), $createdById)" -Database $Database -ConnectionInfo $ConnectionInfo
    }
    
    # 22. Comments (threaded)
    $commentCount = $RowCounts['Comments']
    Write-Host "  Comments: $commentCount rows"
    $rootComments = [Math]::Max(2, [int]($commentCount / 2))
    for ($i = 1; $i -le $rootComments; $i++) {
        $authorId = (($i - 1) % $empCount) + 1
        Invoke-SqlcmdEx -Sql "INSERT INTO dbo.Comments (AuthorId, EntityType, EntityId, CommentText) VALUES ($authorId, 'Document', $((($i-1) % $docCount) + 1), 'Root comment $i')" -Database $Database -ConnectionInfo $ConnectionInfo
    }
    for ($i = $rootComments + 1; $i -le $commentCount; $i++) {
        $authorId = (($i - 1) % $empCount) + 1
        $parentId = (($i - 1) % $rootComments) + 1
        Invoke-SqlcmdEx -Sql "INSERT INTO dbo.Comments (ParentCommentId, AuthorId, EntityType, EntityId, CommentText) VALUES ($parentId, $authorId, 'Document', $((($i-1) % $docCount) + 1), 'Reply $i')" -Database $Database -ConnectionInfo $ConnectionInfo
    }
    
    # 23. JobTitles
    $jtCount = $RowCounts['JobTitles']
    Write-Host "  JobTitles: $jtCount rows"
    for ($i = 1; $i -le $jtCount; $i++) {
        Invoke-SqlcmdEx -Sql "INSERT INTO dbo.JobTitles (Name) VALUES ('JobTitle_$i')" -Database $Database -ConnectionInfo $ConnectionInfo
    }
    
    # 24. Skills
    $skillCount = $RowCounts['Skills']
    Write-Host "  Skills: $skillCount rows"
    for ($i = 1; $i -le $skillCount; $i++) {
        Invoke-SqlcmdEx -Sql "INSERT INTO dbo.Skills (Name) VALUES ('Skill_$i')" -Database $Database -ConnectionInfo $ConnectionInfo
    }
    
    # 25. Teams
    $teamCount = $RowCounts['Teams']
    Write-Host "  Teams: $teamCount rows"
    for ($i = 1; $i -le $teamCount; $i++) {
        $leaderId = (($i - 1) % $empCount) + 1
        $deptId = (($i - 1) % $deptCount) + 1
        Invoke-SqlcmdEx -Sql "INSERT INTO dbo.Teams (Name, LeaderId, DeptId) VALUES ('Team_$i', $leaderId, $deptId)" -Database $Database -ConnectionInfo $ConnectionInfo
    }
    
    # 26. TeamMembers
    $tmCount = $RowCounts['TeamMembers']
    Write-Host "  TeamMembers: $tmCount rows"
    $tmAdded = 0
    for ($t = 1; $t -le $teamCount -and $tmAdded -lt $tmCount; $t++) {
        for ($e = 1; $e -le 5 -and $tmAdded -lt $tmCount; $e++) {
            $empId = (($t + $e - 1) % $empCount) + 1
            try {
                Invoke-SqlcmdEx -Sql "INSERT INTO dbo.TeamMembers (TeamId, EmployeeId) VALUES ($t, $empId)" -Database $Database -ConnectionInfo $ConnectionInfo
                $tmAdded++
            } catch {}
        }
    }
    
    # 27. EmployeeSkills
    $esCount = $RowCounts['EmployeeSkills']
    Write-Host "  EmployeeSkills: $esCount rows"
    $esAdded = 0
    for ($e = 1; $e -le $empCount -and $esAdded -lt $esCount; $e++) {
        for ($s = 1; $s -le 3 -and $esAdded -lt $esCount; $s++) {
            $skillId = (($e + $s - 1) % $skillCount) + 1
            try {
                Invoke-SqlcmdEx -Sql "INSERT INTO dbo.EmployeeSkills (EmployeeId, SkillId, Proficiency) VALUES ($e, $skillId, $s)" -Database $Database -ConnectionInfo $ConnectionInfo
                $esAdded++
            } catch {}
        }
    }
    
    # 28. Organizations
    $orgCount = $RowCounts['Organizations']
    Write-Host "  Organizations: $orgCount rows"
    $rootOrgs = [Math]::Max(2, [int]($orgCount / 2))
    for ($i = 1; $i -le $rootOrgs; $i++) {
        $contactId = (($i - 1) % $contactCount) + 1
        Invoke-SqlcmdEx -Sql "INSERT INTO dbo.Organizations (Name, PrimaryContactId) VALUES ('Org_$i', $contactId)" -Database $Database -ConnectionInfo $ConnectionInfo
    }
    for ($i = $rootOrgs + 1; $i -le $orgCount; $i++) {
        $parentId = (($i - 1) % $rootOrgs) + 1
        $contactId = (($i - 1) % $contactCount) + 1
        Invoke-SqlcmdEx -Sql "INSERT INTO dbo.Organizations (Name, ParentOrgId, PrimaryContactId) VALUES ('Org_Child_$i', $parentId, $contactId)" -Database $Database -ConnectionInfo $ConnectionInfo
    }
    
    # 29. Certifications
    $certCount = $RowCounts['Certifications']
    Write-Host "  Certifications: $certCount rows"
    for ($i = 1; $i -le $certCount; $i++) {
        $issuingBodyId = if ($orgCount -gt 0) { (($i - 1) % $orgCount) + 1 } else { 'NULL' }
        Invoke-SqlcmdEx -Sql "INSERT INTO dbo.Certifications (Name, IssuingBodyId) VALUES ('Cert_$i', $issuingBodyId)" -Database $Database -ConnectionInfo $ConnectionInfo
    }
    
    # 30. EmployeeCertifications
    $ecCount = $RowCounts['EmployeeCertifications']
    Write-Host "  EmployeeCertifications: $ecCount rows"
    $ecAdded = 0
    for ($e = 1; $e -le $empCount -and $ecAdded -lt $ecCount; $e++) {
        for ($c = 1; $c -le 2 -and $ecAdded -lt $ecCount; $c++) {
            $certId = (($e + $c - 1) % $certCount) + 1
            $date = "2020-0$(($c % 9) + 1)-$((($e % 28) + 1).ToString('00'))"
            try {
                Invoke-SqlcmdEx -Sql "INSERT INTO dbo.EmployeeCertifications (EmployeeId, CertificationId, DateEarned) VALUES ($e, $certId, '$date')" -Database $Database -ConnectionInfo $ConnectionInfo
                $ecAdded++
            } catch {}
        }
    }
    
    # 31. Tenants
    $tenantCount = $RowCounts['Tenants']
    Write-Host "  Tenants: $tenantCount rows"
    for ($i = 1; $i -le $tenantCount; $i++) {
        Invoke-SqlcmdEx -Sql "INSERT INTO dbo.Tenants (Name) VALUES ('Tenant_$i')" -Database $Database -ConnectionInfo $ConnectionInfo
    }
    
    # 32. TenantProducts
    $tpCount = $RowCounts['TenantProducts']
    Write-Host "  TenantProducts: $tpCount rows"
    $tpAdded = 0
    for ($t = 1; $t -le $tenantCount -and $tpAdded -lt $tpCount; $t++) {
        for ($p = 1; $p -le $productCount -and $tpAdded -lt $tpCount; $p++) {
            try {
                Invoke-SqlcmdEx -Sql "INSERT INTO dbo.TenantProducts (TenantId, ProductId) VALUES ($t, $p)" -Database $Database -ConnectionInfo $ConnectionInfo
                $tpAdded++
            } catch {}
        }
    }
    
    # 33. Deep Chain tables
    $chainCount = $RowCounts['DeepChainA']
    Write-Host "  DeepChain A-H: $chainCount rows each"
    for ($i = 1; $i -le $chainCount; $i++) {
        Invoke-SqlcmdEx -Sql "INSERT INTO dbo.DeepChainA (Name) VALUES ('ChainA_$i')" -Database $Database -ConnectionInfo $ConnectionInfo
    }
    for ($i = 1; $i -le $chainCount; $i++) {
        $parentId = (($i - 1) % $chainCount) + 1
        Invoke-SqlcmdEx -Sql "INSERT INTO dbo.DeepChainB (Name, ParentId) VALUES ('ChainB_$i', $parentId)" -Database $Database -ConnectionInfo $ConnectionInfo
    }
    for ($i = 1; $i -le $chainCount; $i++) {
        $parentId = (($i - 1) % $chainCount) + 1
        Invoke-SqlcmdEx -Sql "INSERT INTO dbo.DeepChainC (Name, ParentId) VALUES ('ChainC_$i', $parentId)" -Database $Database -ConnectionInfo $ConnectionInfo
    }
    for ($i = 1; $i -le $chainCount; $i++) {
        $parentId = (($i - 1) % $chainCount) + 1
        Invoke-SqlcmdEx -Sql "INSERT INTO dbo.DeepChainD (Name, ParentId) VALUES ('ChainD_$i', $parentId)" -Database $Database -ConnectionInfo $ConnectionInfo
    }
    for ($i = 1; $i -le $chainCount; $i++) {
        $parentId = (($i - 1) % $chainCount) + 1
        Invoke-SqlcmdEx -Sql "INSERT INTO dbo.DeepChainE (Name, ParentId) VALUES ('ChainE_$i', $parentId)" -Database $Database -ConnectionInfo $ConnectionInfo
    }
    for ($i = 1; $i -le $chainCount; $i++) {
        $parentId = (($i - 1) % $chainCount) + 1
        Invoke-SqlcmdEx -Sql "INSERT INTO dbo.DeepChainF (Name, ParentId) VALUES ('ChainF_$i', $parentId)" -Database $Database -ConnectionInfo $ConnectionInfo
    }
    for ($i = 1; $i -le $chainCount; $i++) {
        $parentId = (($i - 1) % $chainCount) + 1
        Invoke-SqlcmdEx -Sql "INSERT INTO dbo.DeepChainG (Name, ParentId) VALUES ('ChainG_$i', $parentId)" -Database $Database -ConnectionInfo $ConnectionInfo
    }
    for ($i = 1; $i -le $chainCount; $i++) {
        $parentId = (($i - 1) % $chainCount) + 1
        Invoke-SqlcmdEx -Sql "INSERT INTO dbo.DeepChainH (Name, ParentId) VALUES ('ChainH_$i', $parentId)" -Database $Database -ConnectionInfo $ConnectionInfo
    }
    
    # 34. HighFanout tables
    $hfParentCount = $RowCounts['HighFanoutParent']
    $hfChildCount = $RowCounts['HighFanoutChildren']
    Write-Host "  HighFanoutParent: $hfParentCount rows"
    Write-Host "  HighFanoutChildren: $hfChildCount rows"
    for ($i = 1; $i -le $hfParentCount; $i++) {
        Invoke-SqlcmdEx -Sql "INSERT INTO dbo.HighFanoutParent (Name) VALUES ('HFParent_$i')" -Database $Database -ConnectionInfo $ConnectionInfo
    }
    for ($i = 1; $i -le $hfChildCount; $i++) {
        $parentId = (($i - 1) % $hfParentCount) + 1
        Invoke-SqlcmdEx -Sql "INSERT INTO dbo.HighFanoutChildren (ParentId, Name) VALUES ($parentId, 'HFChild_$i')" -Database $Database -ConnectionInfo $ConnectionInfo
    }
    
    # 35. AuditLog
    $auditCount = $RowCounts['AuditLog']
    Write-Host "  AuditLog: $auditCount rows"
    for ($i = 1; $i -le $auditCount; $i++) {
        $userId = if ($i % 3 -eq 0) { 'NULL' } else { (($i - 1) % $empCount) + 1 }
        Invoke-SqlcmdEx -Sql "INSERT INTO dbo.AuditLog (TableName, RecordId, Action, UserId) VALUES ('Products', $i, 'INSERT', $userId)" -Database $Database -ConnectionInfo $ConnectionInfo
    }
    
    # 36. Settings
    $settingCount = $RowCounts['Settings']
    Write-Host "  Settings: $settingCount rows"
    for ($i = 1; $i -le $settingCount; $i++) {
        Invoke-SqlcmdEx -Sql "INSERT INTO dbo.Settings (SettingKey, SettingValue) VALUES ('Setting_$i', 'Value_$i')" -Database $Database -ConnectionInfo $ConnectionInfo
    }
    
    # 37. Attachments
    $attachCount = $RowCounts['Attachments']
    Write-Host "  Attachments: $attachCount rows"
    for ($i = 1; $i -le $attachCount; $i++) {
        $uploadedById = (($i - 1) % $empCount) + 1
        Invoke-SqlcmdEx -Sql "INSERT INTO dbo.Attachments (EntityType, EntityId, FileName, UploadedById) VALUES ('Document', $((($i-1) % $docCount) + 1), 'file$i.pdf', $uploadedById)" -Database $Database -ConnectionInfo $ConnectionInfo
    }
    
    # 38. EmployeeJobHistory
    $ejhCount = $RowCounts['EmployeeJobHistory']
    Write-Host "  EmployeeJobHistory: $ejhCount rows"
    for ($i = 1; $i -le $ejhCount; $i++) {
        $empId = (($i - 1) % $empCount) + 1
        $jobTitleId = (($i - 1) % $jtCount) + 1
        $deptId = (($i - 1) % $deptCount) + 1
        Invoke-SqlcmdEx -Sql "INSERT INTO dbo.EmployeeJobHistory (EmployeeId, JobTitleId, DeptId, StartDate) VALUES ($empId, $jobTitleId, $deptId, '2020-01-01')" -Database $Database -ConnectionInfo $ConnectionInfo
    }
    
    # 39. DocumentTags
    $dtCount = $RowCounts['DocumentTags']
    Write-Host "  DocumentTags: $dtCount rows"
    $dtAdded = 0
    for ($d = 1; $d -le $docCount -and $dtAdded -lt $dtCount; $d++) {
        for ($t = 1; $t -le 2 -and $dtAdded -lt $dtCount; $t++) {
            $tagId = (($d + $t - 1) % $tagCount) + 1
            try {
                Invoke-SqlcmdEx -Sql "INSERT INTO dbo.DocumentTags (DocumentId, TagId) VALUES ($d, $tagId)" -Database $Database -ConnectionInfo $ConnectionInfo
                $dtAdded++
            } catch {}
        }
    }
    
    # 40. CustomerTags
    $ctCount = $RowCounts['CustomerTags']
    Write-Host "  CustomerTags: $ctCount rows"
    $ctAdded = 0
    for ($c = 1; $c -le $customerCount -and $ctAdded -lt $ctCount; $c++) {
        for ($t = 1; $t -le 2 -and $ctAdded -lt $ctCount; $t++) {
            $tagId = (($c + $t - 1) % $tagCount) + 1
            try {
                Invoke-SqlcmdEx -Sql "INSERT INTO dbo.CustomerTags (CustomerId, TagId) VALUES ($c, $tagId)" -Database $Database -ConnectionInfo $ConnectionInfo
                $ctAdded++
            } catch {}
        }
    }
    
    # 41. WideTable
    $wideCount = $RowCounts['WideTable']
    Write-Host "  WideTable: $wideCount rows"
    for ($i = 1; $i -le $wideCount; $i++) {
        $catId = (($i - 1) % $catCount) + 1
        $suppId = (($i - 1) % $supplierCount) + 1
        $empId = (($i - 1) % $empCount) + 1
        $custId = (($i - 1) % $customerCount) + 1
        $deptId = (($i - 1) % $deptCount) + 1
        $contactId = (($i - 1) % $contactCount) + 1
        $whId = (($i - 1) % $warehouseCount) + 1
        $teamId = (($i - 1) % $teamCount) + 1
        $docId = (($i - 1) % $docCount) + 1
        $tagId = (($i - 1) % $tagCount) + 1
        Invoke-SqlcmdEx -Sql "INSERT INTO dbo.WideTable (Name, CategoryId, SupplierId, EmployeeId, CustomerId, DeptId, ContactId, WarehouseId, TeamId, DocumentId, TagId) VALUES ('Wide_$i', $catId, $suppId, $empId, $custId, $deptId, $contactId, $whId, $teamId, $docId, $tagId)" -Database $Database -ConnectionInfo $ConnectionInfo
    }
    
    # 42. Inventory
    $invCount = $RowCounts['Inventory']
    Write-Host "  Inventory: $invCount rows"
    $invAdded = 0
    for ($w = 1; $w -le $warehouseCount -and $invAdded -lt $invCount; $w++) {
        for ($v = 1; $v -le $variantCount -and $invAdded -lt $invCount; $v++) {
            try {
                Invoke-SqlcmdEx -Sql "INSERT INTO dbo.Inventory (WarehouseId, ProductVariantId, Quantity) VALUES ($w, $v, $($invAdded * 10))" -Database $Database -ConnectionInfo $ConnectionInfo
                $invAdded++
            } catch {}
        }
    }
    
    $totalRows = ($RowCounts.Values | Measure-Object -Sum).Sum
    Write-Host "  Total: ~$totalRows rows seeded"
}

function Initialize-TestDatabase {
    <#
    .SYNOPSIS
        Full initialization: create DB, schema, and seed data.
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$Database,
        
        [Parameter(Mandatory = $true)]
        $ConnectionInfo,
        
        [Parameter(Mandatory = $true)]
        [hashtable]$RowCounts,
        
        [Parameter(Mandatory = $false)]
        [switch]$ReuseData
    )
    
    $startTime = Get-Date
    
    # Create database if needed
    New-TestDatabase -Database $Database -ConnectionInfo $ConnectionInfo
    
    # Create schema
    Initialize-TestSchema -Database $Database -ConnectionInfo $ConnectionInfo
    
    if (-not $ReuseData) {
        # Clear and reseed
        Clear-TestData -Database $Database -ConnectionInfo $ConnectionInfo
        Invoke-DataSeeding -Database $Database -ConnectionInfo $ConnectionInfo -RowCounts $RowCounts
    }
    else {
        Write-Host "Reusing existing data."
    }
    
    $elapsed = (Get-Date) - $startTime
    Write-Host "Database initialization completed in $($elapsed.TotalSeconds.ToString('F1')) seconds"
}
