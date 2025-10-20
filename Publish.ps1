param (
    [string] $apiKey
)

Publish-Module -Path ".\SqlSizer-MSSQL" -NuGetApiKey $apiKey -Verbose -Force
