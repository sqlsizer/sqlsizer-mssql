# Minimal test to verify type access
Describe 'Type Access Test' {
    It 'Can access SqlConnectionInfo via New-Object' {
        $conn = New-Object SqlConnectionInfo
        $conn | Should -Not -BeNullOrEmpty
        $conn.GetType().Name | Should -Be 'SqlConnectionInfo'
    }
    
    It 'Can access DatabaseInfo via New-Object' {
        $dbInfo = New-Object DatabaseInfo
        $dbInfo | Should -Not -BeNullOrEmpty
        $dbInfo.GetType().Name | Should -Be 'DatabaseInfo'
    }
    
    It 'Can call Get-DatabaseInfo function' {
        $conn = New-Object SqlConnectionInfo
        $conn.Server = '.'
        $conn.EncryptConnection = $false
        $conn.Statistics = New-Object SqlConnectionStatistics
        
        $dbInfo = Get-DatabaseInfo -Database 'SqlSizerIntegrationTests' -ConnectionInfo $conn
        $dbInfo | Should -Not -BeNullOrEmpty
    }
}
