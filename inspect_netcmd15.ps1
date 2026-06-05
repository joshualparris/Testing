Import-Module NetTCPIP -ErrorAction SilentlyContinue
Get-Command Get-NetIPAddress -All | Select-Object Name,Source,CommandType,ModuleName | Format-List
function Get-NetIPAddress {
    param($InterfaceAlias, $IPAddress, $AddressFamily, $ErrorAction)
    Write-Host 'OVERRIDE'
    if ($PSBoundParameters.ContainsKey('IPAddress')) { return $null }
    [pscustomobject]@{ IPAddress = '10.0.0.5' }
}
Get-Command Get-NetIPAddress -All | Select-Object Name,Source,CommandType,ModuleName | Format-List
@(Get-NetIPAddress -InterfaceAlias Ethernet0 -AddressFamily IPv4 -ErrorAction SilentlyContinue) | Format-Table -AutoSize
