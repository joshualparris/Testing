function Set-MockFunction {
    param([string]$Name, [scriptblock]$Body)
    Set-Item -Path "Function:\script:$Name" -Value $Body
}
Set-MockFunction -Name Get-NetIPAddress -Body {
    param($InterfaceAlias, $IPAddress, $AddressFamily, $ErrorAction)
    Write-Output "MOCK Get-NetIPAddress called: InterfaceAlias=$InterfaceAlias AddressFamily=$AddressFamily IPAddressBound=$($PSBoundParameters.ContainsKey('IPAddress'))"
    if ($PSBoundParameters.ContainsKey('IPAddress')) { Write-Output 'MOCK returning null for IPAddress-bound call'; return $null }
    [pscustomobject]@{ IPAddress = '10.0.0.5' }
    [pscustomobject]@{ IPAddress = '169.254.1.8' }
}
Set-Item -Path 'Function:\Global:Get-NetIPAddress' -Value (Get-Item 'Function:\script:Get-NetIPAddress').Value
Get-Command Get-NetIPAddress | Format-List Name,Source,CommandType
$items = @(Get-NetIPAddress -InterfaceAlias 'Ethernet0' -AddressFamily IPv4 -ErrorAction SilentlyContinue)
Write-Output "Returned items: $($items.Count)"
$items | ForEach-Object { Write-Output $_.IPAddress }
