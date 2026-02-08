function Install-SqlSizer
{
    [cmdletbinding()]
    param
    (
        [Parameter(Mandatory = $false)]
        [bool]$Force = $false,

        [Parameter(Mandatory = $true)]
        [string]$Database,

        [Parameter(Mandatory = $true)]
        [DatabaseInfo]$DatabaseInfo,

        [Parameter(Mandatory = $true)]
        [SqlConnectionInfo]$ConnectionInfo
    )

    function CreateJsonFactory()
    {
        $factory = $DatabaseInfo.StoredProcedures | Where-Object { ($_.Schema -eq "SqlSizer") -and ($_.Name -eq "CreateJSON") }

        if ($null -eq $factory)
        {
            $sql = "CREATE PROCEDURE [SqlSizer].[CreateJSON] @SchemaName [VARCHAR](1024),@ViewName [VARCHAR](1024) AS
            BEGIN
                SET NOCOUNT ON
                DECLARE @columnCount INT,
                        @rowCount INT,
                        @i INT = 1,
                        @j INT = 1,
                        @sql_code NVARCHAR(1024),
                        @columnValue NVARCHAR(4000),
                        @ColumnName VARCHAR(1024)

                SELECT
                    ROW_NUMBER() OVER(ORDER BY (SELECT NULL)) AS Sequence,
                    c.TABLE_SCHEMA [schema],
                    c.TABLE_NAME [table],
                    c.COLUMN_NAME [column],
                    row_number() over(PARTITION BY c.TABLE_SCHEMA, c.TABLE_NAME order by c.ORDINAL_POSITION) as [position],
                    c.DATA_TYPE [dataType],
                    c.IS_NULLABLE [isNullable]
                INTO
                    #columns
                FROM
                    INFORMATION_SCHEMA.COLUMNS c
                WHERE
                    c.TABLE_SCHEMA = @SchemaName AND c.TABLE_NAME = @ViewName

                SET @sql_code = 'SELECT * INTO #viewData FROM ' + @SchemaName + '.' + @ViewName
                EXEC sp_executesql @sql_code

                SET @columnCount = (SELECT COUNT(*) FROM #columns)
                SET @rowCount = (SELECT COUNT(*) FROM #viewData)

                DECLARE @result NVARCHAR(max) = ''

                WHILE  @i <= @rowCount
                BEGIN
                    SET @result = @result + '{'

                    SET @j = 1
                    WHILE @j <= @columnCount
                    BEGIN
                        SET @sql_code = 'SELECT @columnName = [column] FROM #columns WHERE Sequence = ' + CONVERT(varchar, @j)
                        EXEC sp_executesql @sql_code, N'@columnName VARCHAR(1024) OUTPUT', @columnName = @columnName OUTPUT

                        SET @sql_code = 'SELECT @columnValue = [' + @columnName + '] FROM #viewData WHERE SqlSizer_RowSequence = ' + CONVERT(varchar, @i)
                        EXEC sp_executesql @sql_code, N'@columnValue NVARCHAR(4000) OUTPUT', @columnValue = @columnValue OUTPUT


                        IF @columnValue IS NULL
                            SET @result = @result + '""' + @columnName + '"":null'
                        ELSE
                            BEGIN
                                SET @columnValue = REPLACE(@columnValue, '\', '\\')
                                SET @result = @result + '""' + @columnName + '"":""' + @columnValue + '""'
                            END

                        IF @j <> @columnCount
                            SET @result = @result + ','
                        SET @j = @j + 1
                    END

                    SET @result = @result + '}'
                    IF @i <> @rowCount
                        SET @result = @result + ','
                    SET @i +=1;
                END

                DROP TABLE #columns
                DROP TABLE #viewData
                SELECT '[' + @result + ']'
            END"
            $null = Invoke-SqlcmdEx -Sql $sql -Database $Database -ConnectionInfo $ConnectionInfo
        }
    }

    $currentSqlSizerVersion = "1.0.6"

    $schemaExists = Test-SchemaExists -SchemaName "SqlSizer" -Database $Database -ConnectionInfo $ConnectionInfo
    if ($schemaExists -eq $true)
    {
        Write-Verbose "SqlSizer is already installed"
        Write-Verbose "Checking the version of installed SqlSizer ..."

        $sql = "IF OBJECT_ID('SqlSizer.Settings') IS NULL
        BEGIN
            SELECT 'Unknown' as Version
        END
        ELSE
        BEGIN
            SELECT Value as Version FROM SqlSizer.Settings WHERE Name = 'Version'
        END"
        $result = Invoke-SqlcmdEx -Sql $sql -Database $Database -ConnectionInfo $ConnectionInfo
        Write-Verbose "Installed version: $($result.Version)"
        Write-Verbose "Current version: $($currentSqlSizerVersion)"

        if ($Force)
        {
            Write-Verbose "Installation of SqlSizer forced"
            Write-Verbose "Uninstalling SqlSizer..."
            Uninstall-SqlSizer -Database $Database -DatabaseInfo $DatabaseInfo -ConnectionInfo $ConnectionInfo
        }
        else
        {
            if ($currentSqlSizerVersion -ne $result.Version)
            {
                $answer = Read-Host -Prompt "Would you like to uninstall SqlSizer [y/n]?"

                if ($answer -eq "y")
                {
                    Write-Verbose "New version. Uninstalling SqlSizer..."
                    Uninstall-SqlSizer -Database $Database -DatabaseInfo $DatabaseInfo -ConnectionInfo $ConnectionInfo
                }
                else
                {
                    throw "Installation has been interrupted"
                    return
                }
            }
            else
            {
                Write-Verbose "Installation of SqlSizer: skipped"
                return
            }
        }
    }

    Write-Verbose "Installing SqlSizer..."

    if ($DatabaseInfo.Tables.Count -eq 0)
    {
        throw "No tables have been found. Cannot install SqlSizer on database without tables."
    }

    $withPrimaryKey = $DatabaseInfo.Tables | Where-Object { ($_.SchemaName -notin @('SqlSizer', 'SqlSizerHistory')) -and ($null -ne $_.PrimaryKey) -and ($_.PrimaryKey.Count -gt 0) }
    if ($null -eq $withPrimaryKey)
    {
        throw "No table has been found with primary key. Run Install-PrimaryKeys or set up manually first."
    }

    Install-SqlSizerCore -Database $Database -DatabaseInfo $DatabaseInfo -ConnectionInfo $ConnectionInfo

    Update-DatabaseInfo -DatabaseInfo $DatabaseInfo -Database $Database -ConnectionInfo $ConnectionInfo
}
