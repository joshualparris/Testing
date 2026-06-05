$Global:ELM_NetworkOps = New-Object System.Collections.Generic.List[object]
. 'c:\dev\testing\ExchangeLabManager.ps1' -NoRun -QAMode:$true
function Assert-Admin { }
function Get-NetAdapter { param($ErrorAction); [pscustomobject]@{ Name = 'Ethernet0'; Status = 'Up'; HardwareInterface = $true; InterfaceDescription = 'Mock Adapter'; MacAddress = '00-11-22-33-44-55' } }
function Get-NetIPAddress { param($InterfaceAlias, $IPAddress, $AddressFamily, $ErrorAction); if ($PSBoundParameters.ContainsKey('IPAddress')) { return $null }; [pscustomobject]@{ IPAddress = '10.0.0.5' }; [pscustomobject]@{ IPAddress = '169.254.1.8' } }
function Remove-NetIPAddress { param($InterfaceAlias, $IPAddress, [switch]$Confirm, $ErrorAction); $Global:ELM_NetworkOps.Add([pscustomobject]@{ Op = 'Remove'; IPAddress = $IPAddress; InterfaceAlias = $InterfaceAlias }) | Out-Null }
function New-NetIPAddress { param($InterfaceAlias, $IPAddress, $PrefixLength, $DefaultGateway, $AddressFamily, $ErrorAction); $Global:ELM_NetworkOps.Add([pscustomobject]@{ Op = 'New'; IPAddress = $IPAddress; PrefixLength = $PrefixLength; DefaultGateway = $DefaultGateway; InterfaceAlias = $InterfaceAlias }) | Out-Null }
function Set-NetIPAddress { param($InterfaceAlias, $IPAddress, $PrefixLength, $ErrorAction); $Global:ELM_NetworkOps.Add([pscustomobject]@{ Op = 'Set'; IPAddress = $IPAddress; PrefixLength = $PrefixLength; InterfaceAlias = $InterfaceAlias }) | Out-Null }
function Set-DnsClientServerAddress { param($InterfaceAlias, $ServerAddresses, $ErrorAction); $Global:ELM_NetworkOps.Add([pscustomobject]@{ Op = 'Dns'; InterfaceAlias = $InterfaceAlias; ServerAddresses = $ServerAddresses }) | Out-Null }
function Get-NetIPConfiguration { param($InterfaceAlias, $ErrorAction); [pscustomobject]@{ IPv4DefaultGateway = @{ NextHop = '192.168.100.1' } } }
function Get-DnsClientServerAddress { param($InterfaceAlias, $AddressFamily, $ErrorAction); [pscustomobject]@{ ServerAddresses = @('127.0.0.1') } }
function DummyReport { param($message,$level); Write-Output ('REPORT:{0}:{1}' -f $level, $message) }
Set-StaticNetwork -Data @{ Ip = '192.168.100.10'; Mask = '255.255.255.0' } -Report ${function:DummyReport}
Write-Output "NetworkOps: $((($Global:ELM_NetworkOps | ForEach-Object { $_.Op }) -join '|'))"
$Global:ELM_NetworkOps | ForEach-Object { Write-Output ($_ | Out-String) }
