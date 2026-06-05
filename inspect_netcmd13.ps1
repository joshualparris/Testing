function Get-NetIPAddress {
    param($InterfaceAlias, $IPAddress, $AddressFamily, $ErrorAction)
    Write-Host 'MOCK GETNETIP'
    if ($PSBoundParameters.ContainsKey('IPAddress')) { return $null }
    [pscustomobject]@{ IPAddress = '10.0.0.5' }
}
Get-Command Get-NetIPAddress -All | Format-List Name,Source,CommandType,ModuleName,Version
