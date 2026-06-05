# Exchange Lab Manager - Preflight Readiness Checker
# Comprehensive environment validation before running the GUI

[CmdletBinding()]
param(
    [switch]$FailFast  # Exit on first critical error
)

$UseVerbose = $PSBoundParameters.ContainsKey('Verbose')
$ErrorActionPreference = 'Continue'
$checks = @{ Passed = 0; Warning = 0; Critical = 0 }
$results = @()

function Report-Check {
    param(
        [Parameter(Mandatory)][string]$Name,
        [ValidateSet('Pass', 'Warning', 'Critical')]
        [string]$Status = 'Pass',
        [string]$Message
    )
    $checks[$Status]++
    $color = @{ Pass = 'Green'; Warning = 'Yellow'; Critical = 'Red' }[$Status]
    $symbol = @{ Pass = 'PASS'; Warning = 'WARN'; Critical = 'FAIL' }[$Status]
    Write-Host "[$symbol] $Name" -ForegroundColor $color
    if ($Message) { Write-Host "    $Message" -ForegroundColor Gray }
    $results += [pscustomobject]@{ Check = $Name; Status = $Status; Message = $Message }
    if ($FailFast -and $Status -eq 'Critical') { exit 1 }
}

Write-Host "Exchange Lab Manager - Preflight Readiness Check" -ForegroundColor Cyan
Write-Host "=================================================" -ForegroundColor Cyan
Write-Host ""

# ============ Host Requirements ============
Write-Host "Host Machine Requirements" -ForegroundColor Cyan
Write-Host "--------------------------" -ForegroundColor Cyan

# Check RAM
$ram = (Get-WmiObject Win32_PhysicalMemory | Measure-Object -Property Capacity -Sum).Sum / 1GB
if ($ram -ge 32) {
    Report-Check "Host RAM >= 32 GB" "Pass" "$ram GB available"
} elseif ($ram -ge 16) {
    Report-Check "Host RAM >= 32 GB" "Warning" "$ram GB (minimum 16 GB, 32 GB recommended)"
} else {
    Report-Check "Host RAM >= 32 GB" "Critical" "$ram GB (insufficient for lab)"
}

# Check disk space
$disk = (Get-Volume | Where-Object { $_.DriveType -eq 'Fixed' } | Measure-Object -Property SizeRemaining -Sum).Sum / 1GB
if ($disk -ge 200) {
    Report-Check "Host Disk Space >= 200 GB" "Pass" "$([math]::Round($disk, 0)) GB free"
} elseif ($disk -ge 100) {
    Report-Check "Host Disk Space >= 200 GB" "Warning" "$([math]::Round($disk, 0)) GB free (minimum 100 GB)"
} else {
    Report-Check "Host Disk Space >= 200 GB" "Critical" "$([math]::Round($disk, 0)) GB free (insufficient)"
}

# Check VirtualBox
if (Test-Path "C:\Program Files\Oracle\VirtualBox\VBoxManage.exe") {
    $vbVersion = & "C:\Program Files\Oracle\VirtualBox\VBoxManage.exe" --version 2>$null
    Report-Check "VirtualBox Installed" "Pass" "$vbVersion"
} else {
    Report-Check "VirtualBox Installed" "Critical" "Not found (download from virtualbox.org)"
}

# ============ VM Network Configuration ============
Write-Host ""
Write-Host "Lab VM Network Configuration" -ForegroundColor Cyan
Write-Host "-----------------------------" -ForegroundColor Cyan

# Get current network adapters (we're checking if on isolated network)
$adapters = Get-NetAdapter | Where-Object { $_.Status -eq 'Up' }
if ($adapters) {
    Report-Check "Network Adapters Active" "Pass" "$($adapters.Count) active adapter(s)"
} else {
    Report-Check "Network Adapters Active" "Warning" "No active adapters detected"
}

# Check IP configuration
$ipConfigs = Get-NetIPAddress -AddressFamily IPv4 | Where-Object { $_.IPAddress -notmatch '^127\.' }
if ($ipConfigs) {
    $staticIps = $ipConfigs | Where-Object { -not (Get-NetIPConfiguration -InterfaceIndex $_.InterfaceIndex).Dhcp }
    if ($staticIps) {
        Report-Check "Static IP Configuration" "Pass" "$($staticIps.Count) static IP(s) configured"
        if ($UseVerbose) { $staticIps | ForEach-Object { Write-Host "      $_" -ForegroundColor Gray } }
    } else {
        Report-Check "Static IP Configuration" "Warning" "All IPs are DHCP-assigned (static IPs recommended)"
    }
} else {
    Report-Check "Static IP Configuration" "Critical" "No IP configuration found"
}

# Check DNS
$dnsServers = Get-DnsClientServerAddress -AddressFamily IPv4 | Where-Object { $_.ServerAddresses -notmatch '^\s*$' }
if ($dnsServers) {
    $labDns = $dnsServers | Where-Object { $_.ServerAddresses -match '192\.168\.100\.' }
    if ($labDns) {
        Report-Check "Lab DNS Configuration" "Pass" "DNS set to lab IP (192.168.100.x)"
    } else {
        Report-Check "Lab DNS Configuration" "Warning" "DNS not configured for lab (expected 192.168.100.x)"
    }
} else {
    Report-Check "Lab DNS Configuration" "Warning" "No DNS servers configured"
}

# ============ Windows Server VM ============
Write-Host ""
Write-Host "Windows Server VM Requirements" -ForegroundColor Cyan
Write-Host "-------------------------------" -ForegroundColor Cyan

# Check OS version
$osVersion = [System.Environment]::OSVersion.Version
$productType = (Get-CimInstance Win32_OperatingSystem).ProductType
$IsWindowsServer = $productType -eq 3
if ($IsWindowsServer) {
    if ($osVersion.Major -ge 10) {
        Report-Check "Windows Server Edition" "Pass" "Windows Server 2016+ detected"
    } else {
        Report-Check "Windows Server Edition" "Critical" "Windows Server 2008 R2 or older (not supported)"
    }
} else {
    Report-Check "Windows Server Edition" "Warning" "Not a Windows Server (detected: $([System.Environment]::OSVersion.VersionString))"
}

# Check for pending reboot
$pendingReboot = Test-Path 'HKLM:\Software\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending'
if ($pendingReboot) {
    Report-Check "Pending Reboot" "Warning" "System requires reboot (complete reboots before lab work)"
} else {
    Report-Check "Pending Reboot" "Pass" "No pending reboot"
}

# Check disk space on C:
$cDrive = Get-Volume | Where-Object { $_.DriveLetter -eq 'C' }
$cFreeGB = $cDrive.SizeRemaining / 1GB
if ($cFreeGB -ge 50) {
    Report-Check "C: Drive Free Space" "Pass" "$([math]::Round($cFreeGB, 1)) GB free"
} elseif ($cFreeGB -ge 20) {
    Report-Check "C: Drive Free Space" "Warning" "$([math]::Round($cFreeGB, 1)) GB free (50 GB+ recommended)"
} else {
    Report-Check "C: Drive Free Space" "Critical" "$([math]::Round($cFreeGB, 1)) GB free (insufficient)"
}

# Check for Exchange drive
$dDrive = Get-Volume | Where-Object { $_.DriveLetter -eq 'D' }
if ($dDrive) {
    $dFreeGB = $dDrive.SizeRemaining / 1GB
    if ($dFreeGB -ge 100) {
        Report-Check "D: Drive Available (Exchange)" "Pass" "$([math]::Round($dFreeGB, 1)) GB free"
    } elseif ($dFreeGB -ge 50) {
        Report-Check "D: Drive Available (Exchange)" "Warning" "$([math]::Round($dFreeGB, 1)) GB free (100 GB+ recommended)"
    } else {
        Report-Check "D: Drive Available (Exchange)" "Warning" "$([math]::Round($dFreeGB, 1)) GB free (insufficient for Exchange)"
    }
} else {
    Report-Check "D: Drive Available (Exchange)" "Warning" "D: drive not found (Exchange install may require partition)"
}

# ============ PowerShell ============
Write-Host ""
Write-Host "PowerShell Environment" -ForegroundColor Cyan
Write-Host "----------------------" -ForegroundColor Cyan

if ($PSVersionTable.PSVersion.Major -ge 5) {
    Report-Check "PowerShell 5.1+" "Pass" "PowerShell $($PSVersionTable.PSVersion.Major).$($PSVersionTable.PSVersion.Minor) detected"
} else {
    Report-Check "PowerShell 5.1+" "Critical" "PowerShell $($PSVersionTable.PSVersion.Major).$($PSVersionTable.PSVersion.Minor) (need 5.1+)"
}

# Check execution policy
$policy = Get-ExecutionPolicy
if ($policy -in @('Unrestricted', 'RemoteSigned', 'Bypass')) {
    Report-Check "Execution Policy" "Pass" "$policy"
} else {
    Report-Check "Execution Policy" "Warning" "$policy (RemoteSigned or Bypass recommended)"
}

# Check elevation
if ((New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Report-Check "Administrator Privileges" "Pass" "Running as administrator"
} else {
    Report-Check "Administrator Privileges" "Critical" "Not running as administrator"
}

# ============ Windows Features ============
Write-Host ""
Write-Host "Required Windows Features" -ForegroundColor Cyan
Write-Host "-------------------------" -ForegroundColor Cyan

$requiredFeatures = @(
    @{ Name = 'AD-Domain-Services'; Display = 'AD DS (Domain Controller)' }
    @{ Name = 'NET-Framework-45-Features'; Display = '.NET Framework 4.5+' }
    @{ Name = 'Web-Server'; Display = 'IIS' }
    @{ Name = 'Web-Mgmt-Console'; Display = 'IIS Management Console' }
)

$windowsFeatureCommand = Get-Command Get-WindowsFeature -ErrorAction SilentlyContinue
if ($IsWindowsServer -and $windowsFeatureCommand) {
    foreach ($feature in $requiredFeatures) {
        try {
            $installed = Get-WindowsFeature -Name $feature.Name -ErrorAction Stop
            if ($installed -and $installed.Installed) {
                Report-Check "$($feature.Display) Installed" "Pass"
            } else {
                Report-Check "$($feature.Display) Installed" "Warning" "Not installed (can be installed during GUI execution)"
            }
        } catch {
            Report-Check "$($feature.Display) Installed" "Warning" "Unable to verify feature on this system"
        }
    }
} else {
    foreach ($feature in $requiredFeatures) {
        Report-Check "$($feature.Display) Installed" "Warning" "Feature detection unavailable on non-server OS or missing ServerManager module"
    }
}

# ============ Network Isolation ============
Write-Host ""
Write-Host "Network Isolation Verification" -ForegroundColor Cyan
Write-Host "-------------------------------" -ForegroundColor Cyan

# Try to reach external DNS (should fail if isolated)
try {
    $testExternal = Test-NetConnection -ComputerName 8.8.8.8 -Port 53 -ErrorAction SilentlyContinue -WarningAction SilentlyContinue
    if ($testExternal.TcpTestSucceeded -or $testExternal.PingSucceeded) {
        Report-Check "Network Isolation" "Critical" "Can reach external networks (8.8.8.8) - LAB IS NOT ISOLATED!"
    } else {
        Report-Check "Network Isolation" "Pass" "Cannot reach external networks (properly isolated)"
    }
} catch {
    Report-Check "Network Isolation" "Pass" "Cannot reach external networks (properly isolated)"
}

# ============ Exchange Lab Manager Package ============
Write-Host ""
Write-Host "Exchange Lab Manager Package" -ForegroundColor Cyan
Write-Host "-----------------------------" -ForegroundColor Cyan

$requiredFiles = @(
    'ExchangeLabManager.ps1'
    'qa-smoke-tests.ps1'
    'qa-full-tests.ps1'
    'run-gui.ps1'
    'run-gui.bat'
)

$missingFiles = @()
foreach ($file in $requiredFiles) {
    $path = Join-Path $PSScriptRoot $file
    if (Test-Path $path) {
        if ($UseVerbose) { Write-Host "  [OK] $file" -ForegroundColor Gray }
    } else {
        $missingFiles += $file
    }
}

if ($missingFiles.Count -eq 0) {
    Report-Check "Package Files Present" "Pass" "All required files found"
} else {
    Report-Check "Package Files Present" "Warning" "Missing: $($missingFiles -join ', ')"
}

# ============ Summary ============
Write-Host ""
Write-Host "=================================================" -ForegroundColor Cyan
Write-Host "Summary" -ForegroundColor Cyan
Write-Host "=================================================" -ForegroundColor Cyan
Write-Host "[OK] Passed:  $($checks.Passed)" -ForegroundColor Green
Write-Host "[WARN] Warnings: $($checks.Warning)" -ForegroundColor Yellow
Write-Host "[FAIL] Critical: $($checks.Critical)" -ForegroundColor Red
Write-Host ""

if ($checks.Critical -eq 0) {
    Write-Host "[OK] Ready to launch Exchange Lab Manager" -ForegroundColor Green
    exit 0
} else {
    Write-Host "[FAIL] Critical issues found - resolve before launching" -ForegroundColor Red
    exit 1
}
