# Exchange Lab Manager QA Report

## Executive Summary

Comprehensive non-destructive QA testing has been completed for Exchange Lab Manager, including the CVE-2026-42897 validation features. The current smoke and full mocked QA suites pass successfully.

This report approves the app for isolated lab validation workflows only. It does not approve use against production Exchange servers, production mailboxes, or networks outside the administrator's explicit test scope.

## Test Coverage

### Smoke Tests

- Script parsing for package PowerShell files.
- GUI loading in `-NoRun` mode.
- Helper logic for subnet masks, gateway derivation, argument quoting, Exchange setup path validation, and SMTP input validation.
- WinForms construction for all six tabs.
- Default control values and visible button labels.
- Optional visible UI event loop that cycles through all six tabs.

### Full Mocked QA Suite

- Package structure and launcher file checks.
- Form construction and repeated construction reset behavior.
- Button wiring for all task buttons.
- Task success, failure, progress, logging, status pill, and button re-enable behavior.
- JSON lab profile save/load behavior.
- Run manifest export behavior.
- Resumable checkpoint update/reset behavior.
- GUI cleanup preview behavior.
- Comprehensive evidence bundle creation.
- Process logging and non-zero process exit handling.
- Exchange setup command construction.
- Mocked network, AD DS, Exchange setup, EOMT, IIS mitigation, SMTP, CSP, and evidence export logic.
- CVE validation helpers:
  - `Get-ExchangeBuildInfo`
  - `Check-EmServiceStatus`
  - `Get-MitigationApplied`
  - `Verify-OwaCspHeader`
  - `Export-CveEvidence`
- Launcher failure handling when the GUI script is missing.

### Implemented Roadmap Coverage

- Lab Control & Evidence tab for profiles, manifests, checkpoints, preflight, full evidence export, and cleanup preview.
- Automatic checkpoint and run-manifest recording after successful task-runner operations.
- Full evidence ZIP export containing app metadata, current inputs, checkpoint state, embedded run manifest, preflight results, UI logs, and CVE/Exchange validation snapshots.

## Bugs Found and Fixed

### Startup UI Construction Failure

The app previously failed during startup with a WinForms `.Text` property error caused by a PowerShell variable-name collision in UI section construction. The section builder was corrected and startup is now covered by `-NoRun` and WinForms construction tests.

### Task Runner Failure

The previous `BackgroundWorker` event registration path was unreliable under Windows PowerShell. Task execution was changed to a UI-safe task runner that reports progress, resets state, and handles success/failure consistently.

### Process Output Handling

Process output capture was made safer by collecting stdout and stderr before reporting lines back to the UI. This avoids fragile cross-thread UI updates while preserving process logs.

### Global UI State Leakage

Repeated form construction could accumulate stale button references. `New-MainForm` now resets UI state and the button registry each time a form is built.

## Current QA Commands

```powershell
.\qa-smoke-tests.ps1
.\qa-smoke-tests.ps1 -RunUiLoop
.\qa-full-tests.ps1
.\qa-full-tests.ps1 -RunUiLoop
.\ExchangeLabManager.ps1 -NoRun
```

## Latest Validation Status

- Smoke suite: passed
- Smoke suite with visible UI loop: passed
- Full mocked QA suite: passed
- Full mocked QA suite with visible UI loop: passed
- Direct `-NoRun` startup check: passed

## Remaining Manual Validation

The following operations are intentionally not run by local QA and must only be tested inside a disposable, isolated Exchange lab VM:

- Network adapter reconfiguration.
- AD DS installation and forest promotion.
- Exchange setup and schema preparation.
- Live EOMT execution.
- Live IIS mitigation changes.
- Real SMTP delivery to Exchange mailboxes.
- Real OWA login, send, reply, and browser CSP behavior checks.

## Recommendations

1. Keep `qa-smoke-tests.ps1` and `qa-full-tests.ps1` as the default pre-change and post-change validation commands.
2. Run the manual lab-only validation list after building a fresh isolated Exchange VM.
3. Treat live AD DS, Exchange, EOMT, IIS, SMTP, and OWA checks as manual isolated-lab validation, even though the GUI scaffolding and mocked QA coverage are now in place.

Report generated: 2026-06-05  
Application: Exchange Lab Manager  
QA status: passed for non-destructive and mocked validation
