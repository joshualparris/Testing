#requires -version 5.1
# Requires -RunAsAdministrator
<#
.SYNOPSIS
    Manual helper functions for an isolated Exchange sandbox lab.
.DESCRIPTION
    Retained as a reference and fallback command-line tool alongside the GUI.
#>

function Set-StaticIp {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [string]$InterfaceAlias = 'Ethernet',
        [string]$IpAddress = '192.168.100.10',
        [int]$PrefixLength = 24,
        [string]$DnsServer = '127.0.0.1',
        [string]$DefaultGateway = '192.168.100.1'
    )

    Write-Host "Configuring static IP on interface '$InterfaceAlias'..."
    $current = Get-NetIPAddress -InterfaceAlias $InterfaceAlias -AddressFamily IPv4 -ErrorAction SilentlyContinue |
        Where-Object { $_.IPAddress -notlike '169.254.*' }

    foreach ($address in $current) {
        if ($address.IPAddress -ne $IpAddress) {
            Remove-NetIPAddress -InterfaceAlias $InterfaceAlias -IPAddress $address.IPAddress -Confirm:$false -ErrorAction SilentlyContinue
        }
    }

    if (Get-NetIPAddress -InterfaceAlias $InterfaceAlias -IPAddress $IpAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue) {
        Set-NetIPAddress -InterfaceAlias $InterfaceAlias -IPAddress $IpAddress -PrefixLength $PrefixLength -ErrorAction Stop
    } else {
        New-NetIPAddress -InterfaceAlias $InterfaceAlias -IPAddress $IpAddress -PrefixLength $PrefixLength -DefaultGateway $DefaultGateway -AddressFamily IPv4 -ErrorAction Stop | Out-Null
    }

    Set-DnsClientServerAddress -InterfaceAlias $InterfaceAlias -ServerAddresses $DnsServer -ErrorAction Stop
    Write-Host "Static IP configuration complete: $IpAddress/$PrefixLength DNS $DnsServer"
}

function Install-ADDS {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param()

    Write-Host 'Installing Active Directory Domain Services...'
    Install-WindowsFeature -Name AD-Domain-Services -IncludeManagementTools -ErrorAction Stop | Out-Null
    Import-Module ADDSDeployment -ErrorAction Stop
    Write-Host 'AD DS feature installed successfully.'
}

function Promote-ToDomainController {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [string]$ForestName = 'mylab.local',
        [string]$SafeModePassword = 'P@ssw0rd!LabOnly'
    )

    Write-Host "Promoting server to domain controller for forest '$ForestName'..."
    $securePassword = ConvertTo-SecureString $SafeModePassword -AsPlainText -Force
    Install-ADDSForest -DomainName $ForestName -SafeModeAdministratorPassword $securePassword -InstallDns -CreateDnsDelegation:$false -Force -NoRebootOnCompletion -ErrorAction Stop
    Write-Host 'Promotion command completed. Reboot the server after the command returns.'
}

function Prepare-ExchangeAD {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param([Parameter(Mandatory)][string]$ExchangeSetupPath)

    if (-not (Test-Path -LiteralPath $ExchangeSetupPath)) { throw "Exchange setup path not found: $ExchangeSetupPath" }
    Push-Location $ExchangeSetupPath
    try {
        Write-Host 'Running Exchange Setup.exe /PrepareSchema...'
        .\Setup.exe /PrepareSchema /IAcceptExchangeServerLicenseTerms_DiagnosticDataON
        Write-Host 'Running Exchange Setup.exe /PrepareAD...'
        .\Setup.exe /PrepareAD /OrganizationName:TestLab /IAcceptExchangeServerLicenseTerms_DiagnosticDataON
    } finally {
        Pop-Location
    }
    Write-Host 'Exchange AD preparation complete.'
}

function Install-Exchange {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param([Parameter(Mandatory)][string]$ExchangeSetupPath)

    if (-not (Test-Path -LiteralPath $ExchangeSetupPath)) { throw "Exchange setup path not found: $ExchangeSetupPath" }
    Push-Location $ExchangeSetupPath
    try {
        .\Setup.exe /Mode:Install /Roles:Mailbox /IAcceptExchangeServerLicenseTerms_DiagnosticDataON /EnableErrorReporting:false /UseWindowsPowerShell:true
    } finally {
        Pop-Location
    }
}

function Download-AndApplyEomtMitigation {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [Parameter(Mandatory)][string]$Source,
        [string]$LocalPath = "$env:TEMP\EOMT.ps1"
    )

    if ($Source -match '^https?://') {
        Write-Host "Downloading EOMT script from $Source to $LocalPath..."
        Invoke-WebRequest -Uri $Source -OutFile $LocalPath -UseBasicParsing -ErrorAction Stop
    } else {
        if (-not (Test-Path -LiteralPath $Source)) { throw "Local EOMT script not found: $Source" }
        $LocalPath = (Resolve-Path -LiteralPath $Source).Path
    }

    Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope Process -Force
    & $LocalPath
    Write-Host 'EOMT script executed. Verify IIS outbound rewrite rules and OWA CSP behavior.'
}

function Get-ExchangeMitigationStatus {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param([string]$MitigationId = 'M2.1.x')

    if (Get-Command Get-Mitigation -ErrorAction SilentlyContinue) {
        Get-Mitigation -Identity $MitigationId -ErrorAction Stop | Format-List
    } else {
        Write-Warning 'Get-Mitigation was not found. Run from Exchange Management Shell for mitigation details.'
    }
}

function Create-TestMailboxes {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [string]$AttackerSamAccountName = 'attacker',
        [string]$VictimSamAccountName = 'victim',
        [string]$DomainName = 'mylab.local',
        [string]$Password = 'P@ssw0rd!LabOnly'
    )

    $securePassword = ConvertTo-SecureString $Password -AsPlainText -Force
    $domainParts = $DomainName.Split('.') | ForEach-Object { "DC=$_" }
    $userPath = 'CN=Users,' + ($domainParts -join ',')

    New-ADUser -Name $AttackerSamAccountName -SamAccountName $AttackerSamAccountName -UserPrincipalName "$AttackerSamAccountName@$DomainName" -AccountPassword $securePassword -Enabled $true -Path $userPath -ErrorAction Stop
    Enable-Mailbox -Identity "$AttackerSamAccountName@$DomainName" -ErrorAction Stop
    New-ADUser -Name $VictimSamAccountName -SamAccountName $VictimSamAccountName -UserPrincipalName "$VictimSamAccountName@$DomainName" -AccountPassword $securePassword -Enabled $true -Path $userPath -ErrorAction Stop
    Enable-Mailbox -Identity "$VictimSamAccountName@$DomainName" -ErrorAction Stop
    Write-Host "Created lab mailboxes for $AttackerSamAccountName and $VictimSamAccountName."
}

function Get-ExchangeLabHelp {
    Write-Host 'exchange-lab-automation.ps1 available functions:'
    Write-Host '  Set-StaticIp -InterfaceAlias Ethernet -IpAddress 192.168.100.10 -PrefixLength 24'
    Write-Host '  Install-ADDS'
    Write-Host '  Promote-ToDomainController -ForestName mylab.local'
    Write-Host '  Prepare-ExchangeAD -ExchangeSetupPath D:\'
    Write-Host '  Install-Exchange -ExchangeSetupPath D:\'
    Write-Host '  Create-TestMailboxes -DomainName mylab.local'
    Write-Host '  Download-AndApplyEomtMitigation -Source https://aka.ms/exchange-onprem-mitigation-tool'
    Write-Host '  Get-ExchangeMitigationStatus -MitigationId M2.1.x'
}
