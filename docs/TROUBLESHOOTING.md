# Exchange Lab Manager Troubleshooting Guide

This guide addresses common issues when using Exchange Lab Manager in an isolated lab environment.

## Startup Issues

### GUI Window Doesn't Appear

**Symptom:** Script launches but no window opens.

**Possible Causes:**
1. Execution policy is blocked
2. Required .NET assemblies cannot load
3. Display/graphics adapter issue

**Solutions:**
```powershell
# Verify execution policy
Get-ExecutionPolicy

# Launch with explicit bypass
powershell -ExecutionPolicy Bypass -File ExchangeLabManager.ps1

# Run in elevated session
# Right-click PowerShell and select "Run as administrator"
```

---

### "This action requires elevated privileges"

**Symptom:** Network, AD DS, Exchange, or mitigation actions fail with permission error.

**Cause:** Actions that modify network settings, AD DS, or IIS require administrator privileges.

**Solution:**
```powershell
# Re-launch the entire GUI in elevated session
# Right-click run-gui.bat and select "Run as administrator"
# OR
# Right-click ExchangeLabManager.ps1 -> Run with PowerShell -> When prompted, allow elevated run

# Alternatively, launch from an already-elevated PowerShell:
powershell -ExecutionPolicy Bypass -File ExchangeLabManager.ps1
```

---

### "The term 'GetExchangeServer' is not recognized"

**Symptom:** CVE validation tab reports this error when checking mitigation state.

**Cause:** CVE functions require Exchange Management Shell or modules loaded.

**Solution:**
1. Run the GUI from an **Exchange Management Shell** session (not a regular PowerShell)
2. Or run the GUI on a machine with Exchange installed
3. For remote validation, ensure Exchange Admin Center or remote PowerShell connectivity is available

---

## Network Setup Issues

### "Cannot bind to IP address"

**Symptom:** Network configuration fails when setting static IP.

**Cause:** 
- IP address already in use on lab network
- Network adapter not connected
- Invalid subnet mask

**Solutions:**
```powershell
# Check current adapters and IP assignments
Get-NetAdapter
Get-NetIPAddress

# Verify the static IP is not in use
Test-NetConnection -ComputerName 192.168.100.10 -InformationLevel "Detailed"

# Check lab network isolation in VirtualBox
# Settings -> Network -> Ensure "Internal Network" is selected
```

---

### "Cannot reach gateway after network setup"

**Symptom:** Lab VM cannot reach 192.168.100.1 (or configured gateway).

**Cause:**
- Another VM is not running
- VirtualBox Internal Network is misconfigured
- Firewall is blocking ICMP

**Solutions:**
```powershell
# Verify network isolation in VirtualBox
# Each lab VM must have:
# - Network attached to "Internal Network"
# - Same internal network name (e.g., "ExchangeLab")
# - No bridging or NAT

# Test connectivity after configuration
Test-NetConnection -ComputerName 192.168.100.1
Get-NetRoute | Where-Object { $_.DestinationPrefix -like '192.168.100.*' }
```

---

## AD DS Promotion Issues

### "AD DS promotion failed"

**Symptom:** AD DS installation or promotion returns error.

**Cause:**
- Required Windows features not installed
- Invalid domain name format
- Insufficient disk space

**Solutions:**
```powershell
# Verify Windows Server version and features
Get-WindowsFeature | Where-Object { $_.Name -like '*AD*' }

# Check available disk space
Get-Volume

# Verify domain name is valid (no special characters beyond hyphens)
# Valid: mylab.local, corp-lab.local
# Invalid: my lab.local, mylab.local!, my@lab.local

# Ensure time sync is good (AD requires < 5 minute clock skew)
Get-Date
```

---

### "DNS cannot resolve domain after promotion"

**Symptom:** Other lab VMs cannot find the DC-promoted server.

**Cause:**
- DNS forwarders are pointing to external DNS
- Lab VMs are not using the lab DNS server

**Solutions:**
```powershell
# On the DC VM, verify DNS config
Get-DnsServer
Get-DnsServerForwarder

# On client VMs, point to the DC's IP for DNS
# Network Settings -> Advanced -> DNS
# Use the DC's IP (e.g., 192.168.100.10)

# Or set DNS via PowerShell on client VM:
$dcIp = '192.168.100.10'
Set-DnsClientServerAddress -InterfaceAlias Ethernet -ServerAddresses $dcIp
```

---

## Exchange Setup Issues

### "ExSetup.exe not found"

**Symptom:** Exchange preparation or installation fails immediately.

**Cause:**
- ISO not mounted or path is incorrect
- ISO is corrupted
- Drive letter changed

**Solutions:**
```powershell
# Verify the Exchange ISO is mounted
Get-Volume | Where-Object { $_.DriveType -eq 'CD-ROM' }

# Check if the specified path exists
Test-Path D:\setup.exe
Test-Path D:\ExSetup.exe

# If volume letter changed, update the default in GUI
# Or provide full path in the Exchange path field before clicking install

# Verify ISO integrity (if available from Microsoft)
# Get-FileHash D:\setup.exe -Algorithm SHA256
```

---

### "Exchange setup prerequisites not met"

**Symptom:** Setup exits with "This role cannot be installed on this computer."

**Cause:**
- Windows Server version mismatch
- Required Windows features not installed
- AD Schema/Org prep not complete
- Insufficient disk space

**Solutions:**
```powershell
# Verify Windows Server version matches Exchange minimum requirements
[System.Environment]::OSVersion

# Ensure AD DS forest/domain prep completed successfully
# Check if you can see the domain in AD Users and Computers

# Check disk space (Exchange needs ~20GB+ free)
Get-Volume
dir D:\  # or the target volume

# Run the GUI's "Prepare Exchange" step if not yet done
# This runs Schema and Org prep before Install
```

---

### "Exchange installation hangs at 'Finalizing Setup'"

**Symptom:** Setup progress bar stalls and remains at 95%+ for extended time.

**Cause:**
- Disk I/O bottleneck
- Exchange waiting for service to start
- Background process contention

**Solution:**
```powershell
# Wait up to 30 minutes (Exchange finalization can be slow)
# Monitor Task Manager > Processes for setup.exe activity

# If truly hung after 45+ minutes:
# 1. Do NOT force-kill setup.exe (will corrupt installation)
# 2. Shut down the entire VM gracefully
# 3. Check logs in %ProgramFiles%\Microsoft\Exchange Server\V15\Logging
# 4. Consider expanding VM disk/RAM if setup was slow

# After restart, check if Exchange is partially installed:
Get-ExchangeServer
```

---

## Mitigation & EOMT Issues

### "EOMT script download failed"

**Symptom:** EOMT tab shows "Failed to download EOMT script."

**Cause:**
- Internet connectivity lost
- Microsoft's EOMT URL changed or is unreachable
- Proxy/firewall blocking HTTPS

**Solutions:**
```powershell
# Verify connectivity to Microsoft
Test-NetConnection -ComputerName aka.ms -Port 443

# Test the EOMT URL directly
Invoke-WebRequest -Uri 'https://aka.ms/exchange-onprem-mitigation-tool' -UseBasicParsing

# Check for proxy settings
[System.Net.ServicePointManager]::DefaultProxy

# If proxy required, configure it:
# This requires modifying the GUI's Invoke-WebRequest calls to include -Proxy parameter
```

---

### "EOMT script execution failed"

**Symptom:** EOMT runs but exits with error or without applying mitigation.

**Cause:**
- Insufficient permissions (needs local admin)
- Exchange Management Shell not available
- IIS not installed
- Pre-existing IIS rule conflicts

**Solutions:**
```powershell
# Ensure running in Exchange Management Shell with elevation
# Or ensure Exchange cmdlets are loaded:
# Add-PSSnapin Microsoft.Exchange.Management.PowerShell.SnapIn

# Verify IIS is installed
Get-WindowsFeature | Where-Object { $_.Name -like '*IIS*' }

# Check for conflicting IIS rules
Import-Module WebAdministration
Get-WebConfiguration -PSPath 'IIS:\Sites\Default Web Site\owa' -Filter 'system.webServer/rewrite/outboundRules/rule' |
  Select-Object -Property name, enabled, preCondition

# EOMT should not fail due to conflicts-review EOMT logs for details
dir $env:TEMP\*EOMT* | Sort-Object LastWriteTime -Descending | Select-Object -First 5
```

---

### "CSP header not found after applying EOMT"

**Symptom:** CVE validation tab "Verify CSP Header" reports no header or incomplete header.

**Cause:**
- Mitigation was not applied successfully
- IIS cache not cleared
- OWA virtual directory not updated
- Browser cache showing old response

**Solutions:**
```powershell
# Force IIS cache clear
iisreset /restart

# Wait 5 minutes for EM service to refresh (if using EM service)

# Check IIS rewrite rules directly
Import-Module WebAdministration
Get-WebConfiguration -PSPath 'IIS:\Sites\Default Web Site\owa' -Filter 'system.webServer/rewrite/outboundRules/rule' |
  Where-Object { $_.name -match 'CSP|OWA' } | Format-List

# Verify OWA is responding
Invoke-WebRequest -Uri 'https://lab-ex01.exchange-lab.test/owa' -UseBasicParsing |
  Select-Object -ExpandProperty Headers | Where-Object { $_.Key -match 'Content-Security' }

# Clear browser cache and try again in a private/incognito window
```

---

## XSS Test Issues

### "SMTP send failed"

**Symptom:** Automated XSS test fails to send email.

**Cause:**
- SMTP server not responding
- Invalid recipient address
- Sender not authorized
- Firewall blocking SMTP

**Solutions:**
```powershell
# Verify Exchange SMTP service is running
Get-Service | Where-Object { $_.Name -like '*SMTP*' }

# Test SMTP connectivity
Test-NetConnection -ComputerName mail.lab.local -Port 25
Test-NetConnection -ComputerName lab-ex01.exchange-lab.local -Port 25

# Check the configured SMTP target in the GUI (default: mail.lab.local)

# Verify sender address format
# Should be user@domain.local format

# Check Exchange transport logs
dir "C:\Program Files\Microsoft\Exchange Server\V15\Logging\SMTP*" |
  Sort-Object LastWriteTime -Descending | Select-Object -First 3
```

---

### "Test email not arriving in target mailbox"

**Symptom:** SMTP send succeeds but email does not appear in Inbox.

**Cause:**
- Routing broken
- Target mailbox doesn't exist
- Message rejected by transport rules
- Stuck in queue

**Solutions:**
```powershell
# Verify test mailbox exists and is accessible
Get-Mailbox -Identity testuser@mylab.local

# Check Exchange queue for stuck messages
Get-Queue | Where-Object { $_.MessageCount -gt 0 }

# Review message tracking logs
Search-MessageTrackingReport -Identity "TestMessageId" -TraceEnabled $true

# Check for transport rules rejecting messages
Get-TransportRule | Select-Object Name, Enabled | Where-Object { $_.Enabled -eq $true }

# For immediate testing, create a new test mailbox
New-Mailbox -Name "LabTest" -Alias "labtest" -UserPrincipalName "labtest@mylab.local"
```

---

## CVE-2026-42897 Validation Issues

### "MSExchangeMitigation service not found"

**Symptom:** CVE tab "Check EM Service" reports service doesn't exist.

**Cause:**
- Not running on an Exchange server
- EM service not installed
- Service name incorrect

**Solution:**
```powershell
# Run checks from an Exchange server, or ensure Exchange modules are loaded
Get-Service MSExchangeMitigation

# If service doesn't exist, EM service may not be installed
# Use EOMT to apply mitigation instead
```

---

### "No obvious IIS CSP outbound rewrite rule was found"

**Symptom:** Mitigation state check reports no CSP rule detected.

**Cause:**
- EOMT not yet applied
- EM service not yet refreshed (10-minute delay)
- IIS cache needs clear

**Solutions:**
```powershell
# Wait 10 minutes for EM service sync

# Or manually apply EOMT if EM service is not running

# Clear IIS cache
iisreset /restart

# Check if rule exists with different name
Import-Module WebAdministration
Get-WebConfiguration -PSPath 'IIS:\Sites\Default Web Site\owa' -Filter 'system.webServer/rewrite/outboundRules/rule' |
  Select-Object name, enabled | Format-Table -AutoSize
```

---

### "Evidence export access denied"

**Symptom:** "Export Evidence Bundle" fails with "Access Denied."

**Cause:** Insufficient permissions to create directory in %TEMP%.

**Solution:**
```powershell
# Run GUI in elevated session
# Right-click run-gui.bat or PowerShell and select "Run as administrator"

# Verify %TEMP% exists and is writable
Test-Path $env:TEMP
Get-Item $env:TEMP | Get-Acl
```

---

## General Troubleshooting

### GUI is slow or unresponsive

**Cause:**
- VM doesn't have enough RAM allocated
- Disk is slow or fragmented
- Network operations hanging
- Background antivirus scan running

**Solutions:**
```powershell
# Check VM resource allocation
Get-VM "LabVMName" | Select-Object MemoryAssigned, ProcessorCount

# Monitor resource usage during operations
Get-Process powershell | Select-Object Id, Name, WorkingSet, CPU

# Check for antivirus exclusions
# Add: %ProgramFiles%\Microsoft\Exchange Server
# Add: C:\Program Files\IIS
```

---

### "An error occurred and the GUI closed"

**Symptom:** GUI exits unexpectedly without error message.

**Cause:**
- Unhandled exception in PowerShell script
- Out of memory
- Critical system error

**Solution:**
```powershell
# Re-run with error output visible:
powershell -ExecutionPolicy Bypass -File ExchangeLabManager.ps1 -ErrorAction Stop

# Check Windows Event Viewer for critical errors:
# Event Viewer > Windows Logs > System
# Filter by PowerShell events

# Check %TEMP% for any error logs created by the GUI
dir $env:TEMP | Where-Object { $_.Name -match 'exchange|error|lab' } | Sort-Object CreationTime -Descending
```

---

## Getting Help

If issues persist:

1. **Collect evidence** using the CVE tab's "Export Evidence Bundle"
2. **Check logs** in:
   - `%ProgramFiles%\Microsoft\Exchange Server\V15\Logging\`
   - `%SystemRoot%\System32\LogFiles\`
   - `%TEMP%\` (for EOMT and script output)
3. **Review this guide** for similar symptoms
4. **Consult Microsoft Learn** for Exchange-specific issues:
   - https://learn.microsoft.com/en-us/exchange/
   - CVE-2026-42897 mitigation guidance
5. **Check the QA report** in `docs/QA-REPORT.md` for known test results

---

Last Updated: 2026-06-05

