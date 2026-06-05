# Exchange Lab Manager - Improvement Plan

## Phase 1: Security & Safety (CRITICAL)

### Issues Flagged:
1. **Hardcoded password on line 1183**: `P@ssw0rd!LabOnly`
   - Risk: Credentials in plain text in script and logs
   - Fix: Use `Read-Host -AsSecureString` with random lab password generator
   
2. **Attacker/Victim naming convention**
   - Issue: Implies exploit testing rather than defensive validation
   - Fix: Rename to Sender/Recipient or ControlAccount/TestAccount
   
3. **"XSS Test" terminology**
   - Issue: Misleading - suggests testing for vulnerabilities rather than validating defenses
   - Fix: Rename to "Benign HTML/CSP Control Test" or "HTML Control Validation Test"
   
4. **No first-run safety warning**
   - Risk: User may casually run destructive actions
   - Fix: Add prominent warning on GUI startup for non-server OS
   
5. **No confirmation prompts before destructive actions**
   - Risk: Accidental network reconfiguration, AD promotion, Exchange setup
   - Fix: Add confirmation dialogs for all destructive operations
   
6. **No network adapter picker**
   - Risk: Modifies first adapter automatically without user choice
   - Fix: Add dropdown/list selector for network adapters before changes
   
7. **No network configuration backup**
   - Risk: User cannot easily restore previous settings
   - Fix: Export network config to JSON before any changes; add restore function
   
8. **No secret redaction in logs/exports**
   - Risk: Passwords/tokens might appear in log files and evidence bundles
   - Fix: Add redaction helper for logs and export filters

## Phase 2: Defensive-Only CVE/OWA Validation

### Required Changes:
1. Rename XSS tab and controls to "HTML/CSP Control Test"
2. Rename Attacker → Sender/ControlAccount
3. Rename Victim → Recipient/TestAccount
4. Update milestone labels to use neutral terms
5. Add warning text: "This validates defensive controls, not exploitability"
6. Ensure payload dropdown shows only benign/fixed payloads - NO arbitrary payload entry
7. Update documentation to clarify: safe lab only, defensive validation, no exploit reproduction

## Phase 3: Architecture & Code Quality

### Opportunities (not required for this pass):
- Script is 1658 lines - could be refactored into modules but is manageable as-is
- Core functions are well-organized
- Recommend deferring full modularization until next major version
- Focus on fixing issues within existing structure

## Phase 4: GUI/UX Improvements

### High Priority:
1. Add prominent "Lab Mode Indicator" at top showing: Safe-Only / Lab-Mode / Isolated-VM
2. Add warning box for non-Server OS
3. Add warning if external network is reachable
4. Disable dangerous buttons until preflight passes
5. Add confirmation dialogs for destructive operations
6. Add adapter picker before network changes
7. Improve button naming (e.g., "Launch Exchange Installer Syntax" → "Run Exchange Install")

### Medium Priority:
1. Add tooltips for all buttons and input fields
2. Add "Copy Command Only" buttons
3. Improve status messages for beginners
4. Add guided workflow sidebar (optional - may defer)

## Phase 5: Preflight & Validation

### Improvements:
1. Expand checks (already mostly complete):
   - RAM amount
   - Disk free space (already done)
   - Pending reboot (already done)
   - Network adapters list
   - Internet reachability (already done)
   - VirtualBox detection
   - Exchange already installed
   - Server is DC before Exchange install
   - AD DS tools available
   - DNS resolution
   - IIS/WebAdministration available

2. Classify results as PASS/WARN/BLOCK (already done)
3. Block destructive actions if BLOCK results exist (already done)

## Phase 6: Lab Profiles & Checkpoints

### Improvements:
1. Add schema versioning to profiles (already exists as version 1)
2. Create additional example profiles:
   - `ad-only-internal-network.json`
   - `ad-client-hostonly.json`
   - `exchange-lab-internal-network.json`
   - `evidence-only-existing-exchange.json`
3. Add profile validation before save
4. Add checklist view showing completion status
5. Ensure manifests never include secrets ✓ (already safe)

## Phase 7: Documentation

### Updates Required:
1. Update main README.md with safety warnings
2. Update docs/README.md with complete feature list
3. Add "What This Tool Does" / "What This Tool Does NOT Do"
4. Add "Safe Lab Only" warning prominently
5. Add recommended beginner path
6. Add warnings about work/managed devices
7. Add low-resource ("ThinkPad Mode") guidance
8. Add recovery procedures (restore network settings)
9. Add dry-run/show-commands guidance
10. Add known limitations

## Phase 8: Testing

### Test Enhancements:
1. Add PSScriptAnalyzer linting
2. Add specific tests for:
   - No passwords in logs
   - No passwords in exported JSON
   - Confirmation dialogs work
   - Network restore functionality
3. Update existing tests to use new terminology
4. Add GitHub Actions CI (optional - may defer)

## Implementation Priority:
1. **CRITICAL** (Phase 1): Security & Safety fixes - must complete before push
2. **HIGH** (Phase 2): Rename XSS/Attacker/Victim terminology
3. **HIGH** (Phase 4a): Confirmation dialogs and adapter picker
4. **HIGH** (Phase 7): Documentation updates
5. **MEDIUM** (Phase 4b): GUI improvements (tooltips, labels, warnings)
6. **MEDIUM** (Phase 5): Expand preflight checks
7. **MEDIUM** (Phase 6): Add example profiles
8. **LOW** (Phase 8): Test enhancements

## Estimated Work:
- Security/Safety: 2-3 hours
- Terminology: 1 hour
- GUI Improvements: 2 hours
- Documentation: 2 hours
- Testing: 1 hour
- Total: ~9 hours of comprehensive improvement

## Safety Boundary (Non-Negotiable):
✓ NO exploit payloads for CVE-2026-42897
✓ NO OWA exploit reproduction steps
✓ NO credential theft functionality
✓ NO session theft
✓ NO MFA bypass
✓ NO persistence mechanisms
✓ NO real attacker workflows
✓ NO external callbacks
✓ Defensive validation ONLY
