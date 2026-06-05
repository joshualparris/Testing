function A { Get-NetIPAddress -InterfaceAlias Ethernet0 -AddressFamily IPv4 -ErrorAction SilentlyContinue }
function Get-NetIPAddress { param($InterfaceAlias,$IPAddress,$AddressFamily,$ErrorAction); Write-Host 'MOCK HERE'; if ($PSBoundParameters.ContainsKey('IPAddress')) { return $null }; [pscustomobject]@{ IPAddress='10.0.0.5' } }
A | Format-Table -AutoSize
