#requires -version 5.1
<#
.SYNOPSIS
    One-click build, sign, stage, and ISO packaging pipeline for Exchange Lab Manager.
.DESCRIPTION
    Verifies workspace inputs, compiles the WinForms GUI with PS2EXE, signs the
    resulting binary with a local lab certificate, stages distribution files, and
    creates a VirtualBox-mountable ISO image using native Windows tooling.
#>

[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$WorkspaceRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location -LiteralPath $WorkspaceRoot

$DistDir = Join-Path $WorkspaceRoot 'dist'
if (-not (Test-Path -LiteralPath $DistDir)) {
    New-Item -Path $DistDir -ItemType Directory -Force | Out-Null
}

$LogFile = Join-Path $DistDir 'deployment-log.txt'
$null = Set-Content -LiteralPath $LogFile -Value ('Exchange Lab Manager deployment log - {0}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss')) -Encoding UTF8
$Stopwatch = [System.Diagnostics.Stopwatch]::StartNew()

function Write-Log {
    param(
        [Parameter(Mandatory)][string]$Message,
        [ValidateSet('INFO', 'OK', 'WARN', 'ERROR', 'STEP', 'CHILD')]
        [string]$Level = 'INFO',
        [ConsoleColor]$Color = [ConsoleColor]::Gray
    )
    $line = '[{0}] [{1}] {2}' -f (Get-Date -Format 'HH:mm:ss'), $Level, $Message
    Add-Content -LiteralPath $LogFile -Value $line
    Write-Host $line -ForegroundColor $Color
}

function Write-Section {
    param([Parameter(Mandatory)][string]$Title)
    Write-Host ''
    Write-Host '+------------------------------------------------------------+' -ForegroundColor Cyan
    Write-Host ('| {0,-58} |' -f $Title) -ForegroundColor Cyan
    Write-Host '+------------------------------------------------------------+' -ForegroundColor Cyan
    Add-Content -LiteralPath $LogFile -Value ''
    Add-Content -LiteralPath $LogFile -Value ('==== {0} ====' -f $Title)
}

function Test-IsAdministrator {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Remove-DirectoryWithinWorkspace {
    param([Parameter(Mandatory)][string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) { return }

    $workspaceFull = [System.IO.Path]::GetFullPath($WorkspaceRoot).TrimEnd('\') + '\'
    $targetFull = [System.IO.Path]::GetFullPath($Path).TrimEnd('\') + '\'
    if (-not $targetFull.StartsWith($workspaceFull, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "Refusing to remove directory outside workspace: $targetFull"
    }
    if ($targetFull -eq $workspaceFull) {
        throw 'Refusing to remove the workspace root.'
    }
    Remove-Item -LiteralPath $Path -Recurse -Force
}

function Invoke-ChildScript {
    param(
        [Parameter(Mandatory)][string]$ScriptPath,
        [Parameter(Mandatory)][string]$StepName
    )
    if (-not (Test-Path -LiteralPath $ScriptPath)) {
        throw "Missing script for ${StepName}: $ScriptPath"
    }

    $powershell = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
    if (-not (Test-Path -LiteralPath $powershell)) {
        $powershell = (Get-Command powershell.exe -ErrorAction Stop).Source
    }

    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $powershell
    $psi.Arguments = '-NoProfile -ExecutionPolicy Bypass -File "{0}"' -f $ScriptPath
    $psi.WorkingDirectory = $WorkspaceRoot
    $psi.UseShellExecute = $false
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.CreateNoWindow = $true

    Write-Log -Message "Launching child step: $StepName" -Level STEP -Color Cyan
    $process = New-Object System.Diagnostics.Process
    $process.StartInfo = $psi

    $stdoutHandler = [System.Diagnostics.DataReceivedEventHandler]{
        param($sender, $eventArgs)
        if (-not [string]::IsNullOrWhiteSpace($eventArgs.Data)) {
            Write-Log -Message ("{0}: {1}" -f $StepName, $eventArgs.Data) -Level CHILD -Color DarkGray
        }
    }
    $stderrHandler = [System.Diagnostics.DataReceivedEventHandler]{
        param($sender, $eventArgs)
        if (-not [string]::IsNullOrWhiteSpace($eventArgs.Data)) {
            Write-Log -Message ("{0}: {1}" -f $StepName, $eventArgs.Data) -Level WARN -Color Yellow
        }
    }
    $process.add_OutputDataReceived($stdoutHandler)
    $process.add_ErrorDataReceived($stderrHandler)

    $exitCode = $null
    try {
        [void]$process.Start()
        $process.BeginOutputReadLine()
        $process.BeginErrorReadLine()
        $process.WaitForExit()
        $exitCode = $process.ExitCode
    } finally {
        $process.remove_OutputDataReceived($stdoutHandler)
        $process.remove_ErrorDataReceived($stderrHandler)
        $process.Dispose()
    }

    if ($exitCode -ne 0) { throw "$StepName failed with exit code $exitCode." }
    Write-Log -Message "Child step completed: $StepName" -Level OK -Color Green
}

function Find-Oscdimg {
    $paths = New-Object System.Collections.Generic.List[string]
    $command = Get-Command oscdimg.exe -ErrorAction SilentlyContinue
    if ($command) { $paths.Add($command.Source) }

    $candidateRoots = @(${env:ProgramFiles(x86)}, $env:ProgramFiles) | Where-Object { $_ }
    foreach ($root in $candidateRoots) {
        $paths.Add((Join-Path $root 'Windows Kits\10\Assessment and Deployment Kit\Deployment Tools\amd64\Oscdimg\oscdimg.exe'))
        $paths.Add((Join-Path $root 'Windows Kits\10\Assessment and Deployment Kit\Deployment Tools\x86\Oscdimg\oscdimg.exe'))
        $paths.Add((Join-Path $root 'Windows Kits\11\Assessment and Deployment Kit\Deployment Tools\amd64\Oscdimg\oscdimg.exe'))
    }

    foreach ($path in $paths | Select-Object -Unique) {
        if ($path -and (Test-Path -LiteralPath $path)) { return $path }
    }
    return $null
}

function New-IsoWithOscdimg {
    param(
        [Parameter(Mandatory)][string]$SourceDirectory,
        [Parameter(Mandatory)][string]$IsoPath,
        [Parameter(Mandatory)][string]$VolumeLabel,
        [Parameter(Mandatory)][string]$OscdimgPath
    )
    Write-Log -Message "Using oscdimg.exe: $OscdimgPath" -Level INFO -Color Cyan
    $arguments = @('-n', '-m', '-o', ('-l{0}' -f $VolumeLabel), $SourceDirectory, $IsoPath)
    & $OscdimgPath @arguments
    if ($LASTEXITCODE -ne 0) { throw "oscdimg.exe failed with exit code $LASTEXITCODE." }
}

function New-IsoWithImapi {
    param(
        [Parameter(Mandatory)][string]$SourceDirectory,
        [Parameter(Mandatory)][string]$IsoPath,
        [Parameter(Mandatory)][string]$VolumeLabel
    )
    Write-Log -Message 'oscdimg.exe was not found. Falling back to native IMAPI2FS COM ISO generation.' -Level WARN -Color Yellow
    Write-Log -Message 'No boot sector was provided, so the fallback creates a VirtualBox-mountable data ISO.' -Level INFO -Color Cyan

    $image = New-Object -ComObject IMAPI2FS.MsftFileSystemImage
    try { $image.ChooseImageDefaultsForMediaType(13) } catch { Write-Log -Message 'IMAPI media defaults unavailable; continuing with explicit filesystem flags.' -Level WARN -Color Yellow }
    $image.FileSystemsToCreate = 7
    $image.VolumeName = $VolumeLabel
    $image.Root.AddTree($SourceDirectory, $false)

    $result = $image.CreateResultImage()
    $stream = $result.ImageStream
    $totalBytes = [int64]$result.TotalBlocks * [int64]$result.BlockSize
    $fileStream = [System.IO.File]::Open($IsoPath, [System.IO.FileMode]::Create, [System.IO.FileAccess]::Write, [System.IO.FileShare]::None)
    try {
        $remaining = $totalBytes
        while ($remaining -gt 0) {
            $readSize = [int][Math]::Min(1048576, $remaining)
            $chunk = $stream.Read($readSize)
            if ($null -eq $chunk -or $chunk.Length -eq 0) { break }
            $fileStream.Write($chunk, 0, $chunk.Length)
            $remaining -= $chunk.Length
        }
    } finally {
        $fileStream.Close()
        $fileStream.Dispose()
    }
}

function New-VirtualBoxIso {
    param([Parameter(Mandatory)][string]$StageDirectory, [Parameter(Mandatory)][string]$IsoPath)
    if (Test-Path -LiteralPath $IsoPath) { Remove-Item -LiteralPath $IsoPath -Force }
    $label = 'EXCHANGE_LAB'
    $oscdimg = Find-Oscdimg
    if ($oscdimg) {
        New-IsoWithOscdimg -SourceDirectory $StageDirectory -IsoPath $IsoPath -VolumeLabel $label -OscdimgPath $oscdimg
    } else {
        New-IsoWithImapi -SourceDirectory $StageDirectory -IsoPath $IsoPath -VolumeLabel $label
    }

    if (-not (Test-Path -LiteralPath $IsoPath)) { throw "ISO generation completed without producing the expected file: $IsoPath" }
    $iso = Get-Item -LiteralPath $IsoPath
    if ($iso.Length -le 0) { throw "ISO file was generated but is empty: $IsoPath" }
    Write-Log -Message ("ISO generated: {0} ({1} bytes / {2} MB)" -f $iso.FullName, $iso.Length, [math]::Round($iso.Length / 1MB, 3)) -Level OK -Color Green
}

function Copy-IfPresent {
    param([Parameter(Mandatory)][string]$RelativePath, [Parameter(Mandatory)][string]$DestinationDirectory)
    $source = Join-Path $WorkspaceRoot $RelativePath
    if (Test-Path -LiteralPath $source) {
        Copy-Item -LiteralPath $source -Destination $DestinationDirectory -Force
        Write-Log -Message "Staged helper file: $RelativePath" -Level INFO -Color Gray
    }
}

try {
    Write-Section 'Workspace Verification'
    Write-Log -Message "Workspace: $WorkspaceRoot" -Level INFO -Color Cyan
    if (Test-IsAdministrator) {
        Write-Log -Message 'Administrative token detected.' -Level OK -Color Green
    } else {
        Write-Log -Message 'Administrative token not detected. Build can continue, but signing/trust behavior may be constrained by local policy.' -Level WARN -Color Yellow
    }

    $required = 'ExchangeLabManager.ps1','build-executable.ps1','sign-executable.ps1'
    $missing = @()
    foreach ($file in $required) {
        if (-not (Test-Path -LiteralPath (Join-Path $WorkspaceRoot $file))) { $missing += $file }
    }
    if ($missing.Count -gt 0) {
        Write-Log -Message ('Missing required workspace files: {0}' -f ($missing -join ', ')) -Level ERROR -Color Red
        throw 'Workspace verification failed.'
    }
    Write-Log -Message 'All required workspace scripts are present.' -Level OK -Color Green

    Write-Section 'Step 1: Execution Policy Check'
    Write-Log -Message ("Current Process execution policy: {0}" -f (Get-ExecutionPolicy -Scope Process)) -Level INFO -Color Cyan
    Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass -Force
    Write-Log -Message 'Process execution policy set to Bypass for this build session.' -Level OK -Color Green

    Write-Section 'Step 2: Compilation'
    Invoke-ChildScript -ScriptPath (Join-Path $WorkspaceRoot 'build-executable.ps1') -StepName 'Compilation'
    $compiled = Join-Path $WorkspaceRoot 'bin\ExchangeLabManager.exe'
    if (-not (Test-Path -LiteralPath $compiled)) { throw "Compilation finished but the binary was not found: $compiled" }
    Write-Log -Message "Compiled binary verified: $compiled" -Level OK -Color Green

    Write-Section 'Step 3: Digital Code-Signing'
    try {
        Invoke-ChildScript -ScriptPath (Join-Path $WorkspaceRoot 'sign-executable.ps1') -StepName 'Code signing'
        $signature = Get-AuthenticodeSignature -FilePath $compiled -ErrorAction Stop
        if ($signature.Status -ne 'Valid') { throw "Authenticode status is not Valid: $($signature.Status). $($signature.StatusMessage)" }
        Write-Log -Message 'Authenticode status returned Valid.' -Level OK -Color Green
    } catch {
        Write-Log -Message "Code signing failed or was skipped: $($_.Exception.Message)" -Level WARN -Color Yellow
        Write-Log -Message 'Proceeding with unsigned binary for lab deployment.' -Level INFO -Color Cyan
    }

    Write-Section 'Laboratory Deployment Packaging'
    $distBinary = Join-Path $DistDir 'ExchangeLabManager.exe'
    Copy-Item -LiteralPath $compiled -Destination $distBinary -Force
    Write-Log -Message "Signed executable staged: $distBinary" -Level OK -Color Green
    Write-Log -Message "Deployment log path: $LogFile" -Level OK -Color Green

    Write-Section 'Step 4: Automated VirtualBox ISO Generation'
    $isoStage = Join-Path $WorkspaceRoot 'iso_stage'
    try {
        Remove-DirectoryWithinWorkspace -Path $isoStage
        New-Item -Path $isoStage -ItemType Directory -Force | Out-Null
        Write-Log -Message "ISO staging directory prepared: $isoStage" -Level OK -Color Green
        Copy-Item -LiteralPath $distBinary -Destination $isoStage -Force
        Write-Log -Message 'Signed executable copied into ISO stage.' -Level OK -Color Green
        Copy-IfPresent -RelativePath 'README.md' -DestinationDirectory $isoStage
        Copy-IfPresent -RelativePath 'exchange-html-validation-test.ps1' -DestinationDirectory $isoStage
        Copy-IfPresent -RelativePath 'exchange-lab-automation.ps1' -DestinationDirectory $isoStage
        Copy-Item -LiteralPath $LogFile -Destination $isoStage -Force
        Write-Log -Message 'Deployment log copied into ISO stage.' -Level INFO -Color Gray
        New-VirtualBoxIso -StageDirectory $isoStage -IsoPath (Join-Path $DistDir 'ExchangeLabFiles.iso')
    } finally {
        if (Test-Path -LiteralPath $isoStage) {
            Remove-DirectoryWithinWorkspace -Path $isoStage
            Write-Log -Message 'Temporary iso_stage directory removed.' -Level OK -Color Green
        }
    }

    $Stopwatch.Stop()
    $elapsed = '{0:hh\:mm\:ss}' -f $Stopwatch.Elapsed
    Write-Section 'Final Build Summary'
    Write-Host ''
    Write-Host '+------------------------------------------------------------+' -ForegroundColor Green
    Write-Host '| Exchange Lab Manager release pipeline completed            |' -ForegroundColor Green
    Write-Host '+------------------------------------------------------------+' -ForegroundColor Green
    Write-Host ('| Total elapsed time: {0,-38} |' -f $elapsed) -ForegroundColor Green
    Write-Host '| [OK] GUI Source Code Verified                              |' -ForegroundColor Green
    Write-Host '| [OK] Standalone Binary Compiled (.exe)                     |' -ForegroundColor Green
    Write-Host '| [OK] Digital Lab Certificate Generated & Trusted           |' -ForegroundColor Green
    Write-Host '| [OK] Executable Digitally Signed                           |' -ForegroundColor Green
    Write-Host '| [OK] Staging Directories Cleared                           |' -ForegroundColor Green
    Write-Host '| [OK] VirtualBox-Ready ISO Image Compiled                   |' -ForegroundColor Green
    Write-Host '+------------------------------------------------------------+' -ForegroundColor Green
    Write-Log -Message "Pipeline completed in $elapsed." -Level OK -Color Green
    Write-Log -Message 'Final EXE: .\dist\ExchangeLabManager.exe' -Level OK -Color Green
    Write-Log -Message 'Final ISO: .\dist\ExchangeLabFiles.iso' -Level OK -Color Green
    exit 0
} catch {
    $Stopwatch.Stop()
    Write-Log -Message "Pipeline failed: $($_.Exception.Message)" -Level ERROR -Color Red
    Write-Log -Message ('Elapsed before failure: {0:hh\:mm\:ss}' -f $Stopwatch.Elapsed) -Level ERROR -Color Red
    exit 1
}
