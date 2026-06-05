# Exchange Lab Manager - Detailed Usage Guide

This guide provides a comprehensive walkthrough for using the Exchange Lab Manager GUI and troubleshooting common issues.

## GUI Walkthrough

The GUI is organized into tabs that follow a logical lab deployment and validation milestone order.

### 1. Profiles & Preflight
- **Load/Save Profile**: Manage your lab configurations (IPs, domain, ISO paths) as JSON files.
- **Run Preflight Check**: Mandatory first step. Verifies elevation, OS version, disk space, and network isolation.
- **Save Checkpoint**: Persists your current milestone progress so you can resume after reboots.
- **Export Full Evidence Bundle**: Generates a timestamped ZIP with all logs, manifests, and validation evidence.

### 2. System & Network Setup
- **Configure Network**: Sets static IP, mask, and DNS. **DESTRUCTIVE**: Backs up current config to `%LOCALAPPDATA%\ExchangeLabManager\backups` before applying changes.
- **Install Active Directory & Promote**: Installs the AD DS role and promotes the server to a new forest. **DESTRUCTIVE**: Requires a reboot.

### 3. Exchange Prep & Install
- **Prepare AD Schema & Forests**: Runs `setup.exe /PrepareSchema` and `/PrepareAD`.
- **Launch Exchange Installer**: Starts the full Mailbox role installation. This can take 30-60 minutes depending on hardware.

### 4. Mitigation & EOMT
- **Download & Apply EOMT**: Fetches Microsoft's Exchange On-Premises Mitigation Tool and applies interim rewrite rules.
- **Check Status**: Queries IIS directly for the presence of CSP-style outbound rewrite rules.

### 5. Benign HTML Validation Test
- **Send HTML Validation Mail**: Sends a benign email containing a control payload (e.g., `<script>alert('test')</script>`) to verify if the OWA Content Security Policy (CSP) correctly blocks inline execution.

### 6. CVE-2026-42897 Validation
- **Check Exchange Build**: Confirms if the installed build is subject to CVE-2026-42897.
- **Check EM Service**: Verifies the MSExchangeMitigation service is healthy.
- **Verify CSP Header**: Directly queries the OWA endpoint to confirm the `script-src-attr 'none'` header is active.

---

## Preflight Check Reference

| Check | Meaning | How to Fix Failure |
|-------|---------|--------------------|
| **Administrator privileges** | Required for system changes. | Restart PowerShell or `run-gui.bat` as Administrator. |
| **Windows Server edition** | Tool is optimized for Server OS. | Run inside the target lab VM, not on your host machine. |
| **Network isolation** | Verifies no reachability to 8.8.8.8. | Set VirtualBox adapter to "Internal Network". |
| **Static IP input** | Validates IP format. | Correct the IP address in the System tab. |
| **Pending reboot** | Checks for CBS/WU reboot markers. | Restart the VM before proceeding with AD or Exchange. |

---

## Lab Profiles and Recovery

### Loading and Saving Profiles
Profiles are stored in `%LOCALAPPDATA%\ExchangeLabManager\profiles`. You can manually edit these JSON files or use the GUI to update them.

### Dry-Run Mode (Planned)
While a full dry-run mode is planned, you can currently use the **Cleanup Preview** button to see what temporary files would be removed without actually deleting them.

### Network Recovery
If network configuration breaks:
1. Navigate to `%LOCALAPPDATA%\ExchangeLabManager\backups`.
2. Locate the latest `network-backup-YYYYMMDD-HHMMSS.json`.
3. Use the `Restore-NetworkConfiguration` function in [ExchangeLabManager.ps1](file:///c:/dev/testing/ExchangeLabManager.ps1) via PowerShell CLI to revert settings.

---

## Evidence Bundles
The **Export Full Evidence Bundle** button creates a ZIP in `%TEMP%` containing:
- `00-Bundle-Metadata.json`: System info and timestamps.
- `01-Current-Inputs.json`: Your GUI input values.
- `02-Checkpoint.json`: Milestone completion status.
- `logs/`: All tab logs (System, Exchange, Mitigation, etc.).
- `cve-validation/`: Specific evidence for CVE mitigation status.

---

## Troubleshooting Common Failures

### 1. Exchange Install Fails
- **Cause**: Often due to missing prerequisites or insufficient disk space.
- **Fix**: Review the `ExchangeLog.txt` in the evidence bundle. Ensure all features from [PREFLIGHT-CHECKLIST.md](file:///c:/dev/testing/docs/PREFLIGHT-CHECKLIST.md) are installed.

### 2. EM Service Not Running
- **Cause**: The MSExchangeMitigation service may fail to start if it can't reach Microsoft for mitigation updates.
- **Fix**: Ensure the service is set to "Automatic" and check `MSExchangeMitigation-Service.txt` in the evidence bundle.

### 3. EOMT Rule Not Appearing in IIS
- **Cause**: EOMT may have exited with an error or the IIS configuration hasn't refreshed.
- **Fix**: Run `iisreset /restart` and re-run the "Check Status" task.

### 4. CSP Header Not Present in OWA Response
- **Cause**: Outbound rewrite rules are active but the OWA virtual directory isn't being correctly processed.
- **Fix**: Verify the OWA URL in the GUI matches the internal hostname used in the certificate.

### 5. QA Tests Failing
- **Cause**: Mismatched paths or environment variables.
- **Fix**: Ensure you are running [qa-full-tests.ps1](file:///c:/dev/testing/qa-full-tests.ps1) from the root of the repository.
