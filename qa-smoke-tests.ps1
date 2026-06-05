#requires -version 5.1
<#
.SYNOPSIS
    Non-destructive QA smoke tests for Exchange Lab Manager.
.DESCRIPTION
    Parses all PowerShell scripts, loads the GUI in NoRun mode, builds the WinForms
    form without showing it, and validates default controls plus safe helper logic.
    These tests intentionally do not execute network, AD DS, Exchange, EOMT, IIS, or SMTP actions.
#>

[CmdletBinding()]
param(
    [switch]$RunUiLoop
)

$ErrorActionPreference = 'Stop'
$WorkspaceRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location -LiteralPath $WorkspaceRoot

if ([Threading.Thread]::CurrentThread.GetApartmentState() -ne 'STA') {
    $powershell = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
    if (-not (Test-Path -LiteralPath $powershell -PathType Leaf)) {
        $powershell = (Get-Command powershell.exe -ErrorAction Stop).Source
    }
    $arguments = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-STA', '-File', $PSCommandPath)
    if ($RunUiLoop) { $arguments += '-RunUiLoop' }
    & $powershell @arguments
    exit $LASTEXITCODE
}

$script:Failures = 0

function Write-Result {
    param(
        [Parameter(Mandatory)][string]$Status,
        [Parameter(Mandatory)][string]$Message,
        [ConsoleColor]$Color = [ConsoleColor]::Gray
    )
    Write-Host ("[{0}] {1}" -f $Status, $Message) -ForegroundColor $Color
}

function Assert-True {
    param(
        [Parameter(Mandatory)][bool]$Condition,
        [Parameter(Mandatory)][string]$Message
    )
    if ($Condition) {
        Write-Result 'OK' $Message Green
    } else {
        Write-Result 'FAIL' $Message Red
        $script:Failures++
    }
}

function Assert-Equal {
    param(
        $Actual,
        $Expected,
        [Parameter(Mandatory)][string]$Message
    )
    Assert-True -Condition ([object]::Equals($Actual, $Expected)) -Message ("{0} (expected: {1}; actual: {2})" -f $Message, $Expected, $Actual)
}

function Assert-ThrowsLike {
    param(
        [Parameter(Mandatory)][scriptblock]$ScriptBlock,
        [Parameter(Mandatory)][string]$ExpectedText,
        [Parameter(Mandatory)][string]$Message
    )
    try {
        & $ScriptBlock
        Write-Result 'FAIL' ("{0} (no exception was thrown)" -f $Message) Red
        $script:Failures++
    } catch {
        if ($_.Exception.Message -like "*$ExpectedText*") {
            Write-Result 'OK' $Message Green
        } else {
            Write-Result 'FAIL' ("{0} (unexpected exception: {1})" -f $Message, $_.Exception.Message) Red
            $script:Failures++
        }
    }
}

function Get-ControlTree {
    param([Parameter(Mandatory)][System.Windows.Forms.Control]$Control)
    foreach ($child in $Control.Controls) {
        $child
        Get-ControlTree -Control $child
    }
}

Write-Host ''
Write-Host 'Exchange Lab Manager QA Smoke Tests' -ForegroundColor Cyan
Write-Host '-----------------------------------' -ForegroundColor Cyan

Write-Host ''
Write-Host 'Script parsing' -ForegroundColor Cyan
$scripts = Get-ChildItem -LiteralPath $WorkspaceRoot -Filter '*.ps1' -File |
    Where-Object { $_.Name -notlike 'tmp_*.ps1' } |
    Sort-Object Name
foreach ($script in $scripts) {
    $tokens = $null
    $parseErrors = $null
    [System.Management.Automation.Language.Parser]::ParseFile($script.FullName, [ref]$tokens, [ref]$parseErrors) | Out-Null
    Assert-True -Condition ($parseErrors.Count -eq 0) -Message ("{0} parses without syntax errors" -f $script.Name)
}

Write-Host ''
Write-Host 'Loading application' -ForegroundColor Cyan
. (Join-Path $WorkspaceRoot 'ExchangeLabManager.ps1') -NoRun
Assert-True -Condition ([bool](Get-Command New-MainForm -ErrorAction SilentlyContinue)) -Message 'GUI functions load in NoRun mode'

Write-Host ''
Write-Host 'Helper logic' -ForegroundColor Cyan
Assert-Equal -Actual (Convert-MaskToPrefix '255.255.255.0') -Expected 24 -Message 'Subnet mask converts to prefix length'
Assert-Equal -Actual (Get-GatewayFromIp '192.168.100.10') -Expected '192.168.100.1' -Message 'Gateway is derived from lab IP'
Assert-Equal -Actual (Format-Arg 'simple') -Expected 'simple' -Message 'Simple process argument is unchanged'
Assert-Equal -Actual (Format-Arg 'C:\Lab Path\Setup.exe') -Expected '"C:\Lab Path\Setup.exe"' -Message 'Process argument with spaces is quoted'
Assert-ThrowsLike -ScriptBlock { Convert-MaskToPrefix '255.0.255.0' } -ExpectedText 'not contiguous' -Message 'Invalid subnet mask is rejected'
Assert-ThrowsLike -ScriptBlock { Invoke-ExchangeSetup -ExchangePath (Join-Path $env:TEMP 'missing-exchange-iso') -Arguments @('/help') -Report { } } -ExpectedText 'Setup.exe was not found' -Message 'Missing Exchange setup path fails safely before process launch'
Assert-ThrowsLike -ScriptBlock { Send-XssMail -Data @{ Sender = ''; Recipient = 'victim@mylab.local'; Smtp = '192.168.100.10'; Payload = '<b>test</b>' } -Report { } } -ExpectedText 'Sender is required' -Message 'SMTP validation rejects missing sender before sending mail'

Write-Host ''
Write-Host 'WinForms construction' -ForegroundColor Cyan
$form = $null
try {
    $form = New-MainForm
    Assert-Equal -Actual $form.Text -Expected 'Exchange Lab & Security Mitigation Manager' -Message 'Main window title is correct'

    $tabControl = $form.Controls | Where-Object { $_ -is [System.Windows.Forms.TabControl] } | Select-Object -First 1
    Assert-True -Condition ($null -ne $tabControl) -Message 'Main tab control exists'
    Assert-Equal -Actual $tabControl.TabPages.Count -Expected 6 -Message 'All six operational tabs are present'

    $expectedTabs = @('Lab Control & Evidence','System & Network Setup','Exchange Prep & Install','Mitigation & EOMT','Automated XSS Test','CVE-2026-42897 Validation')
    $actualTabs = @($tabControl.TabPages | ForEach-Object { $_.Text })
    Assert-Equal -Actual ($actualTabs -join '|') -Expected ($expectedTabs -join '|') -Message 'Tab names match expected workflow'

    $allControls = @(Get-ControlTree -Control $form)
    Assert-True -Condition ($allControls.Count -gt 30) -Message 'Control tree is populated'
    Assert-Equal -Actual $script:Ui.ProfilePath.Text -Expected 'default-lab' -Message 'Default profile name is populated'
    Assert-Equal -Actual $script:Ui.Ip.Text -Expected '192.168.100.10' -Message 'Default static IP is populated'
    Assert-Equal -Actual $script:Ui.Mask.Text -Expected '255.255.255.0' -Message 'Default subnet mask is populated'
    Assert-Equal -Actual $script:Ui.Domain.Text -Expected 'mylab.local' -Message 'Default AD domain is populated'
    Assert-Equal -Actual $script:Ui.ExchangePath.Text -Expected 'D:\' -Message 'Default Exchange path is populated'
    Assert-Equal -Actual $script:Ui.Eomt.Text -Expected 'https://aka.ms/exchange-onprem-mitigation-tool' -Message 'Default EOMT source is populated'
    Assert-Equal -Actual $script:Ui.Payload.Items.Count -Expected 3 -Message 'Payload dropdown contains the expected safe controls'
    Assert-Equal -Actual $script:Ui.Payload.SelectedIndex -Expected 0 -Message 'Payload dropdown has a default selection'
    Assert-Equal -Actual $script:Ui.Status.Text.Trim() -Expected 'Ready. Use only inside an isolated Exchange lab VM.' -Message 'Status bar starts in ready state'
    Assert-Equal -Actual $script:Buttons.Count -Expected 24 -Message 'Expected action buttons are registered'

    $emptyButtonText = @($script:Buttons | Where-Object { [string]::IsNullOrWhiteSpace($_.Text) })
    Assert-Equal -Actual $emptyButtonText.Count -Expected 0 -Message 'All action buttons have visible labels'
} finally {
    if ($form) { $form.Dispose() }
}

if ($RunUiLoop) {
    Write-Host ''
    Write-Host 'Visible UI event loop' -ForegroundColor Cyan
    $form = $null
    $timer = $null
    try {
        $form = New-MainForm
        $tabControl = $form.Controls | Where-Object { $_ -is [System.Windows.Forms.TabControl] } | Select-Object -First 1
        $state = [pscustomobject]@{
            Index = 0
            Visited = New-Object System.Collections.Generic.List[string]
        }

        $timer = New-Object System.Windows.Forms.Timer
        $timer.Interval = 300
        $timer.Add_Tick({
            if ($state.Index -lt $tabControl.TabPages.Count) {
                $tabControl.SelectedIndex = $state.Index
                $state.Visited.Add($tabControl.SelectedTab.Text) | Out-Null
                $state.Index++
            } else {
                $timer.Stop()
                $form.Close()
            }
        })

        $form.Add_Shown({ $timer.Start() })
        [System.Windows.Forms.Application]::Run($form)
        Assert-Equal -Actual ($state.Visited -join '|') -Expected ($expectedTabs -join '|') -Message 'Visible UI loop cycles through all six tabs'
    } finally {
        if ($timer) { $timer.Dispose() }
        if ($form) { $form.Dispose() }
    }
}

Write-Host ''
if ($script:Failures -eq 0) {
    Write-Result 'PASS' 'All non-destructive QA smoke tests passed.' Green
    exit 0
}

Write-Result 'FAIL' ("{0} QA smoke test(s) failed." -f $script:Failures) Red
exit 1
