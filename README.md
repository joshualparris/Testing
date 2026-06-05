# Exchange Lab Manager

Documentation for this repository is located in the `docs/` directory.

Open `docs/README.md` for setup, usage, QA commands, roadmap notes, and supported helper tools.

## Included tools

- `ExchangeLabManager.ps1` - self-contained WinForms GUI for lab deployment and validation.
- `build-executable.ps1` - compiles the GUI into `./bin/ExchangeLabManager.exe` using PS2EXE.
- `sign-executable.ps1` - creates a local self-signed code-signing certificate and signs the executable.
- `build-pipeline.ps1` - one-click compile, sign, stage, and ISO packaging pipeline.
- `run-gui.bat` / `run-gui.ps1` - GUI launchers.
- `qa-smoke-tests.ps1` - non-destructive GUI and helper smoke tests.
- `qa-full-tests.ps1` - full mocked QA suite.
- `preflight-readiness-check.ps1` - verifies host/VM readiness before launch.
- `lab-cleanup-helper.ps1` - removes temporary lab artifacts and optionally resets network/IIS.
- `lab-profiles/` - JSON lab profile templates for reusable lab configuration manifests.
