# Exchange Lab Manager

Exchange Lab Manager is a Windows Server lab utility for building and validating an isolated on-premises Exchange security sandbox. It wraps network setup, AD DS promotion, Exchange preparation, EOMT mitigation checks, and benign SMTP/OWA validation mail inside a single WinForms GUI.

Use this package only inside an isolated lab VM. Do not run it against production Exchange servers, real user mailboxes, or networks you do not administer.

## Files

- `ExchangeLabManager.ps1` - self-contained dark-mode WinForms GUI.
- `build-executable.ps1` - compiles the GUI into `.\bin\ExchangeLabManager.exe` with PS2EXE.
- `sign-executable.ps1` - creates a local self-signed lab code-signing certificate and signs the EXE.
- `build-pipeline.ps1` - one-click compile, sign, stage, and ISO packaging pipeline.
- `run-gui.bat` - double-click launcher for File Explorer.
- `run-gui.ps1` - convenience launcher for `ExchangeLabManager.ps1`.
- `qa-smoke-tests.ps1` - non-destructive GUI and helper smoke tests.
- `qa-full-tests.ps1` - full mocked QA suite for launchers, UI wiring, task handling, and operation logic.
- `exchange-lab-automation.ps1` - legacy function library retained for reference and manual testing.
- `exchange-xss-test.ps1` - standalone benign SMTP validation mail sender.

## Recommended Workflow

From a PowerShell prompt in this workspace:

```powershell
.\build-pipeline.ps1
```

The pipeline verifies required files, sets the process execution policy for the current session, compiles the GUI, signs the EXE, stages `.\dist\ExchangeLabManager.exe`, and creates `.\dist\ExchangeLabFiles.iso` for VirtualBox transfer.

### Quick Launch

For the easiest way to open the GUI, double-click `run-gui.bat` in File Explorer.

The launcher prompts for elevation when needed. If startup fails, the console stays open and shows the error instead of closing immediately. You can also run the PowerShell launcher directly from a terminal:

```powershell
.\run-gui.ps1
```

The helper launcher starts `ExchangeLabManager.ps1` with a bypass execution policy and will prompt for elevation if required.

### QA Smoke Tests

Run the non-destructive smoke test suite after making code changes:

```powershell
.\qa-smoke-tests.ps1
```

The QA script parses the PowerShell files, loads the GUI in `-NoRun` mode, builds the WinForms control tree, checks default values, and validates safe helper logic. To briefly open the GUI, cycle through every tab, and close it automatically, run:

```powershell
.\qa-smoke-tests.ps1 -RunUiLoop
```

The QA checks do not run network reconfiguration, AD DS promotion, Exchange setup, EOMT, IIS, or SMTP actions.

For broader coverage, run the full mocked QA suite:

```powershell
.\qa-full-tests.ps1
```

The full suite checks the launchers, package files, helper functions, repeated form construction, button wiring, task success/failure behavior, process logging, Exchange setup command construction, mocked network/AD DS/EOMT/IIS/SMTP operation logic, and CVE validation helpers. Add `-RunUiLoop` to briefly show the GUI and cycle every tab automatically.

The only thing this suite intentionally does not do is execute irreversible lab operations. Test those final live operations only inside a disposable, isolated Windows Server Exchange lab VM.

### Additional helper tools

- `preflight-readiness-check.ps1` - runs a readiness validation check on the host or lab VM before the GUI is launched. This helper is intended for use within a Windows Server lab VM and may report warnings on client OS environments.
- `lab-cleanup-helper.ps1` - inspects and optionally removes temporary lab artifacts, with optional network/IIS reset in full mode.
- `lab-profiles/` - contains JSON lab profile templates to capture reusable lab configuration settings.

If you want to run each step manually:

```powershell
.\build-executable.ps1
.\sign-executable.ps1
```

## Running the GUI Script Directly

On a fresh Windows Server VM, right-click `ExchangeLabManager.ps1` and choose **Run with PowerShell**. Run elevated when using network, AD DS, Exchange setup, or mitigation actions.

The GUI contains five operational views:

1. System & Network Setup
2. Exchange Prep & Install
3. Mitigation & EOMT
4. Automated XSS Test
5. CVE-2026-42897 Validation

## Lab Isolation

Recommended VirtualBox configuration:

1. Open the VM settings.
2. Select **Network**.
3. Set **Attached to** to **Internal Network**.
4. Use a lab-only network name such as `ExchangeLab`.
5. Avoid NAT, bridged, or production host-only networks for this sandbox.

## Notes on Signing

`sign-executable.ps1` creates a self-signed certificate trusted by the current user profile. This is suitable for local lab Authenticode validation. It does not create global Microsoft SmartScreen reputation; public reputation requires a publicly trusted certificate and reputation history.

## Safe Validation Payloads

The automated XSS test sends benign HTML control payloads through SMTP so you can inspect whether OWA and CSP mitigation behavior is blocking active content. The payloads are intended for isolated validation only and do not collect data or contact external systems.

## Documentation Index

Complete documentation for this project:

| Document | Purpose | Audience |
|----------|---------|----------|
| **README.md** (this file) | Overview, workflow, and QA commands | Everyone |
| **[LAB-SETUP-GUIDE.md](LAB-SETUP-GUIDE.md)** | VirtualBox configuration, VM prerequisites, step-by-step lab deployment | Lab administrators, first-time users |
| **[PREFLIGHT-CHECKLIST.md](PREFLIGHT-CHECKLIST.md)** | Pre-launch verification checklist, environment readiness validation | Before running the GUI |
| **[CVE-2026-42897-INTEGRATION.md](CVE-2026-42897-INTEGRATION.md)** | Validation tab features, usage workflows, integration details | Security teams, compliance auditors |
| **[TROUBLESHOOTING.md](TROUBLESHOOTING.md)** | Common issues, error messages, solutions, diagnostic commands | Troubleshooting problems |
| **[QA-REPORT.md](QA-REPORT.md)** | Test results, test coverage, deployment readiness | QA verification, code review |
| **[CVE-2026-42897_Defensive_Lab_Report.txt](CVE-2026-42897_Defensive_Lab_Report.txt)** | Full defensive lab documentation, vulnerability details, mitigation background | Security research, detailed reference |

### Quick Start Path
1. Start here -> **README.md** (this file)
2. -> **[PREFLIGHT-CHECKLIST.md](PREFLIGHT-CHECKLIST.md)** (verify readiness)
3. -> **[LAB-SETUP-GUIDE.md](LAB-SETUP-GUIDE.md)** (configure lab)
4. -> Launch GUI and run workflows
5. -> **[TROUBLESHOOTING.md](TROUBLESHOOTING.md)** (if issues arise)

## Improvement Roadmap

These five improvements would make Exchange Lab Manager safer, easier to repeat, and more useful as a serious lab validation tool:

1. **Lab profiles and run manifests**
   - Save and reload named lab configurations, including static IP settings, domain inputs, Exchange ISO paths, EOMT paths, SMTP targets, and test mailbox details.
   - Store profiles as JSON so the GUI and future automation entry points can share the same configuration format.
   - Export a run manifest with each lab attempt so the exact inputs used for a build or mitigation validation can be reviewed later.
   - *Status: Not yet implemented*

2. **Preflight readiness checks**
   - Add a dedicated readiness step before network, AD DS, Exchange, or mitigation actions run.
   - Check elevation, Windows Server version, required features, disk space, pending reboot state, network adapter selection, DNS state, and whether the VM appears isolated.
   - Show blocking failures separately from warnings so users can fix risky setup issues before starting long-running changes.
   - *Status: Manual checklist available in [PREFLIGHT-CHECKLIST.md](PREFLIGHT-CHECKLIST.md). GUI feature not yet implemented.*

3. **Guided workflow and resumable checkpoints**
   - Track which lab milestones are complete, such as network configured, AD DS promoted, reboot completed, Exchange AD prepared, Exchange installed, and mitigation checked.
   - Disable or warn on actions that are out of sequence, while still allowing advanced users to override when they know the lab state is valid.
   - Persist checkpoint state after each major step so the GUI can resume cleanly after required restarts.
   - *Status: Not yet implemented*

4. **Evidence bundle export**
   - Let users export a timestamped ZIP containing tab logs, build logs, mitigation status output, selected configuration metadata, validation message details, and tool versions.
   - Redact secrets and passwords before writing the bundle.
   - Include enough evidence to compare lab runs and confirm which mitigations or validation checks were actually performed.
   - *Status: Partial - CVE validation tab exports individual evidence files. Comprehensive bundle export not yet implemented.*

5. **Rollback and cleanup tools**
   - Add safer cleanup actions for temporary downloads, generated test payload files, local mitigation scripts, and lab-only IIS rewrite/CSP rules.
   - Provide network restore helpers for reverting adapter IP/DNS settings after testing.
   - Use strong confirmation prompts and checkpoint reminders before destructive or hard-to-reverse actions such as AD DS promotion and Exchange installation.
   - *Status: Not yet implemented*

---

### Documentation Improvements (Completed)
These items have been addressed through comprehensive documentation:

[done] **LAB-SETUP-GUIDE.md** - Complete VM configuration, prerequisites, and step-by-step lab deployment workflow  
[done] **PREFLIGHT-CHECKLIST.md** - Pre-launch verification checklist covering all readiness criteria  
[done] **TROUBLESHOOTING.md** - Comprehensive troubleshooting guide for common issues and error messages  
[done] **Updated README.md** - Documentation index and quick-start guide



