function Get-NetIPAddress {
    param($InterfaceAlias, $IPAddress, $AddressFamily, $ErrorAction)
    Write-Host 'MOCK GETNETIP'
    if ($PSBoundParameters.ContainsKey('IPAddress')) { return $null }
    [pscustomobject]@{ IPAddress = '10.0.0.5' }
}
function Get-NetAdapter {
    param($ErrorAction)
    [pscustomobject]@{ Name = 'Ethernet0'; Status = 'Up'; HardwareInterface = $true }
}
function Set-DnsClientServerAddress {
    param($InterfaceAlias, $ServerAddresses, $ErrorAction)
    Write-Host 'MOCK DNS'
}
function New-NetIPAddress {
    param($InterfaceAlias, $IPAddress, $PrefixLength, $DefaultGateway, $AddressFamily, $ErrorAction)
    Write-Host 'MOCK NEW'
}
function Set-NetIPAddress {
    param($InterfaceAlias, $IPAddress, $PrefixLength, $ErrorAction)
    Write-Host 'MOCK SET'
}
. 'c:\dev\testing\ExchangeLabManager.ps1' -NoRun -QAMode:$true
function Assert-Admin { }
Set-StaticNetwork -Data @{ Ip='192.168.100.10'; Mask='255.255.255.0' } -Report { param($m,$l) Write-Host ('REPORT:{0}:{1}' -f $l, $m) }
