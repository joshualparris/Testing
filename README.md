# Exchange Lab Manager

A defensive, isolated lab manager for validating Microsoft Exchange OWA security mitigations in a sandboxed VirtualBox environment.

PowerShell 5.1+ | Windows Server 2022 | Defensive Lab Only | No Exploit Content

## What this tool does

- **Automates setup** of an isolated AD + Exchange lab in VirtualBox.
- **Guides the user** through DC01, EX01, and CLIENT01 configuration.
- **Validates** Microsoft Exchange Emergency Mitigation (EM) service status.
- **Verifies** EOMT URL Rewrite rules on the OWA virtual directory.
- **Confirms** Content-Security-Policy (CSP) headers in OWA HTTP responses.
- **Exports** a structured evidence bundle for audit or portfolio use.
- **Provides** safe functional smoke tests for OWA after mitigation.

## What this tool does NOT do

- **Does not reproduce** CVE-2026-42897 or any other exploit.
- **Does not include** malicious payloads, session theft, MFA bypass, or credential harvesting.
- **Does not modify** production systems.
- **Does not connect** to external networks during CVE testing.
- **Is not a replacement** for Microsoft's official security updates.

## Safety Boundary Statement

> [!IMPORTANT]
> **This tool is for isolated, defensive lab use only.** It must not be run on production systems, work-managed devices, or any machine with external network access during CVE testing. All destructive actions (network reconfiguration, AD DS promotion, Exchange installation) require explicit confirmation.

## Recommended Hardware

- **Minimum**: 8GB RAM (AD + client only), 60GB free storage.
- **Recommended**: 16GB+ RAM (full Exchange lab), 120GB+ free storage.
- **Software**: VirtualBox 7.x.
- *Note for low-RAM machines*: Use the AD-only lab path (DC01 + CLIENT01) and defer Exchange installation to stronger hardware.

## Quick Start

### Path A: AD-only Lab (Low RAM)
1. Build **DC01** on a VirtualBox Internal Network (`JoshLab-Internal`).
2. Build **CLIENT01** and join it to the domain.
3. Run the GUI's **Preflight Check** to confirm AD health.
4. Use **Evidence Export** for AD-only validation.

### Path B: Full Exchange Lab
1. Complete Path A first.
2. Build **EX01** as a separate member server.
3. Install Exchange prerequisites and **Exchange SE**.
4. Run **Mitigation Checks** via the GUI.
5. Export the **Evidence Bundle** for full validation.

## Included Tools

- [ExchangeLabManager.ps1](file:///c:/dev/testing/ExchangeLabManager.ps1): The main WinForms GUI for managing the lab workflow.
- [build-pipeline.ps1](file:///c:/dev/testing/build-pipeline.ps1): One-click script to compile, sign, and package the tool into an ISO.
- [run-gui.bat](file:///c:/dev/testing/run-gui.bat): A convenience launcher that handles elevation and STA mode.
- [preflight-readiness-check.ps1](file:///c:/dev/testing/preflight-readiness-check.ps1): Standalone script to verify host and VM readiness.
- [qa-full-tests.ps1](file:///c:/dev/testing/qa-full-tests.ps1): Comprehensive test suite covering UI, logic, and persistence.
- [lab-cleanup-helper.ps1](file:///c:/dev/testing/lab-cleanup-helper.ps1): Tool for removing temporary artifacts and resetting lab state.

## Lab Network Layout

| VM | Role | IP | Network |
|----|------|----|---------|
| **DC01** | Domain Controller | 10.10.10.10 | JoshLab-Internal (Isolated) |
| **CLIENT01** | Windows Client | 10.10.10.20 | JoshLab-Internal (Isolated) |
| **EX01** | Exchange Server | 10.10.10.30 | JoshLab-Internal (Isolated) |

## QA and Testing

### Smoke Tests
Run [qa-smoke-tests.ps1](file:///c:/dev/testing/qa-smoke-tests.ps1) to verify basic UI functionality and script integrity without performing destructive actions.
```powershell
.\qa-smoke-tests.ps1 -RunUiLoop
```

### Full Tests
Run [qa-full-tests.ps1](file:///c:/dev/testing/qa-full-tests.ps1) for a deep dive into mocked operations, profile management, and evidence export logic.

**What the tests cover**: UI wiring, task handling, manifest generation, and logic validation.
**What they do NOT do**: Execute irreversible lab operations (AD promotion, actual Exchange install).

## Build and Packaging

1. **Compile**: Use [build-executable.ps1](file:///c:/dev/testing/build-executable.ps1) to create `ExchangeLabManager.exe`.
2. **Sign**: Use [sign-executable.ps1](file:///c:/dev/testing/sign-executable.ps1) to apply a local self-signed certificate.
3. **Pipeline**: Run [build-pipeline.ps1](file:///c:/dev/testing/build-pipeline.ps1) to automate the entire build-to-ISO process.

## Known Limitations

- **Resource Intensive**: Exchange is heavy; 8GB RAM is insufficient for a full three-VM lab.
- **Interim Mitigations**: As of June 2026, this tool validates interim mitigations (CSP/Rewrite) for CVE-2026-42897.
- **IIS Detection**: The official Health Checker may not detect outbound rewrite rules; this tool queries IIS directly.
- **STA Mode**: The WinForms GUI requires Single Threaded Apartment mode; always use the provided launchers.

## Links

- [Microsoft Exchange Emergency Mitigation Service](https://learn.microsoft.com/en-us/exchange/plan-and-deploy/post-installation-tasks/security-best-practices/exchange-emergency-mitigation-service)
- [Microsoft CSS-Exchange GitHub](https://github.com/microsoft/CSS-Exchange)
- [CISA KEV Catalogue](https://www.cisa.gov/known-exploited-vulnerabilities-catalog)
- [OWASP XSS Prevention Cheat Sheet](https://cheatsheetseries.owasp.org/cheatsheets/Cross_Site_Scripting_Prevention_Cheat_Sheet.html)
- [MDN CSP script-src-attr](https://developer.mozilla.org/en-US/docs/Web/HTTP/Headers/Content-Security-Policy/script-src-attr)

---
*Note: This repository was formerly known as "Testing". Documentation references are being updated to reflect the new name: Exchange Lab Manager.*
