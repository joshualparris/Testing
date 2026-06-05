# Contributing to Exchange Lab Manager

Thank you for considering a contribution to Exchange Lab Manager. This project is a personal portfolio and defensive lab manager designed for security researchers and lab administrators.

## Safety Boundary (HARD LIMIT)

Contributors must **NEVER** add the following to this repository:
- Exploit code for CVE-2026-42897 or any other vulnerability.
- Malicious payloads, credential harvesters, or session theft scripts.
- Functionality designed to bypass security controls.
- Tools for attacking production systems.

Any pull request containing offensive content will be rejected and reported if necessary.

## Getting Started

1. **Fork the repository** and create your branch from `main`.
2. **Set up your lab environment** following the [LAB-SETUP-GUIDE.md](file:///c:/dev/testing/docs/LAB-SETUP-GUIDE.md).
3. **Run the existing tests** before making any changes.

## Running Tests

Before submitting a pull request, ensure all tests pass:

```powershell
# Run smoke tests
.\qa-smoke-tests.ps1

# Run full mocked tests
.\qa-full-tests.ps1
```

If you've modified the GUI, run the tests with the `-RunUiLoop` flag to verify the UI tree builds correctly:
```powershell
.\qa-full-tests.ps1 -RunUiLoop
```

## Commit Message Convention

We use a simplified version of Conventional Commits:
- `feat:` New functionality (e.g., `feat: add support for Exchange 2016`)
- `fix:` Bug fixes (e.g., `fix: resolve IP parsing error`)
- `docs:` Documentation changes (e.g., `docs: update setup guide`)
- `test:` Adding or updating tests (e.g., `test: add unit test for profile saving`)

## Reporting Bugs

- Use the GitHub Issues tracker to report bugs.
- Include the **Run Manifest** or **Evidence Bundle** (with secrets redacted) if possible.
- Describe the exact steps to reproduce the issue in an isolated lab environment.

## Portfolio Project Note

Please note that this is a personal portfolio project. While I welcome contributions, the primary goal is to maintain a clean, professional, and defensive-focused codebase for lab validation.
