function Set-MockFunction {
    param([string]$Name, [scriptblock]$Body)
    Set-Item -Path "Function:\script:$Name" -Value $Body
}
$Global:ELM_NetworkOps = New-Object System.Collections.Generic.List[object]
. 'c:\dev\testing\ExchangeLabManager.ps1' -NoRun -QAMode:$true
function Assert-Admin { }
Set-MockFunction -Name Get-NetAdapter -Body {
    param($ErrorAction)
    [pscustomobject]@{ Name = 'Ethernet0'; Status = 'Up'; HardwareInterface = $true; InterfaceDescription = 'Mock Adapter'; MacAddress = '00-11-22-33-44-55' }
}
Set-Item -Path 'Function:\Global:Get-NetAdapter' -Value (Get-Item 'Function:\script:Get-NetAdapter').Value
Set-MockFunction -Name Get-NetIPAddress -Body {
    param($InterfaceAlias, $IPAddress, $AddressFamily, $ErrorAction)
    Write-Host "MOCK Get-NetIPAddress called: InterfaceAlias=$InterfaceAlias AddressFamily=$AddressFamily IPAddressBound=$($PSBoundParameters.ContainsKey('IPAddress'))"
    if ($PSBoundParameters.ContainsKey('IPAddress')) { Write-Host 'MOCK returning null for IPAddress-bound call'; return $null }
    [pscustomobject]@{ IPAddress = '10.0.0.5' }
    [pscustomobject]@{ IPAddress = '169.254.1.8' }
}
Set-Item -Path 'Function:\Global:Get-NetIPAddress' -Value (Get-Item 'Function:\script:Get-NetIPAddress').Value
Set-MockFunction -Name Remove-NetIPAddress -Body {
    param($InterfaceAlias, $IPAddress, [switch]$Confirm, $ErrorAction)
    Write-Host "MOCK Remove-NetIPAddress called: InterfaceAlias=$InterfaceAlias IPAddress=$IPAddress"
    $Global:ELM_NetworkOps.Add([pscustomobject]@{ Op = 'Remove'; IPAddress = $IPAddress; InterfaceAlias = $InterfaceAlias }) | Out-Null
}
Set-Item -Path 'Function:\Global:Remove-NetIPAddress' -Value (Get-Item 'Function:\script:Remove-NetIPAddress').Value
Set-MockFunction -Name New-NetIPAddress -Body {
    param($InterfaceAlias, $IPAddress, $PrefixLength, $DefaultGateway, $AddressFamily, $ErrorAction)
    Write-Host "MOCK New-NetIPAddress called: InterfaceAlias=$InterfaceAlias IPAddress=$IPAddress PrefixLength=$PrefixLength Gateway=$DefaultGateway"
    $Global:ELM_NetworkOps.Add([pscustomobject]@{ Op = 'New'; IPAddress = $IPAddress; PrefixLength = $PrefixLength; DefaultGateway = $DefaultGateway; InterfaceAlias = $InterfaceAlias }) | Out-Null
}
Set-Item -Path 'Function:\Global:New-NetIPAddress' -Value (Get-Item 'Function:\script:New-NetIPAddress').Value
Set-MockFunction -Name Set-NetIPAddress -Body {
    param($InterfaceAlias, $IPAddress, $PrefixLength, $ErrorAction)
    Write-Host "MOCK Set-NetIPAddress called: InterfaceAlias=$InterfaceAlias IPAddress=$IPAddress PrefixLength=$PrefixLength"
    $Global:ELM_NetworkOps.Add([pscustomobject]@{ Op = 'Set'; IPAddress = $IPAddress; PrefixLength = $PrefixLength; InterfaceAlias = $InterfaceAlias }) | Out-Null
}
Set-Item -Path 'Function:\Global:Set-NetIPAddress' -Value (Get-Item 'Function:\script:Set-NetIPAddress').Value
Set-MockFunction -Name Set-DnsClientServerAddress -Body {
    param($InterfaceAlias, $ServerAddresses, $ErrorAction)
    Write-Host "MOCK Set-DnsClientServerAddress called: InterfaceAlias=$InterfaceAlias ServerAddresses=$ServerAddresses"
    $Global:ELM_NetworkOps.Add([pscustomobject]@{ Op = 'Dns'; InterfaceAlias = $InterfaceAlias; ServerAddresses = $ServerAddresses }) | Out-Null
}
Set-Item -Path 'Function:\Global:Set-DnsClientServerAddress' -Value (Get-Item 'Function:\script:Set-DnsClientServerAddress').Value
$reports = New-Object System.Collections.Generic.List[object]
Trace-Command -Name CommandDiscovery -Expression { Set-StaticNetwork -Data @{ Ip = '192.168.100.10'; Mask = '255.255.255.0' } -Report { param($m,$l) Write-Host ('REPORT:{0}:{1}' -f $l, $m) } } -PSHost
Write-Output "NetworkOps: $((($Global:ELM_NetworkOps | ForEach-Object { $_.Op }) -join '|'))"
$Global:ELM_NetworkOps | ForEach-Object { Write-Output ($_ | Out-String) }
