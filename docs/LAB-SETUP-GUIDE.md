# Exchange Lab Manager - Lab Setup Guide

This guide walks through the prerequisites and VirtualBox configuration needed before running Exchange Lab Manager.

## System Requirements

### Host Machine
- **Virtualization**: Intel VT-x or AMD-V capable CPU
- **RAM**: Minimum 32 GB available (16 GB minimum to start, but less stable)
- **Disk Space**: 200+ GB free for multiple lab VMs and ISO files
- **VirtualBox**: Version 7.0+ (download from https://www.virtualbox.org/)

### Lab VM - Domain Controller
- **OS**: Windows Server 2019 or 2022 (Evaluation or properly licensed)
- **RAM**: 4 GB (8 GB recommended)
- **Disk**: 50 GB
- **Network**: Internal Network (isolated)
- **Roles**: AD DS (promoted by GUI or manual setup)

### Lab VM - Exchange Server
- **OS**: Windows Server 2019 or 2022 (must match DC)
- **RAM**: 8 GB (16 GB recommended for Mailbox role)
- **Disk**: 100 GB
- **Network**: Internal Network (same as DC)
- **Exchange Edition**: Exchange Server 2019, 2016, or SE

---

## Pre-Lab Checklist

Before launching Exchange Lab Manager, complete these steps:

### 1. Create Windows Server VMs

**For Domain Controller VM:**
```
Name:        LabDC
OS:          Windows Server 2019/2022 Evaluation
RAM:         4 GB
Disk:        50 GB
```

**For Exchange Server VM:**
```
Name:        LabEx
OS:          Windows Server 2019/2022 Evaluation (same as DC)
RAM:         8-16 GB
Disk:        100 GB
```

---

### 2. Configure Network Isolation

**In VirtualBox, for each lab VM:**

1. Power off the VM
2. Right-click VM -> **Settings**
3. Navigate to **Network**
4. For **Adapter 1**:
   - **Enabled**: ok (checked)
   - **Attached to**: **Internal Network**
   - **Name**: `ExchangeLab` (must be identical for both VMs)
   - **Adapter Type**: Intel Pro/1000
5. Click **OK**

[done] **Result**: Both VMs can reach each other on 192.168.100.0/24 network, but cannot reach the host or external networks.

---

### 3. Install Windows Server

On each VM:

1. Start the VM and boot from Windows Server ISO
2. Complete Windows setup
3. For Domain Controller VM:
   - Set Computer Name: `LabDC` (or similar)
   - Set Static IP: 192.168.100.10
4. For Exchange Server VM:
   - Set Computer Name: `LabEx` (or similar)
   - Set Static IP: 192.168.100.20

**Network Configuration Example (for LabEx VM):**
```
IP Address:       192.168.100.20
Subnet Mask:      255.255.255.0
Default Gateway:  192.168.100.10
Preferred DNS:    192.168.100.10 (after DC is promoted)
```

---

### 4. Pre-Install Windows Features (Optional but Recommended)

If you have Windows ISO mounted, install these features on each server before running the GUI:

**On Domain Controller VM:**
```powershell
Install-WindowsFeature AD-Domain-Services -IncludeManagementTools
```

**On Exchange Server VM:**
```powershell
# Windows Server 2019 / 2022 prerequisites for Exchange Server Mailbox role
Install-WindowsFeature NET-Framework-45-Features, RPC-over-HTTP-proxy, `
  RSAT-Clustering, RSAT-Clustering-CmdInterface, RSAT-Clustering-Mgmt, `
  RSAT-Clustering-PowerShell, Web-Mgmt-Console, WAS-Process-Model, `
  WAS-Config-APIs, HTTP-Activation, IISRESET, RSAT-ADDS

# Also install .NET 4.8 if not present
# Download from https://support.microsoft.com/en-us/topic/the-latest-supported-visual-c-downloads
```

---

### 5. Download Required ISOs and Tools

On your **Host Machine**, download:

1. **Exchange Server ISO**
   - Exchange Server 2019 (CU13 or later recommended)
   - Or Exchange Server SE (latest)
   - Source: https://www.microsoft.com/en-us/download/

2. **Windows Server ISO** (if not already available)
   - Windows Server 2019 or 2022 Evaluation
   - Source: https://www.microsoft.com/en-us/evalcenter/

3. **Exchange Lab Manager Package** (this repository)
   - Clone or download to a USB drive or shared folder

Place the Exchange ISO somewhere accessible:
- Example: `C:\ISOs\Exchange2019.iso`
- Or mount it in VirtualBox: VM -> Settings -> Storage -> Add ISO

---

### 6. Verify Network Connectivity Between VMs

Before running the GUI:

**From Exchange VM, test connectivity to DC VM:**
```powershell
Test-NetConnection -ComputerName 192.168.100.10 -Port 389  # LDAP
Test-NetConnection -ComputerName 192.168.100.10 -Port 53   # DNS
```

[done] Both tests should succeed ("TcpTestSucceeded : True")

---

### 7. Import Exchange Lab Manager

**Copy the package into each VM:**

Option A - Via USB Drive:
1. Create USB with ExchangeLabManager files
2. Boot LabEx VM
3. Plug in USB and copy files to `C:\Lab\`

Option B - Via ISO (VirtualBox):
1. Open the `.dist\ExchangeLabFiles.iso` in VirtualBox
2. Mount as DVD in the LabEx VM
3. Copy files from the DVD to `C:\Lab\`

Option C - Via File Sharing:
1. Set up VirtualBox Shared Folder (VM -> Settings -> Shared Folders)
2. Mount share in guest: `net use Z: \\vboxsvr\ShareName`
3. Copy files from Z:\ to `C:\Lab\`

---

## Workflow: Step-by-Step Lab Deployment

### Phase 1: Domain Controller Setup (5-10 minutes)

1. **Boot LabDC VM** and log in with local admin
2. **Open PowerShell** as Administrator
3. **Set DNS forwarder** (optional, for safety):
   ```powershell
   # After AD DS is promoted, set a safe forwarder
   Set-DnsServerForwarder -IPAddress 8.8.8.8, 1.1.1.1
   ```
4. **Wait for reboot** (if required by GUI or features)

---

### Phase 2: Exchange Server Setup (20-40 minutes)

1. **Boot LabEx VM** and log in
2. **Set DNS to point to DC:**
   ```powershell
   Set-DnsClientServerAddress -InterfaceAlias Ethernet -ServerAddresses 192.168.100.10
   ```
3. **Navigate to** `C:\Lab\` or mounted ISO location
4. **Right-click** `ExchangeLabManager.ps1` -> **Run with PowerShell**
   - Confirm elevation prompt
5. **Set Lab Workflow**:
   - **System & Network Setup tab**: Skip (already configured)
   - **Exchange Prep & Install tab**:
     - Set Exchange ISO path (e.g., `D:\` if mounted)
     - Click **Prepare Exchange** (Schema/Org prep)
     - Click **Launch Installer** (Mailbox role setup)
     - Wait 30-45 minutes for completion
6. **After installation**: Exchange Management Shell should work

---

### Phase 3: Mitigation & Testing (10-15 minutes)

1. **Mitigation & EOMT tab**:
   - Click **Check Status** to verify Exchange is installed
   - Click **Download EOMT** to fetch Microsoft's mitigation tool
   - Click **Run EOMT** to apply CSP headers and IIS rules

2. **CVE-2026-42897 Validation tab**:
   - Click **Check Exchange Build** (should show version)
   - Click **Check EM Service** (if EM service is deployed)
   - Click **Check Mitigation State** (should show M2/M2.1.x)
   - Update **OWA URL** field: `https://lab-ex01.exchange-lab.local/owa` (adjust for your hostname)
   - Click **Verify CSP Header** (should show CSP header present)

3. **Automated XSS Test tab** (optional):
   - Set **Test Mailbox**: `testuser@mylab.local`
   - Click **Send Test Email** to verify SMTP functionality

---

## Troubleshooting Pre-Lab Issues

### VMs can't reach each other

**Check:**
```powershell
# On LabEx VM
Test-NetConnection -ComputerName 192.168.100.10

# Should show TcpTestSucceeded: True
```

**If fails:**
- Verify both VMs have "Internal Network" in their network settings
- Verify both use the same internal network name (`ExchangeLab`)
- Restart the VM's network adapter:
  ```powershell
  Restart-NetAdapter -Name Ethernet
  ```

---

### DNS not working

**Check:**
```powershell
# On LabEx VM
Get-DnsClientServerAddress
# Should show 192.168.100.10 (or DC's IP)

nslookup lab-ex01.exchange-lab.local
# Should resolve
```

**If not working:**
- Promote DC first in Phase 1 (must create Active Directory)
- Then point LabEx DNS to DC
- Wait 1-2 minutes for replication

---

### Active Directory promotion failed

**Check Event Viewer:**
```powershell
Get-EventLog -LogName "Directory Service" -Newest 10
```

**Common causes:**
- DNS not yet configured
- Network connectivity issues
- Insufficient permissions (ensure logged in as local admin)

**Solution:**
- Review the logs
- Reboot both VMs
- Start over with Phase 1

---

## Advanced: Creating a Lab Snapshot

After everything is set up and working:

1. **Power off both VMs**
2. **In VirtualBox**: VM -> Snapshots -> **Take Snapshot**
   - Name: `Post-Install-Ready` (for DC)
   - Name: `Exchange-Installed-Mitigation-Applied` (for Exchange)
3. **Later**, you can **Restore** to this snapshot to reset the lab quickly

---

## Performance Tuning

If the lab is slow:

### Increase VM Allocation

```powershell
# In PowerShell on Host Machine
$vm = Get-VM "LabEx"
$vm | Set-VM -MemoryMB 16384  # 16 GB RAM
$vm | Set-VM -ProcessorCount 4 # 4 CPU cores
```

### Optimize Disk

```powershell
# On the guest VM, defragment disk
Optimize-Volume -DriveLetter C -Defrag

# Clear temporary files
Remove-Item "$env:TEMP\*" -Recurse -Force -ErrorAction SilentlyContinue
```

### Monitor During Operations

```powershell
# On host, monitor VM resource usage
Get-VM "LabEx" | Measure-Object -Property MemoryAssigned | Select-Object Sum
```

---

## Cleanup & Reset

To tear down the lab:

```powershell
# Stop VMs gracefully
$vm = Get-VM "LabEx"
Stop-VM $vm

$vm = Get-VM "LabDC"
Stop-VM $vm

# Optional: Delete the VMs to free up disk space
Remove-VM $vm
```

Or restore from snapshot if you took one.

---

## Related Documentation

- [Exchange Lab Manager README](README.md) - Main usage guide
- [CVE-2026-42897 Integration](CVE-2026-42897-INTEGRATION.md) - Validation tab features
- [Troubleshooting Guide](TROUBLESHOOTING.md) - Common issues and solutions

---

Last Updated: 2026-06-05

