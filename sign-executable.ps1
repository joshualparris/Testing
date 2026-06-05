#requires -version 5.1
<#
.SYNOPSIS
    Creates a local code-signing certificate and signs ExchangeLabManager.exe.
.DESCRIPTION
    Generates a self-signed code-signing certificate in the current user's Personal
    store, trusts it in the current user's Root store, and signs the compiled binary
    using native PowerShell Authenticode commands.
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

try {
    Write-Section 'Exchange Lab Manager Code Signing'

    $targetFile = Join-Path $WorkspaceRoot 'bin\ExchangeLabManager.exe'
    if (-not (Test-Path -LiteralPath $targetFile)) {
        throw "Target executable missing: $targetFile. Run .\build-executable.ps1 first."
    }
    Write-Success "Target executable found: $targetFile"

    Write-Section 'Certificate Creation'
    $cert = New-SelfSignedCertificate `
        -Subject 'CN=IT Sec Lab Local Code Signing' `
        -Type CodeSigning `
        -FriendlyName 'Exchange Lab Manager Development Cert' `
        -CertStoreLocation 'Cert:\CurrentUser\My' `
        -NotAfter (Get-Date).AddYears(2) `
        -KeyAlgorithm RSA `
        -KeyLength 2048 `
        -HashAlgorithm SHA256 `
        -KeyExportPolicy Exportable `
        -ErrorAction Stop

    Write-Success 'Certificate generated in Cert:\CurrentUser\My.'
    Write-Info "Thumbprint: $($cert.Thumbprint)"
    Write-Info "Expires: $($cert.NotAfter)"

    Write-Section 'Local Trust Provisioning'
    $exportPath = Join-Path $env:TEMP ('ExchangeLabManager-CodeSigning-{0}.cer' -f $cert.Thumbprint)
    Export-Certificate -Cert $cert -FilePath $exportPath -Force -ErrorAction Stop | Out-Null
    Import-Certificate -FilePath $exportPath -CertStoreLocation 'Cert:\CurrentUser\Root' -ErrorAction Stop | Out-Null
    Remove-Item -LiteralPath $exportPath -Force -ErrorAction SilentlyContinue
    Write-Success 'Certificate exported and imported into Cert:\CurrentUser\Root.'
    Write-WarningLine 'Self-signed trust is local to this lab profile. Public SmartScreen reputation still requires a publicly trusted certificate and reputation history.'

    Write-Section 'Authenticode Signing'
    $signature = Set-AuthenticodeSignature -FilePath $targetFile -Certificate $cert -HashAlgorithm SHA256 -ErrorAction Stop
    Write-Info "Signing result: $($signature.Status)"

    $verification = Get-AuthenticodeSignature -FilePath $targetFile -ErrorAction Stop
    if ($verification.Status -ne 'Valid') {
        throw "Signature was applied but did not validate cleanly. Authenticode status: $($verification.Status). $($verification.StatusMessage)"
    }

    Write-Success 'Authenticode signature validated successfully.'
    Write-Info 'Windows UI verification path: right-click the EXE, choose Properties, then open the Digital Signatures tab.'

    Write-Section 'Signing Summary'
    Write-Host '[OK] Certificate generated' -ForegroundColor Green
    Write-Host '[OK] Certificate trusted in CurrentUser Root store' -ForegroundColor Green
    Write-Host '[OK] Executable digitally signed' -ForegroundColor Green
    Write-Host ('[OK] Authenticode status: {0}' -f $verification.Status) -ForegroundColor Green
    exit 0
} catch {
    Write-ErrorLine "Signing failed: $($_.Exception.Message)"
    exit 1
}
