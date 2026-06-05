#requires -version 5.1
<#
.SYNOPSIS
    Builds ExchangeLabManager.ps1 into a standalone Windows executable.
.DESCRIPTION
    Checks internet connectivity, ensures PS2EXE is available, compiles the WinForms
    PowerShell GUI with no console window, and validates the generated binary.
#>

[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$WorkspaceRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location -LiteralPath $WorkspaceRoot

function Write-Section {
    param([Parameter(Mandatory)][string]$Text)
    Write-Host ''
    Write-Host ('==== {0} ====' -f $Text) -ForegroundColor Cyan
}

function Write-Info {
    param([Parameter(Mandatory)][string]$Message)
    Write-Host ('[INFO] {0}' -f $Message) -ForegroundColor Cyan
}

function Write-Success {
    param([Parameter(Mandatory)][string]$Message)
    Write-Host ('[OK] {0}' -f $Message) -ForegroundColor Green
}

function Write-WarningLine {
    param([Parameter(Mandatory)][string]$Message)
    Write-Host ('[WARN] {0}' -f $Message) -ForegroundColor Yellow
}

function Write-ErrorLine {
    param([Parameter(Mandatory)][string]$Message)
    Write-Host ('[ERROR] {0}' -f $Message) -ForegroundColor Red
}

function Test-IsAdministrator {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Test-InternetConnection {
    try {
        if (Get-Command Test-NetConnection -ErrorAction SilentlyContinue) {
            return [bool](Test-NetConnection -ComputerName 'www.powershellgallery.com' -Port 443 -InformationLevel Quiet)
        }
        $request = [System.Net.WebRequest]::Create('https://www.powershellgallery.com')
        $request.Method = 'HEAD'
        $request.Timeout = 5000
        $response = $request.GetResponse()
        $response.Close()
        return $true
    } catch {
        return $false
    }
}

try {
    Write-Section 'Exchange Lab Manager EXE Build'

    if (Test-IsAdministrator) {
        Write-Success 'Administrative token detected.'
    } else {
        Write-WarningLine 'Administrative token not detected. Compilation usually works without elevation, but module/provider installation may be restricted by policy.'
    }

    $sourceFile = Join-Path $WorkspaceRoot 'ExchangeLabManager.ps1'
    if (-not (Test-Path -LiteralPath $sourceFile)) {
        throw "Source file missing: $sourceFile. Create ExchangeLabManager.ps1 before compiling."
    }
    Write-Success "Source file found: $sourceFile"

    Write-Section 'PS2EXE Setup'
    if (Test-InternetConnection) {
        Write-Success 'Internet connectivity to PowerShell Gallery detected.'
        Write-Info 'Installing or updating PS2EXE for the current user.'
        try {
            if (Get-Command Install-PackageProvider -ErrorAction SilentlyContinue) {
                Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Scope CurrentUser -Force -ErrorAction SilentlyContinue | Out-Null
            }
            Install-Module -Name ps2exe -Force -Scope CurrentUser -AllowClobber -ErrorAction Stop
        } catch {
            throw "Unable to install PS2EXE from PowerShell Gallery: $($_.Exception.Message)"
        }
    } else {
        Write-WarningLine 'No internet connection was detected.'
        Write-WarningLine 'Offline fallback: copy the ps2exe module folder into one of these module paths:'
        $env:PSModulePath -split ';' | Where-Object { $_ } | ForEach-Object { Write-Host ('       {0}' -f $_) -ForegroundColor Yellow }
        Write-WarningLine 'After copying the module, rerun this build script.'
    }

    if (-not (Get-Module -ListAvailable -Name ps2exe)) {
        throw 'PS2EXE is not installed or discoverable. Install-Module ps2exe failed or the system is offline without a staged module.'
    }

    Import-Module ps2exe -ErrorAction Stop
    $invokeCommand = Get-Command Invoke-PS2EXE -ErrorAction Stop
    Write-Success 'PS2EXE command loaded.'

    Write-Section 'Compilation'
    $outputDir = Join-Path $WorkspaceRoot 'bin'
    if (-not (Test-Path -LiteralPath $outputDir)) {
        New-Item -Path $outputDir -ItemType Directory -Force | Out-Null
    }

    $outputFile = Join-Path $outputDir 'ExchangeLabManager.exe'
    if (Test-Path -LiteralPath $outputFile) {
        Remove-Item -LiteralPath $outputFile -Force
    }

    $compileParams = @{
        InputFile   = $sourceFile
        OutputFile  = $outputFile
        NoConsole   = $true
        Title       = 'Exchange Lab & Security Mitigation Manager'
        Description = 'Automated testing framework for Exchange deployment and CVE-2026-42897 XSS validation'
    }
    if ($invokeCommand.Parameters.ContainsKey('Company')) {
        $compileParams.Company = 'IT Sec Lab Operations'
    } elseif ($invokeCommand.Parameters.ContainsKey('CompanyName')) {
        $compileParams.CompanyName = 'IT Sec Lab Operations'
    }
    if ($invokeCommand.Parameters.ContainsKey('Force')) {
        $compileParams.Force = $true
    }

    Write-Info 'Invoking PS2EXE with NoConsole enabled.'
    & $invokeCommand @compileParams

    if (-not (Test-Path -LiteralPath $outputFile)) {
        throw "Compilation completed without producing the expected executable: $outputFile"
    }

    $outputItem = Get-Item -LiteralPath $outputFile
    Write-Section 'Output Validation'
    Write-Success "Executable generated: $($outputItem.FullName)"
    Write-Success ("File size: {0} bytes ({1} KB / {2} MB)" -f $outputItem.Length, [math]::Round($outputItem.Length / 1KB, 2), [math]::Round($outputItem.Length / 1MB, 3))
    exit 0
} catch {
    Write-ErrorLine "Build failed: $($_.Exception.Message)"
    exit 1
}
