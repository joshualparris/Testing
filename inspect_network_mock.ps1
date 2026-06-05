function Get-NetIPAddress {
    param($InterfaceAlias, $IPAddress, $AddressFamily, $ErrorAction)
    if ($PSBoundParameters.ContainsKey('IPAddress')) { return $null }
    [pscustomobject]@{ IPAddress = '10.0.0.5' }
    [pscustomobject]@{ IPAddress = '169.254.1.8' }
}
$records = @(Get-NetIPAddress -InterfaceAlias 'Ethernet0' -AddressFamily IPv4 -ErrorAction SilentlyContinue | Where-Object { $_.IPAddress -notlike '169.254.*' })
foreach ($r in $records) { Write-Output $r.IPAddress }
