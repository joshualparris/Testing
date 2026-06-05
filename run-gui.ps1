<#
.SYNOPSIS
Launch the Exchange Lab Manager GUI from the repository root.
.DESCRIPTION
This helper script starts ExchangeLabManager.ps1 with a bypass execution policy and elevates if needed.
#>

[CmdletBinding()]
param(
    [switch]$Elevated,
    [switch]$PauseOnError
)

$ErrorActionPreference = 'Stop'

function Quote-LauncherArgument {
    param([Parameter(Mandatory)][string]$Value)
    return '"' + ($Value -replace '"', '\"') + '"'
}

function Wait-AfterLauncherError {
    param([Parameter(Mandatory)][string]$Message)

    Write-Host ''
    Write-Host 'Exchange Lab Manager could not start.' -ForegroundColor Red
    Write-Host $Message -ForegroundColor Yellow

    if ($PauseOnError) {
        Write-Host ''
        Read-Host 'Press Enter to close this window' | Out-Null
    }
}

try {
    $scriptDir = if ($PSScriptRoot) { $PSScriptRoot } else { Split-Path -Path $MyInvocation.MyCommand.Path -Parent }
    $guiPath = Join-Path $scriptDir 'ExchangeLabManager.ps1'

    if (-not (Test-Path -LiteralPath $guiPath -PathType Leaf)) {
        throw "Unable to find ExchangeLabManager.ps1 in $scriptDir"
    }

    $principal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
    $isAdmin = $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

    if (-not $isAdmin) {
        if ($Elevated) {
            throw 'Elevation was requested, but this PowerShell session is still not running as administrator.'
        }

        $powershell = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
        if (-not (Test-Path -LiteralPath $powershell -PathType Leaf)) {
            $powershell = (Get-Command powershell.exe -ErrorAction Stop).Source
        }

        $arguments = @(
            '-NoProfile'
            '-ExecutionPolicy'
            'Bypass'
            '-STA'
            '-File'
            (Quote-LauncherArgument $PSCommandPath)
            '-Elevated'
        )
        if ($PauseOnError) { $arguments += '-PauseOnError' }

        Start-Process -FilePath $powershell -ArgumentList ($arguments -join ' ') -Verb RunAs
        exit 0
    }

    & $guiPath
    exit 0
} catch {
    Wait-AfterLauncherError $_.Exception.Message
    exit 1
}
