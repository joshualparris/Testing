# Preflight Readiness Checklist

Use this checklist before running Exchange Lab Manager to verify your lab environment is ready.

## Environment Verification

### [ ] Host Machine
- [ ] **Virtualization enabled** in BIOS (Intel VT-x or AMD-V)
- [ ] **VirtualBox 7.0+** installed and running
- [ ] **32+ GB RAM available** (minimum 16 GB free during operations)
- [ ] **200+ GB free disk space** for ISOs and VM images
- [ ] **No conflicting hypervisors** (Hyper-V disabled if using VirtualBox on Windows)

### [ ] VM Network Configuration
- [ ] **Both VMs attached to "Internal Network"**
  - Right-click VM -> Settings -> Network -> Adapter 1
  - "Attached to: Internal Network"
  - Network name: `ExchangeLab` (identical for both VMs)
- [ ] **Both VMs have static IPs configured**
  - Domain Controller: 192.168.100.10/24
  - Exchange Server: 192.168.100.20/24
- [ ] **Both VMs can ping each other**
  ```powershell
  Test-NetConnection -ComputerName 192.168.100.10  # From Exchange VM
  Test-NetConnection -ComputerName 192.168.100.20  # From DC VM
  ```

### [ ] Windows Server Installation
- [ ] **Windows Server 2019 or 2022** (same version on both VMs)
- [ ] **Latest Windows Updates installed**
  ```powershell
  Get-HotFix | Select-Object -Last 5
  ```
- [ ] **Time synchronized** (critical for AD DS and Exchange)
  ```powershell
  Get-Date
  ```

### [ ] Disk Space
- [ ] **50 GB free on Domain Controller VM** (C: drive)
- [ ] **100 GB free on Exchange Server VM** (C: drive)
- [ ] **30 GB free on Exchange Server VM** (or designated Exchange drive D:)
  ```powershell
  Get-Volume | Select-Object DriveLetter, SizeRemaining, Size | Where-Object { $_.SizeRemaining -gt 0 }
  ```

---

## Required ISOs and Files

### [ ] Exchange Server ISO
- [ ] **ISO downloaded** from Microsoft
  - Exchange Server 2019 (CU13+ recommended)
  - Or Exchange Server SE (latest)
- [ ] **ISO accessible** to the lab VM
  - Mounted as DVD drive, or
  - Located on accessible file share
- [ ] **ISO integrity verified** (if checksum provided by Microsoft)

### [ ] Exchange Lab Manager Package
- [ ] **Package copied to lab VM** (C:\Lab\ recommended)
  - Or accessible from mounted ISO/share
- [ ] **Files include**:
  - `ExchangeLabManager.ps1`
  - `build-executable.ps1`
  - `qa-smoke-tests.ps1`
  - `qa-full-tests.ps1`
  - `run-gui.ps1`
  - `run-gui.bat`

---

## Exchange Server VM Pre-Checks

### [ ] Windows Features
- [ ] **Verify Windows Server Evaluation is active**
  ```powershell
  Get-WindowsEdition -Online
  ```
- [ ] **(Recommended) Pre-install features** to save time during GUI execution
  ```powershell
  Install-WindowsFeature NET-Framework-45-Features, RPC-over-HTTP-proxy, `
    RSAT-Clustering, RSAT-Clustering-CmdInterface, Web-Mgmt-Console, WAS-Process-Model, `
    WAS-Config-APIs, HTTP-Activation, IISRESET
  ```

### [ ] PowerShell Version
- [ ] **PowerShell 5.1+** installed
  ```powershell
  $PSVersionTable.PSVersion
  ```

### [ ] Network Configuration
- [ ] **DNS configured to point to Domain Controller**
  ```powershell
  Set-DnsClientServerAddress -InterfaceAlias Ethernet -ServerAddresses 192.168.100.10
  ```
- [ ] **Can resolve DC hostname** (after DC is promoted)
  ```powershell
  nslookup labdc.mylab.local 192.168.100.10
  ```

### [ ] User Account
- [ ] **Logged in as Local Administrator** or domain admin
  ```powershell
  [System.Security.Principal.WindowsIdentity]::GetCurrent().Name
  ```
- [ ] **PowerShell run as Administrator**
  - Right-click PowerShell -> "Run as administrator"

---

## Domain Controller VM Pre-Checks

### [ ] Network Configuration
- [ ] **Static IP set**: 192.168.100.10/24
- [ ] **Can reach Exchange VM** (or at least respond to ping)
  ```powershell
  Test-NetConnection -ComputerName 192.168.100.20
  ```

### [ ] User Account
- [ ] **Logged in as Local Administrator**
- [ ] **PowerShell run as Administrator**

---

## Readiness Validation Commands

Run these commands on each VM to verify readiness:

### Domain Controller VM
```powershell
# Network connectivity
Test-NetConnection -ComputerName 192.168.100.20  # Should succeed
Get-NetIPAddress | Where-Object { $_.AddressState -eq 'Preferred' }

# Time sync
Get-Date

# User permissions
[Security.Principal.WindowsIdentity]::GetCurrent().Name
```

### Exchange Server VM
```powershell
# Network connectivity to DC
Test-NetConnection -ComputerName 192.168.100.10  # Should succeed

# DNS resolution
nslookup 192.168.100.10  # Should resolve after DC promotion

# PowerShell version
$PSVersionTable.PSVersion  # Should be 5.1+

# Disk space
Get-Volume | Format-Table DriveLetter, SizeRemaining, Size

# User permissions (elevated)
[Security.Principal.WindowsIdentity]::GetCurrent().Name  # Should show Administrator
[Security.Principal.WindowsIdentity]::GetCurrent() | ForEach-Object { 
  (New-Object Security.Principal.WindowsPrincipal($_)).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator) 
}  # Should return True

# PowerShell execution policy
Get-ExecutionPolicy  # Should allow script execution
```

---

## Critical: Isolation Verification

Warning: **BEFORE RUNNING THE LAB**, verify network isolation:

```powershell
# From a lab VM, test that you CANNOT reach the host or external networks
Test-NetConnection -ComputerName 8.8.8.8  # Should FAIL (no external access)
Test-NetConnection -ComputerName <HostIP>  # Should FAIL (no host access)

# But you CAN reach the other lab VM
Test-NetConnection -ComputerName 192.168.100.10  # Should SUCCEED
```

**If external connectivity exists, your lab is NOT isolated and you risk affecting production networks.**

---

## Pre-Launch Checklist

Right before launching `ExchangeLabManager.ps1`:

### On Exchange Server VM:
- [ ] Both VMs powered on and at login screen
- [ ] Network connectivity verified to DC (ping succeeds)
- [ ] Logged in as Administrator
- [ ] Exchange ISO mounted or accessible (D:\ drive, for example)
- [ ] PowerShell open in elevated session
- [ ] Navigated to Exchange Lab Manager package directory
- [ ] Antivirus/security software **paused or excluded** from lab directories
  ```
  Exclude: C:\Lab\*
  Exclude: C:\Program Files\Microsoft\Exchange Server\*
  Exclude: C:\Windows\System32\drivers\etc\*
  ```

### Ready to Launch:
```powershell
cd C:\Lab
.\ExchangeLabManager.ps1
# Or
Right-click ExchangeLabManager.ps1 -> Run with PowerShell
```

---

## Troubleshooting Pre-Flight Issues

### "VMs can't reach each other"
See: [LAB-SETUP-GUIDE.md](LAB-SETUP-GUIDE.md) -> Troubleshooting

### "PowerShell execution policy blocks script"
```powershell
powershell -ExecutionPolicy Bypass -File ExchangeLabManager.ps1
```

### "Not enough disk space"
Increase VM disk allocation in VirtualBox:
- VM -> Settings -> Storage -> Expand VDI disk image

### "No elevated permissions"
```powershell
# Re-launch PowerShell as Administrator
Start-Process powershell -Verb RunAs
```

---

## Estimated Timeline

| Phase | Duration | Task |
|-------|----------|------|
| VM Creation | 30-60 min | Create 2 VMs, install Windows |
| Network Config | 10 min | Set IPs, verify connectivity |
| Pre-Install Features | 15-30 min | Optional feature pre-install |
| Lab Setup | 5 min | Verify checklist items |
| **GUI Execution** | **60-90 min** | **Run Exchange Lab Manager** |
| - DC Setup | 10 min | AD DS promotion |
| - Exchange Prep | 15 min | Schema/Org prep |
| - Exchange Install | 30-45 min | Mailbox role setup |
| - Mitigation | 10 min | EOMT/CSP rules |

**Total first-time lab build: 2-3 hours**

---

## Next Steps

1. [done] Complete this checklist
2. [docs] Review [LAB-SETUP-GUIDE.md](LAB-SETUP-GUIDE.md) for detailed instructions
3. [run] Launch `ExchangeLabManager.ps1`
4. [search] Reference [TROUBLESHOOTING.md](TROUBLESHOOTING.md) if issues arise
5. [done] Review [CVE-2026-42897-INTEGRATION.md](CVE-2026-42897-INTEGRATION.md) for validation tab usage

---

Last Updated: 2026-06-05


