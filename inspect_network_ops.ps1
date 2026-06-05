# Setup environment
. 'c:\dev\testing\ExchangeLabManager.ps1' -NoRun -QAMode:$true
function Assert-Admin { }
$script:NetworkOps = New-Object System.Collections.Generic.List[object]
function Get-NetAdapter { param($ErrorAction); [pscustomobject]@{ Name = 'Ethernet0'; Status = 'Up'; HardwareInterface = $true } }
function Get-NetIPAddress { param($InterfaceAlias, $IPAddress, $AddressFamily, $ErrorAction); if ($PSBoundParameters.ContainsKey('IPAddress')) { return $null }; [pscustomobject]@{ IPAddress = '10.0.0.5' }; [pscustomobject]@{ IPAddress = '169.254.1.8' } }
function Remove-NetIPAddress { param($InterfaceAlias, $IPAddress, [switch]$Confirm, $ErrorAction); $script:NetworkOps.Add([pscustomobject]@{ Op = 'Remove'; IPAddress = $IPAddress; InterfaceAlias = $InterfaceAlias }) | Out-Null }
function New-NetIPAddress { param($InterfaceAlias, $IPAddress, $PrefixLength, $DefaultGateway, $AddressFamily, $ErrorAction); $script:NetworkOps.Add([pscustomobject]@{ Op = 'New'; IPAddress = $IPAddress; PrefixLength = $PrefixLength; DefaultGateway = $DefaultGateway; InterfaceAlias = $InterfaceAlias }) | Out-Null }
function Set-NetIPAddress { param($InterfaceAlias, $IPAddress, $PrefixLength, $ErrorAction); $script:NetworkOps.Add([pscustomobject]@{ Op = 'Set'; IPAddress = $IPAddress; PrefixLength = $PrefixLength; InterfaceAlias = $InterfaceAlias }) | Out-Null }
function Set-DnsClientServerAddress { param($InterfaceAlias, $ServerAddresses, $ErrorAction); $script:NetworkOps.Add([pscustomobject]@{ Op = 'Dns'; InterfaceAlias = $InterfaceAlias; ServerAddresses = $ServerAddresses }) | Out-Null }
function DummyReport { param($message,$level) }
Set-StaticNetwork -Data @{ Ip = '192.168.100.10'; Mask = '255.255.255.0' } -Report ${function:DummyReport}
Write-Output "NetworkOps: $((($script:NetworkOps | ForEach-Object { $_.Op }) -join '|'))"
$script:NetworkOps | ForEach-Object { Write-Output $_ }
Write-Output "Report Text:"; Write-Output (Get-ReportText $reports)
