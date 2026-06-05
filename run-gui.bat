@echo off
setlocal
REM Launch Exchange Lab Manager GUI from the repository root.
pushd "%~dp0" || (
    echo Unable to open launcher directory: %~dp0
    pause
    exit /b 1
)

powershell.exe -NoProfile -ExecutionPolicy Bypass -STA -File "%~dp0run-gui.ps1" -PauseOnError
set "exitCode=%ERRORLEVEL%"
popd

if not "%exitCode%"=="0" (
    echo.
    echo Exchange Lab Manager launcher failed with exit code %exitCode%.
    pause
)

exit /b %exitCode%
