# Exchange Lab Manager - Rollback and Cleanup Helper
# Safely removes temporary files, resets network settings, and cleans up lab artifacts

[CmdletBinding()]
param(
    [ValidateSet('DryRun', 'Clean', 'Full')]
    [string]$Mode = 'DryRun',
    [switch]$Force,
    [switch]$Quiet
)

$ErrorActionPreference = 'Continue'

function Write-Status {
    param([string]$Message, [string]$Status = 'Info')
    if (-not $Quiet) {
        $color = @{ Info = 'Cyan'; Warning = 'Yellow'; Error = 'Red'; Success = 'Green' }[$Status]
        Write-Host "[$Status] $Message" -ForegroundColor $color
    }
}

function Confirm-Action {
    param([string]$Action, [switch]$IsDestructive)
    if ($Force) { return $true }
    if ($IsDestructive) {
        $prompt = "WARNING: This action cannot be undone. Proceed?"
    } else {
        $prompt = "Proceed?"
    }
    $response = Read-Host "$Action`n$prompt (Y/N)"
    return $response -eq 'Y'
}

function Test-IsAdmin {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

Write-Host "Exchange Lab Manager - Cleanup & Rollback Helper" -ForegroundColor Cyan
Write-Host ('=' * 50) -ForegroundColor Cyan
Write-Host "Mode: $Mode`n" -ForegroundColor Yellow

if ($Mode -eq 'DryRun') {
    Write-Host "(DRY RUN - No changes will be made. Use -Mode Clean or -Mode Full to execute.)" -ForegroundColor Yellow
    Write-Host ""
}

# ============ Temporary Files ============
Write-Status "Scanning for temporary files..." 'Info'
$tempItems = @()

# Exchange Lab Manager temp files
$labTempPath = Join-Path $env:TEMP "ExchangeLabManager*"
$found = @(Get-Item -Path $labTempPath -ErrorAction SilentlyContinue)
if ($found) {
    $tempItems += $found
    Write-Status "Found $($found.Count) Exchange Lab Manager temp folder(s)" 'Info'
}

# CVE evidence bundles
$cvePath = Join-Path $env:TEMP "CVE42897-Evidence*"
$found = @(Get-Item -Path $cvePath -ErrorAction SilentlyContinue)
if ($found) {
    $tempItems += $found
    Write-Status "Found $($found.Count) CVE evidence folder(s)" 'Info'
}

# EOMT temp files
$eomtPath = Join-Path $env:TEMP "*EOMT*"
$found = @(Get-Item -Path $eomtPath -ErrorAction SilentlyContinue)
if ($found) {
    $tempItems += $found
    Write-Status "Found $($found.Count) EOMT temp file(s)" 'Info'
}

# Exchange Lab Manager script temp files (ui-error.txt, tmp_*.ps1, etc.)
$scriptTempPath = $PSScriptRoot
$scriptTemp = @(Get-ChildItem -Path $scriptTempPath -Filter "ui-error.txt" -ErrorAction SilentlyContinue)
$scriptTemp += @(Get-ChildItem -Path $scriptTempPath -Filter "tmp_*.ps1" -ErrorAction SilentlyContinue)
$scriptTemp += @(Get-ChildItem -Path $scriptTempPath -Filter "tmp_*.txt" -ErrorAction SilentlyContinue)
if ($scriptTemp) {
    $tempItems += $scriptTemp
    Write-Status "Found $($scriptTemp.Count) script temp file(s)" 'Info'
}

# ============ Display Summary ============
Write-Host ""
Write-Status "Cleanup Summary" 'Info'
Write-Host "================================" -ForegroundColor Gray

$categories = @{
    'ExchangeLabManager' = @()
    'CVEEvidence' = @()
    'EOMT' = @()
    'ScriptTemp' = @()
}

foreach ($item in $tempItems) {
    $size = if ($item.PSIsContainer) { (Get-ChildItem $item -Recurse | Measure-Object -Property Length -Sum).Sum } else { $item.Length }
    $sizeKB = [math]::Round($size / 1KB, 1)
    
    if ($item.Name -like "ExchangeLabManager*") {
        $categories['ExchangeLabManager'] += @{ Name = $item.Name; Path = $item.FullName; Size = $sizeKB }
        Write-Host "  [INFO] $($item.Name) ($sizeKB KB)" -ForegroundColor Gray
    } elseif ($item.Name -like "CVE42897*") {
        $categories['CVEEvidence'] += @{ Name = $item.Name; Path = $item.FullName; Size = $sizeKB }
        Write-Host "  [INFO] $($item.Name) ($sizeKB KB)" -ForegroundColor Gray
    } elseif ($item.Name -like "*EOMT*") {
        $categories['EOMT'] += @{ Name = $item.Name; Path = $item.FullName; Size = $sizeKB }
        Write-Host "  [INFO] $($item.Name) ($sizeKB KB)" -ForegroundColor Gray
    } else {
        $categories['ScriptTemp'] += @{ Name = $item.Name; Path = $item.FullName; Size = $sizeKB }
        Write-Host "  [INFO] $($item.Name) ($sizeKB KB)" -ForegroundColor Gray
    }
}

$totalSize = ($tempItems | ForEach-Object {
    if ($_.PSIsContainer) { (Get-ChildItem $_ -Recurse | Measure-Object -Property Length -Sum).Sum }
    else { $_.Length }
} | Measure-Object -Sum).Sum / 1MB

Write-Host ""
Write-Host "Total space to free: $([math]::Round($totalSize, 1)) MB" -ForegroundColor Cyan

# ============ Execute Cleanup (if not DryRun) ============
if ($Mode -in @('Clean', 'Full')) {
    Write-Host ""
    if (Confirm-Action "Delete temporary files?" -IsDestructive) {
        Write-Status "Removing temporary files..." 'Info'
        $removed = 0
        $failed = 0
        
        foreach ($item in $tempItems) {
            try {
                Remove-Item -LiteralPath $item.FullName -Recurse -Force -ErrorAction Stop
                $removed++
                if (-not $Quiet) { Write-Host "  [OK] Removed: $($item.Name)" -ForegroundColor Green }
            } catch {
                $failed++
                Write-Status "Failed to remove $($item.Name): $_" 'Error'
            }
        }
        
        Write-Host ""
        Write-Status "Removed $removed items, $failed failed" 'Success'
    }
}

# ============ Network Reset (Full Mode) ============
if ($Mode -eq 'Full') {
    Write-Host ""
    Write-Status "Network Reset Options" 'Info'
    Write-Host "(Full mode - use caution)" -ForegroundColor Yellow
    
    if (Confirm-Action "Reset network settings to DHCP?" -IsDestructive) {
        if (-not (Test-IsAdmin)) {
            Write-Status "Administrator privileges required for network reset" 'Error'
        } else {
            try {
                $adapters = Get-NetAdapter | Where-Object { $_.Status -eq 'Up' }
                foreach ($adapter in $adapters) {
                    Write-Status "Resetting $($adapter.Name) to DHCP..." 'Info'
                    Set-NetIPInterface -InterfaceAlias $adapter.Name -Dhcp Enabled -ErrorAction Stop
                    Remove-NetIPAddress -InterfaceAlias $adapter.Name -Confirm:$false -ErrorAction SilentlyContinue
                    Set-DnsClientServerAddress -InterfaceAlias $adapter.Name -ResetServerAddresses -ErrorAction Stop
                    Write-Status "Reset complete for $($adapter.Name)" 'Success'
                }
            } catch {
                Write-Status "Network reset failed: $_" 'Error'
            }
        }
    }
}

# ============ IIS Reset (Full Mode) ============
if ($Mode -eq 'Full') {
    Write-Host ""
    if (Confirm-Action "Reset IIS (iisreset)?" -IsDestructive) {
        if (-not (Test-IsAdmin)) {
            Write-Status "Administrator privileges required for IIS reset" 'Error'
        } else {
            try {
                Write-Status "Running iisreset..." 'Info'
                & iisreset /restart
                Write-Status "IIS reset complete" 'Success'
            } catch {
                Write-Status "IIS reset failed: $_" 'Error'
            }
        }
    }
}

# ============ Summary ============
Write-Host ""
Write-Host ('=' * 50) -ForegroundColor Cyan
if ($Mode -eq 'DryRun') {
    Write-Host "DRY RUN COMPLETE - No changes made" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "To execute cleanup, run:" -ForegroundColor Cyan
    Write-Host "  .\lab-cleanup-helper.ps1 -Mode Clean" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "For full cleanup (temporary + network reset + IIS reset):" -ForegroundColor Cyan
    Write-Host "  .\lab-cleanup-helper.ps1 -Mode Full -Force" -ForegroundColor Yellow
} else {
    Write-Host "CLEANUP COMPLETE" -ForegroundColor Green
}

exit 0
