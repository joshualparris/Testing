#requires -version 5.1
<#
.SYNOPSIS
    Full non-destructive and mocked QA suite for Exchange Lab Manager.
.DESCRIPTION
    Exercises the app's parser, launcher failure path, WinForms construction,
    button wiring, async worker behavior, helper functions, process logging, and
    destructive operation logic behind mocks. This suite does not mutate network
    settings, promote AD DS, install Exchange, run EOMT, modify IIS, or send SMTP.
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

function Assert-Like {
    param(
        [AllowEmptyString()][string]$Actual,
        [Parameter(Mandatory)][string]$Pattern,
        [Parameter(Mandatory)][string]$Message
    )
    Assert-True -Condition ($Actual -like $Pattern) -Message ("{0} (pattern: {1}; actual: {2})" -f $Message, $Pattern, $Actual)
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

function New-ReportList {
    New-Object System.Collections.Generic.List[object]
}

function New-ReportBlock {
    param([AllowEmptyCollection()][System.Collections.Generic.List[object]]$List)
    return {
        param([Parameter(Mandatory)][string]$Message, [string]$Kind = 'Info')
        $List.Add([pscustomobject]@{ Message = $Message; Kind = $Kind }) | Out-Null
    }.GetNewClosure()
}

function Get-ReportText {
    param([Parameter(Mandatory)][System.Collections.Generic.List[object]]$List)
    return (($List | ForEach-Object { "$($_.Kind):$($_.Message)" }) -join "`n")
}

function Get-ControlTree {
    param([Parameter(Mandatory)][System.Windows.Forms.Control]$Control)
    foreach ($child in $Control.Controls) {
        $child
        Get-ControlTree -Control $child
    }
}

function Get-ButtonByText {
    param(
        [Parameter(Mandatory)][string]$Text,
        [Parameter(Mandatory)][System.Windows.Forms.Form]$Form
    )
    $button = Get-ControlTree -Control $Form |
        Where-Object { $_ -is [System.Windows.Forms.Button] -and $_.Text -eq $Text } |
        Select-Object -First 1
    Assert-True -Condition ($null -ne $button) -Message "Button exists: $Text"
    return $button
}

function Invoke-ButtonClick {
    param([Parameter(Mandatory)][System.Windows.Forms.Button]$Button)
    $bindingFlags = [System.Reflection.BindingFlags]::Instance -bor [System.Reflection.BindingFlags]::NonPublic
    $onClick = $Button.GetType().GetMethod('OnClick', $bindingFlags)
    if (-not $onClick) { throw "Unable to find protected OnClick method for button '$($Button.Text)'." }
    $onClick.Invoke($Button, @([System.EventArgs]::Empty)) | Out-Null
}

function Invoke-VisibleTabLoop {
    param(
        [Parameter(Mandatory)][System.Windows.Forms.Form]$Form,
        [Parameter(Mandatory)][System.Windows.Forms.TabControl]$TabControl
    )
    $state = [pscustomobject]@{
        Index = 0
        Visited = New-Object System.Collections.Generic.List[string]
    }
    $timer = New-Object System.Windows.Forms.Timer
    try {
        $timer.Interval = 250
        $timer.Add_Tick({
            if ($state.Index -lt $TabControl.TabPages.Count) {
                $TabControl.SelectedIndex = $state.Index
                $state.Visited.Add($TabControl.SelectedTab.Text) | Out-Null
                $state.Index++
            } else {
                $timer.Stop()
                $Form.Close()
            }
        })
        $Form.Add_Shown({ $timer.Start() })
        [System.Windows.Forms.Application]::Run($Form)
        return @($state.Visited)
    } finally {
        $timer.Dispose()
    }
}

function Invoke-WorkerScenario {
    param([bool]$Fail)

    $form = New-MainForm
    try {
        Start-LabTask 'QA worker' $script:Ui.SystemLog $script:Ui.SystemPill $script:Ui.SystemProgress {
            param($Data, $Report)
            & $Report 'QA worker progress' 'Info'
            if ($Data.Fail) { throw 'QA forced failure' }
            & $Report 'QA worker success detail' 'Good'
        } @{ Fail = $Fail } 'QA worker starting...' 'QA worker finished.'

        $deadline = (Get-Date).AddSeconds(12)
        while ($script:Busy -and (Get-Date) -lt $deadline) {
            [System.Windows.Forms.Application]::DoEvents()
            Start-Sleep -Milliseconds 50
        }
        for ($i = 0; $i -lt 10; $i++) {
            [System.Windows.Forms.Application]::DoEvents()
            Start-Sleep -Milliseconds 20
        }

        return [pscustomobject]@{
            TimedOut = [bool]$script:Busy
            Log = $script:Ui.SystemLog.Text
            Pill = $script:Ui.SystemPill.Text.Trim()
            Status = $script:Ui.Status.Text.Trim()
            ProgressStyle = $script:Ui.SystemProgress.Style.ToString()
            ButtonsEnabled = (@($script:Buttons | Where-Object { -not $_.Enabled }).Count -eq 0)
        }
    } finally {
        $form.Dispose()
    }
}

function Set-MockFunction {
    param(
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][scriptblock]$Body
    )
    Set-Item -Path "Function:\script:$Name" -Value $Body
}

Write-Host ''
Write-Host 'Exchange Lab Manager Full QA Suite' -ForegroundColor Cyan
Write-Host '----------------------------------' -ForegroundColor Cyan

Write-Host ''
Write-Host 'Script parsing and static package checks' -ForegroundColor Cyan
$scripts = Get-ChildItem -LiteralPath $WorkspaceRoot -Filter '*.ps1' -File |
    Where-Object { $_.Name -notlike 'tmp_*.ps1' } |
    Sort-Object Name
foreach ($script in $scripts) {
    $tokens = $null
    $parseErrors = $null
    [System.Management.Automation.Language.Parser]::ParseFile($script.FullName, [ref]$tokens, [ref]$parseErrors) | Out-Null
    Assert-True -Condition ($parseErrors.Count -eq 0) -Message ("{0} parses without syntax errors" -f $script.Name)
}
foreach ($required in 'ExchangeLabManager.ps1','run-gui.bat','run-gui.ps1','qa-smoke-tests.ps1','build-executable.ps1','sign-executable.ps1','build-pipeline.ps1','exchange-xss-test.ps1') {
    Assert-True -Condition (Test-Path -LiteralPath (Join-Path $WorkspaceRoot $required) -PathType Leaf) -Message "Required package file exists: $required"
}
$batchText = Get-Content -Raw -LiteralPath (Join-Path $WorkspaceRoot 'run-gui.bat')
Assert-True -Condition ($batchText -match '-STA' -and $batchText -match '-PauseOnError') -Message 'Batch launcher uses STA and pause-on-error mode'
$pipelineText = Get-Content -Raw -LiteralPath (Join-Path $WorkspaceRoot 'build-pipeline.ps1')
Assert-True -Condition ($pipelineText -match 'Refusing to remove directory outside workspace') -Message 'Build pipeline keeps workspace deletion guard'

Write-Host ''
Write-Host 'Application load and helper logic' -ForegroundColor Cyan
$qaStateRoot = Join-Path $env:TEMP ('ExchangeLabManager-StateQA-{0}' -f ([guid]::NewGuid()))
. (Join-Path $WorkspaceRoot 'ExchangeLabManager.ps1') -NoRun
$script:LabDataRoot = $qaStateRoot
Assert-True -Condition ([bool](Get-Command New-MainForm -ErrorAction SilentlyContinue)) -Message 'Application loads in NoRun mode'
Assert-Equal -Actual (Convert-MaskToPrefix '0.0.0.0') -Expected 0 -Message 'Zero subnet mask converts to /0'
Assert-Equal -Actual (Convert-MaskToPrefix '255.255.255.255') -Expected 32 -Message 'Host subnet mask converts to /32'
Assert-Equal -Actual (Convert-MaskToPrefix '255.255.252.0') -Expected 22 -Message 'Non-octet subnet mask converts to prefix'
Assert-ThrowsLike -ScriptBlock { Convert-MaskToPrefix '255.0.255.0' } -ExpectedText 'not contiguous' -Message 'Non-contiguous subnet mask is rejected'
Assert-ThrowsLike -ScriptBlock { Convert-MaskToPrefix 'not-a-mask' } -ExpectedText 'Invalid subnet mask' -Message 'Malformed subnet mask is rejected'
Assert-Equal -Actual (Get-GatewayFromIp '192.168.100.10') -Expected '192.168.100.1' -Message 'Gateway derives from IPv4 address'
Assert-Equal -Actual (Get-GatewayFromIp 'bad-ip') -Expected $null -Message 'Invalid gateway input returns null'
Assert-Equal -Actual (Format-Arg 'simple') -Expected 'simple' -Message 'Simple process argument is unchanged'
Assert-Equal -Actual (Format-Arg 'C:\Lab Path\Setup.exe') -Expected '"C:\Lab Path\Setup.exe"' -Message 'Process argument with spaces is quoted'

Write-Host ''
Write-Host 'WinForms construction and reset behavior' -ForegroundColor Cyan
$form = $null
$form2 = $null
try {
    $form = New-MainForm
    $tabControl = $form.Controls | Where-Object { $_ -is [System.Windows.Forms.TabControl] } | Select-Object -First 1
    $expectedTabs = @('Lab Control & Evidence','System & Network Setup','Exchange Prep & Install','Mitigation & EOMT','Automated XSS Test','CVE-2026-42897 Validation')
    Assert-Equal -Actual $form.Text -Expected 'Exchange Lab & Security Mitigation Manager' -Message 'Main form title is correct'
    Assert-Equal -Actual $tabControl.TabPages.Count -Expected 6 -Message 'Main form has six tabs'
    Assert-Equal -Actual ((@($tabControl.TabPages | ForEach-Object { $_.Text })) -join '|') -Expected ($expectedTabs -join '|') -Message 'Tab names match expected workflow'
    Assert-Equal -Actual $script:Buttons.Count -Expected 24 -Message 'Button registry has twenty-four buttons after first form construction'
    $form2 = New-MainForm
    Assert-Equal -Actual $script:Buttons.Count -Expected 24 -Message 'Button registry resets on repeated form construction'
    Assert-Equal -Actual $script:Ui.Status.Text.Trim() -Expected 'Ready. Use only inside an isolated Exchange lab VM.' -Message 'Status bar starts ready'
    Assert-Equal -Actual $script:Ui.Payload.Items.Count -Expected 3 -Message 'Payload dropdown has three control payloads'

    if ($RunUiLoop) {
        $visited = Invoke-VisibleTabLoop -Form $form2 -TabControl ($form2.Controls | Where-Object { $_ -is [System.Windows.Forms.TabControl] } | Select-Object -First 1)
        $form2 = $null
        Assert-Equal -Actual ($visited -join '|') -Expected ($expectedTabs -join '|') -Message 'Visible event loop cycles through all six tabs'
    }
} finally {
    if ($form) { $form.Dispose() }
    if ($form2) { $form2.Dispose() }
}

Write-Host ''
Write-Host 'Button wiring with mocked Start-LabTask' -ForegroundColor Cyan
$script:StartCalls = New-Object System.Collections.Generic.List[object]
Set-MockFunction -Name Start-LabTask -Body {
    param($Name, $LogBox, $Indicator, $Progress, $Action, $Data, $StartMessage, $DoneMessage, $CheckpointMilestone, $RecordManifest)
    $script:StartCalls.Add([pscustomobject]@{
        Name = $Name
        Data = $Data
        StartMessage = $StartMessage
        DoneMessage = $DoneMessage
        CheckpointMilestone = $CheckpointMilestone
        RecordManifest = $RecordManifest
        LogType = if ($LogBox) { $LogBox.GetType().FullName } else { $null }
        IndicatorType = if ($Indicator) { $Indicator.GetType().FullName } else { $null }
        ProgressType = if ($Progress) { $Progress.GetType().FullName } else { $null }
    }) | Out-Null
}
$form = $null
try {
    $form = New-MainForm
    $script:Ui.ProfilePath.Text = 'qa-profile'
    $script:Ui.Ip.Text = '10.20.30.40'
    $script:Ui.Mask.Text = '255.255.252.0'
    $script:Ui.Domain.Text = 'contoso.lab'
    $script:Ui.ExchangePath.Text = 'E:\Exchange ISO'
    $script:Ui.Eomt.Text = 'C:\Tools\EOMT.ps1'
    $script:Ui.Attacker.Text = 'red@mylab.local'
    $script:Ui.Victim.Text = 'blue@mylab.local'
    $script:Ui.Smtp.Text = '10.20.30.40'
    $script:Ui.Payload.SelectedIndex = 2
    $script:Ui.OwaUrl.Text = 'https://lab-ex02.exchange-lab.test/owa'

    foreach ($buttonName in @(
        'Load Profile',
        'Save Profile',
        'Save Run Manifest',
        'Run Preflight Check',
        'Export Full Evidence Bundle',
        'Save Checkpoint',
        'Load Checkpoint',
        'Reset Checkpoint',
        'Preview Cleanup',
        'Clean Temp Artifacts',
        'Configure Network',
        'Install Active Directory & Promote',
        'Prepare AD Schema & Forests',
        'Launch Exchange Installer Syntax',
        'Download & Apply EOMT Mitigation',
        'Check Status (Get-Mitigation M2.1.x)',
        'Fire Test Email',
        'Check Exchange Build',
        'Check EM Service',
        'Check Mitigation State',
        'Verify CSP Header',
        'Export Evidence Bundle'
    )) {
        $button = Get-ButtonByText -Text $buttonName -Form $form
        Invoke-ButtonClick -Button $button
    }

    Assert-Equal -Actual $script:StartCalls.Count -Expected 22 -Message 'All task buttons except browse buttons dispatch Start-LabTask'
    Assert-Equal -Actual (($script:StartCalls | ForEach-Object { $_.Name }) -join '|') -Expected 'Profile load|Profile save|Run manifest export|Preflight check|Full evidence export|Checkpoint save|Checkpoint load|Checkpoint reset|Cleanup preview|Temp cleanup|Network setup|AD DS promotion|Exchange AD prep|Exchange install|EOMT mitigation|Mitigation status|XSS email test|Exchange build check|EM service check|Mitigation state check|CSP header verification|Evidence export' -Message 'Action buttons dispatch expected task names'

    $profileLoadCall = $script:StartCalls | Where-Object { $_.Name -eq 'Profile load' } | Select-Object -First 1
    Assert-Equal -Actual $profileLoadCall.Data.Profile -Expected 'qa-profile' -Message 'Profile load passes profile name'

    $profileSaveCall = $script:StartCalls | Where-Object { $_.Name -eq 'Profile save' } | Select-Object -First 1
    Assert-Equal -Actual $profileSaveCall.Data.Profile -Expected 'qa-profile' -Message 'Profile save passes profile name'

    $fullEvidenceCall = $script:StartCalls | Where-Object { $_.Name -eq 'Full evidence export' } | Select-Object -First 1
    Assert-True -Condition ($fullEvidenceCall.Data.Logs.Contains('System')) -Message 'Full evidence export receives UI logs'

    $networkCall = $script:StartCalls | Where-Object { $_.Name -eq 'Network setup' } | Select-Object -First 1
    Assert-Equal -Actual $networkCall.Data.Ip -Expected '10.20.30.40' -Message 'Network button passes IP'
    Assert-Equal -Actual $networkCall.Data.Mask -Expected '255.255.252.0' -Message 'Network button passes mask'

    $adCall = $script:StartCalls | Where-Object { $_.Name -eq 'AD DS promotion' } | Select-Object -First 1
    Assert-Equal -Actual $adCall.Data.Domain -Expected 'contoso.lab' -Message 'AD button passes domain'

    $exchangePrepCall = $script:StartCalls | Where-Object { $_.Name -eq 'Exchange AD prep' } | Select-Object -First 1
    Assert-Equal -Actual $exchangePrepCall.Data.Path -Expected 'E:\Exchange ISO' -Message 'Exchange prep button passes trimmed path'

    $exchangeInstallCall = $script:StartCalls | Where-Object { $_.Name -eq 'Exchange install' } | Select-Object -First 1
    Assert-Equal -Actual $exchangeInstallCall.Data.Path -Expected 'E:\Exchange ISO' -Message 'Exchange install button passes trimmed path'

    $eomtCall = $script:StartCalls | Where-Object { $_.Name -eq 'EOMT mitigation' } | Select-Object -First 1
    Assert-Equal -Actual $eomtCall.Data.Source -Expected 'C:\Tools\EOMT.ps1' -Message 'EOMT button passes source'

    $mitigationStatusCall = $script:StartCalls | Where-Object { $_.Name -eq 'Mitigation status' } | Select-Object -First 1
    Assert-Equal -Actual $mitigationStatusCall.Data.Count -Expected 0 -Message 'Mitigation status button passes empty data'

    $xssCall = $script:StartCalls | Where-Object { $_.Name -eq 'XSS email test' } | Select-Object -First 1
    Assert-Equal -Actual $xssCall.Data.Sender -Expected 'red@mylab.local' -Message 'XSS button passes sender'
    Assert-Equal -Actual $xssCall.Data.Payload -Expected '<a href="javascript:alert(''Link_Control_Payload'')">Lab validation link</a>' -Message 'XSS button passes selected payload'

    $buildCheckCall = $script:StartCalls | Where-Object { $_.Name -eq 'Exchange build check' } | Select-Object -First 1
    Assert-Equal -Actual $buildCheckCall.Data.Count -Expected 0 -Message 'Exchange build check passes empty data'

    $serviceCheckCall = $script:StartCalls | Where-Object { $_.Name -eq 'EM service check' } | Select-Object -First 1
    Assert-Equal -Actual $serviceCheckCall.Data.Count -Expected 0 -Message 'EM service check passes empty data'

    $mitigationCheckCall = $script:StartCalls | Where-Object { $_.Name -eq 'Mitigation state check' } | Select-Object -First 1
    Assert-Equal -Actual $mitigationCheckCall.Data.Count -Expected 0 -Message 'Mitigation state check passes empty data'

    $cspCall = $script:StartCalls | Where-Object { $_.Name -eq 'CSP header verification' } | Select-Object -First 1
    Assert-Equal -Actual $cspCall.Data.Url -Expected 'https://lab-ex02.exchange-lab.test/owa' -Message 'CSP verification passes trimmed OWA URL'

    $evidenceCall = $script:StartCalls | Where-Object { $_.Name -eq 'Evidence export' } | Select-Object -First 1
    Assert-Equal -Actual $evidenceCall.Data.Count -Expected 2 -Message 'Evidence export passes evidence bundle arguments'
    Assert-True -Condition ($evidenceCall.Data.Logs.Contains('CVE')) -Message 'CVE evidence export receives UI logs'
} finally {
    if ($form) { $form.Dispose() }
    . (Join-Path $WorkspaceRoot 'ExchangeLabManager.ps1') -NoRun
    $script:LabDataRoot = $qaStateRoot
}

Write-Host ''
Write-Host 'Profile, manifest, checkpoint, and cleanup helpers' -ForegroundColor Cyan
$stateForm = $null
try {
    $stateForm = New-MainForm
    $script:Ui.ProfilePath.Text = 'qa-saved-profile'
    $script:Ui.Ip.Text = '172.16.10.20'
    $script:Ui.Mask.Text = '255.255.254.0'
    $script:Ui.Domain.Text = 'qa.lab'
    $script:Ui.ExchangePath.Text = 'E:\QA Exchange'
    $script:Ui.Eomt.Text = 'C:\QA\EOMT.ps1'
    $script:Ui.Attacker.Text = 'qa-attacker@qa.lab'
    $script:Ui.Victim.Text = 'qa-victim@qa.lab'
    $script:Ui.Smtp.Text = '172.16.10.21'
    $script:Ui.Payload.SelectedIndex = 1
    $script:Ui.OwaUrl.Text = 'https://qa-ex01.qa.lab/owa'

    $reports = New-ReportList
    $profilePath = Save-LabProfile 'qa-saved-profile' (New-ReportBlock $reports)
    Assert-True -Condition (Test-Path -LiteralPath $profilePath -PathType Leaf) -Message 'Named lab profile saves to JSON'

    $script:Ui.Ip.Text = '10.0.0.99'
    Load-LabProfile 'qa-saved-profile' (New-ReportBlock $reports) | Out-Null
    Assert-Equal -Actual $script:Ui.Ip.Text -Expected '172.16.10.20' -Message 'Lab profile load restores static IP'
    Assert-Equal -Actual $script:Ui.Payload.SelectedIndex -Expected 1 -Message 'Lab profile load restores payload selection'

    $manifestPath = Export-RunManifest -TaskName 'qa manifest' -Report (New-ReportBlock $reports)
    Assert-True -Condition (Test-Path -LiteralPath $manifestPath -PathType Leaf) -Message 'Run manifest exports to app-data manifests folder'

    Update-LabCheckpoint -Milestone 'NetworkConfigured' -Status 'Complete' -Notes 'QA checkpoint' -Report (New-ReportBlock $reports) | Out-Null
    $checkpoint = Get-LabCheckpoint
    Assert-Equal -Actual $checkpoint.Milestones['NetworkConfigured'].Status -Expected 'Complete' -Message 'Checkpoint update persists milestone status'

    Clear-LabCheckpoint -Report (New-ReportBlock $reports) | Out-Null
    $resetCheckpoint = Get-LabCheckpoint
    Assert-Equal -Actual $resetCheckpoint.Milestones['NetworkConfigured'].Status -Expected 'Pending' -Message 'Checkpoint reset returns milestone to pending'

    $cleanupPreview = Invoke-LabCleanup -Mode Preview -Report (New-ReportBlock $reports)
    Assert-True -Condition ($cleanupPreview.Removed -eq 0) -Message 'Cleanup preview does not remove files'
} finally {
    if ($stateForm) { $stateForm.Dispose() }
}

Write-Host ''
Write-Host 'Async worker behavior' -ForegroundColor Cyan
$success = Invoke-WorkerScenario -Fail:$false
Assert-True -Condition (-not $success.TimedOut) -Message 'Worker success scenario completes'
Assert-Like -Actual $success.Log -Pattern '*QA worker progress*QA worker finished.*' -Message 'Worker success log contains progress and completion'
Assert-Equal -Actual $success.Pill -Expected 'QA worker complete' -Message 'Worker success pill is complete'
Assert-Equal -Actual $success.Status -Expected 'QA worker finished.' -Message 'Worker success status is done message'
Assert-Equal -Actual $success.ProgressStyle -Expected 'Continuous' -Message 'Worker success resets progress style'
Assert-True -Condition $success.ButtonsEnabled -Message 'Worker success re-enables buttons'

$failure = Invoke-WorkerScenario -Fail:$true
Assert-True -Condition (-not $failure.TimedOut) -Message 'Worker failure scenario completes'
Assert-Like -Actual $failure.Log -Pattern '*QA worker progress*ERROR: QA forced failure*' -Message 'Worker failure log contains error'
Assert-Equal -Actual $failure.Pill -Expected 'QA worker failed' -Message 'Worker failure pill is failed'
Assert-Equal -Actual $failure.Status -Expected 'Error: QA forced failure' -Message 'Worker failure status contains error'
Assert-True -Condition $failure.ButtonsEnabled -Message 'Worker failure re-enables buttons'

$busyForm = New-MainForm
try {
    $script:Busy = $true
    Start-LabTask 'Blocked task' $script:Ui.SystemLog $script:Ui.SystemPill $script:Ui.SystemProgress { } @{} 'Should not start' 'Should not finish'
    Assert-Like -Actual $script:Ui.SystemLog.Text -Pattern '*Another lab operation is still running.*' -Message 'Busy gate prevents concurrent task'
} finally {
    $script:Busy = $false
    $busyForm.Dispose()
}

Write-Host ''
Write-Host 'Process logging and Exchange setup command construction' -ForegroundColor Cyan
$tempRoot = Join-Path $env:TEMP ('ExchangeLabManager-QA-{0}' -f ([guid]::NewGuid()))
New-Item -Path $tempRoot -ItemType Directory -Force | Out-Null
try {
    $argScript = Join-Path $tempRoot 'echo-args.ps1'
    Set-Content -LiteralPath $argScript -Value "Write-Output ('ARGS=' + (`$args -join '|')); Write-Error 'ERR=expected warning'; exit 0" -Encoding UTF8
    $reports = New-ReportList
    $powershell = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
    Invoke-LoggedProcess -FilePath $powershell -Arguments @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $argScript, 'alpha', 'two words') -Report (New-ReportBlock $reports)
    $reportText = Get-ReportText $reports
    Assert-Like -Actual $reportText -Pattern '*ARGS=alpha|two words*' -Message 'Invoke-LoggedProcess preserves spaced arguments'
    Assert-Like -Actual $reportText -Pattern '*ERR=expected warning*' -Message 'Invoke-LoggedProcess captures stderr as warning'
    Assert-Like -Actual $reportText -Pattern '*Process completed with exit code 0.*' -Message 'Invoke-LoggedProcess reports success'

    $failScript = Join-Path $tempRoot 'exit-fail.ps1'
    Set-Content -LiteralPath $failScript -Value "Write-Output 'about to fail'; exit 7" -Encoding UTF8
    Assert-ThrowsLike -ScriptBlock {
        Invoke-LoggedProcess -FilePath $powershell -Arguments @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $failScript) -Report (New-ReportBlock (New-ReportList))
    } -ExpectedText 'Process exited with code 7' -Message 'Invoke-LoggedProcess throws on non-zero exit'

    $originalInvokeLoggedProcess = (Get-Command Invoke-LoggedProcess).ScriptBlock
    $script:ExchangeSetupCalls = New-Object System.Collections.Generic.List[object]
    Set-MockFunction -Name Invoke-LoggedProcess -Body {
        param($FilePath, $Arguments, $WorkingDirectory, $Report)
        $script:ExchangeSetupCalls.Add([pscustomobject]@{ FilePath = $FilePath; Arguments = @($Arguments); WorkingDirectory = $WorkingDirectory }) | Out-Null
    }
    $setupRoot = Join-Path $tempRoot 'Mounted ISO'
    New-Item -Path $setupRoot -ItemType Directory -Force | Out-Null
    New-Item -Path (Join-Path $setupRoot 'Setup.exe') -ItemType File -Force | Out-Null
    Invoke-ExchangeSetup -ExchangePath $setupRoot -Arguments @('/PrepareSchema') -Report { }
    Invoke-ExchangeSetup -ExchangePath (Join-Path $setupRoot 'Setup.exe') -Arguments @('/Mode:Install') -Report { }
    Assert-Equal -Actual $script:ExchangeSetupCalls.Count -Expected 2 -Message 'Invoke-ExchangeSetup dispatches both root and direct Setup.exe paths'
    Assert-Equal -Actual $script:ExchangeSetupCalls[0].WorkingDirectory -Expected $setupRoot -Message 'Invoke-ExchangeSetup uses ISO root as working directory'
    Assert-Equal -Actual $script:ExchangeSetupCalls[1].FilePath -Expected (Join-Path $setupRoot 'Setup.exe') -Message 'Invoke-ExchangeSetup accepts direct Setup.exe path'
    Assert-ThrowsLike -ScriptBlock {
        Invoke-ExchangeSetup -ExchangePath (Join-Path $tempRoot 'Missing ISO') -Arguments @('/help') -Report { }
    } -ExpectedText 'Setup.exe was not found' -Message 'Invoke-ExchangeSetup fails safely when Setup.exe is absent'
    Set-MockFunction -Name Invoke-LoggedProcess -Body $originalInvokeLoggedProcess
} finally {
    Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Host ''
Write-Host 'Destructive operation logic behind mocks' -ForegroundColor Cyan
Set-MockFunction -Name Assert-Admin -Body { }

$script:NetworkOps = New-Object System.Collections.Generic.List[object]
Set-MockFunction -Name Get-NetAdapter -Body {
    param($ErrorAction)
    [pscustomobject]@{ Name = 'Ethernet0'; Status = 'Up'; HardwareInterface = $true }
}
Set-MockFunction -Name Get-NetIPAddress -Body {
    param($InterfaceAlias, $IPAddress, $AddressFamily, $ErrorAction)
    if ($PSBoundParameters.ContainsKey('IPAddress')) { return $null }
    [pscustomobject]@{ IPAddress = '10.0.0.5' }
    [pscustomobject]@{ IPAddress = '169.254.1.8' }
}
Set-MockFunction -Name Remove-NetIPAddress -Body {
    param($InterfaceAlias, $IPAddress, [switch]$Confirm, $ErrorAction)
    $script:NetworkOps.Add([pscustomobject]@{ Op = 'Remove'; IPAddress = $IPAddress; InterfaceAlias = $InterfaceAlias }) | Out-Null
}
Set-MockFunction -Name New-NetIPAddress -Body {
    param($InterfaceAlias, $IPAddress, $PrefixLength, $DefaultGateway, $AddressFamily, $ErrorAction)
    $script:NetworkOps.Add([pscustomobject]@{ Op = 'New'; IPAddress = $IPAddress; PrefixLength = $PrefixLength; DefaultGateway = $DefaultGateway; InterfaceAlias = $InterfaceAlias }) | Out-Null
}
Set-MockFunction -Name Set-NetIPAddress -Body {
    param($InterfaceAlias, $IPAddress, $PrefixLength, $ErrorAction)
    $script:NetworkOps.Add([pscustomobject]@{ Op = 'Set'; IPAddress = $IPAddress; PrefixLength = $PrefixLength; InterfaceAlias = $InterfaceAlias }) | Out-Null
}
Set-MockFunction -Name Set-DnsClientServerAddress -Body {
    param($InterfaceAlias, $ServerAddresses, $ErrorAction)
    $script:NetworkOps.Add([pscustomobject]@{ Op = 'Dns'; InterfaceAlias = $InterfaceAlias; ServerAddresses = $ServerAddresses }) | Out-Null
}
$reports = New-ReportList
Set-StaticNetwork -Data @{ Ip = '192.168.100.10'; Mask = '255.255.255.0' } -Report (New-ReportBlock $reports)
Assert-Equal -Actual (($script:NetworkOps | ForEach-Object { $_.Op }) -join '|') -Expected 'Remove|New|Dns' -Message 'Network setup removes old IP, creates new IP, and sets DNS'
Assert-Equal -Actual ($script:NetworkOps | Where-Object Op -eq 'New' | Select-Object -ExpandProperty PrefixLength) -Expected 24 -Message 'Network setup uses converted prefix length'
Assert-Equal -Actual ($script:NetworkOps | Where-Object Op -eq 'New' | Select-Object -ExpandProperty DefaultGateway) -Expected '192.168.100.1' -Message 'Network setup derives default gateway'
Assert-Like -Actual (Get-ReportText $reports) -Pattern '*Network applied: 192.168.100.10/24*' -Message 'Network setup reports successful application'

$script:AdOps = New-Object System.Collections.Generic.List[object]
Set-MockFunction -Name Install-WindowsFeature -Body {
    param($Name, [switch]$IncludeManagementTools, $ErrorAction)
    $script:AdOps.Add([pscustomobject]@{ Op = 'InstallFeature'; Name = $Name; IncludeManagementTools = [bool]$IncludeManagementTools }) | Out-Null
}
Set-MockFunction -Name Import-Module -Body {
    param($Name, $ErrorAction)
    $script:AdOps.Add([pscustomobject]@{ Op = 'ImportModule'; Name = $Name }) | Out-Null
}
Set-MockFunction -Name Install-ADDSForest -Body {
    param($DomainName, $SafeModeAdministratorPassword, [switch]$InstallDns, [switch]$CreateDnsDelegation, [switch]$Force, [switch]$NoRebootOnCompletion, $ErrorAction)
    $script:AdOps.Add([pscustomobject]@{ Op = 'InstallForest'; DomainName = $DomainName; InstallDns = [bool]$InstallDns; NoRebootOnCompletion = [bool]$NoRebootOnCompletion }) | Out-Null
}
Assert-ThrowsLike -ScriptBlock { Install-AdAndPromote -Data @{ Domain = 'not valid' } -Report { } } -ExpectedText 'Invalid domain name' -Message 'AD promotion rejects invalid domain names'
Install-AdAndPromote -Data @{ Domain = 'corp.lab' } -Report (New-ReportBlock (New-ReportList))
Assert-Equal -Actual (($script:AdOps | ForEach-Object { $_.Op }) -join '|') -Expected 'InstallFeature|ImportModule|InstallForest' -Message 'AD promotion calls expected provisioning operations'
Assert-Equal -Actual ($script:AdOps | Where-Object Op -eq 'InstallForest' | Select-Object -ExpandProperty DomainName) -Expected 'corp.lab' -Message 'AD promotion passes requested domain name'

$originalInvokeExchangeSetup = (Get-Command Invoke-ExchangeSetup).ScriptBlock
$script:ExchangeOps = New-Object System.Collections.Generic.List[object]
Set-MockFunction -Name Invoke-ExchangeSetup -Body {
    param($ExchangePath, $Arguments, $Report)
    $script:ExchangeOps.Add([pscustomobject]@{ Path = $ExchangePath; Arguments = @($Arguments) }) | Out-Null
}
Prepare-ExchangeAd -Data @{ Path = 'D:\' } -Report { }
Install-Exchange -Data @{ Path = 'D:\' } -Report (New-ReportBlock (New-ReportList))
Assert-Equal -Actual $script:ExchangeOps.Count -Expected 3 -Message 'Exchange prep/install call setup three times'
Assert-Equal -Actual ($script:ExchangeOps[0].Arguments -join '|') -Expected '/PrepareSchema|/IAcceptExchangeServerLicenseTerms_DiagnosticDataON' -Message 'Exchange schema prep arguments are correct'
Assert-Equal -Actual ($script:ExchangeOps[1].Arguments -join '|') -Expected '/PrepareAD|/OrganizationName:TestLab|/IAcceptExchangeServerLicenseTerms_DiagnosticDataON' -Message 'Exchange AD prep arguments are correct'
Assert-Like -Actual ($script:ExchangeOps[2].Arguments -join '|') -Pattern '*/Mode:Install*/Roles:Mailbox*' -Message 'Exchange install arguments include mailbox install mode'
Set-MockFunction -Name Invoke-ExchangeSetup -Body $originalInvokeExchangeSetup

$script:EomtOps = New-Object System.Collections.Generic.List[object]
Set-MockFunction -Name Invoke-WebRequest -Body {
    param($Uri, $OutFile, [switch]$UseBasicParsing, $ErrorAction)
    Set-Content -LiteralPath $OutFile -Value '# mocked EOMT' -Encoding UTF8
    $script:EomtOps.Add([pscustomobject]@{ Op = 'Download'; Uri = $Uri; OutFile = $OutFile }) | Out-Null
}
Set-MockFunction -Name Invoke-LoggedProcess -Body {
    param($FilePath, $Arguments, $WorkingDirectory, $Report)
    $script:EomtOps.Add([pscustomobject]@{ Op = 'Run'; FilePath = $FilePath; Arguments = @($Arguments); WorkingDirectory = $WorkingDirectory }) | Out-Null
}
Apply-Eomt -Data @{ Source = 'https://example.test/EOMT.ps1' } -Report (New-ReportBlock (New-ReportList))
Assert-Equal -Actual (($script:EomtOps | ForEach-Object { $_.Op }) -join '|') -Expected 'Download|Run' -Message 'EOMT URL flow downloads then runs script'
Assert-Like -Actual (($script:EomtOps | Where-Object Op -eq 'Run').Arguments -join '|') -Pattern '*-File*EOMT.ps1*' -Message 'EOMT run flow invokes downloaded script'
Assert-ThrowsLike -ScriptBlock { Apply-Eomt -Data @{ Source = '' } -Report { } } -ExpectedText 'Enter an EOMT URL or local script path' -Message 'EOMT flow rejects empty source'

function Get-Mitigation {
    param($Identity, $ErrorAction)
    [pscustomobject]@{ Identity = $Identity; Applied = $true }
}
Set-MockFunction -Name Import-Module -Body { param($Name, $ErrorAction) }
Set-MockFunction -Name Get-WebConfiguration -Body {
    param($PSPath, $Filter, $ErrorAction)
    [pscustomobject]@{
        name = 'OWA CSP Mitigation'
        action = [pscustomobject]@{ value = 'Content-Security-Policy: default-src self' }
    }
}
$reports = New-ReportList
Check-Mitigation -Data @{} -Report (New-ReportBlock $reports)
$mitigationReport = Get-ReportText $reports
Assert-Like -Actual $mitigationReport -Pattern '*Get-Mitigation M2.1.x*' -Message 'Mitigation check reports Get-Mitigation output'
Assert-Like -Actual $mitigationReport -Pattern '*IIS CSP-style outbound rewrite rule found*' -Message 'Mitigation check reports CSP-style IIS rule'

$script:MailOps = New-Object System.Collections.Generic.List[object]
Set-MockFunction -Name Send-MailMessage -Body {
    param($From, $To, $Subject, $Body, [switch]$BodyAsHtml, $SmtpServer, $ErrorAction)
    $script:MailOps.Add([pscustomobject]@{ From = $From; To = $To; Subject = $Subject; Body = $Body; BodyAsHtml = [bool]$BodyAsHtml; SmtpServer = $SmtpServer }) | Out-Null
}
$reports = New-ReportList
Send-XssMail -Data @{ Sender = 'attacker@mylab.local'; Recipient = 'victim@mylab.local'; Smtp = '192.168.100.10'; Payload = '<b>payload</b>' } -Report (New-ReportBlock $reports)
Assert-Equal -Actual $script:MailOps.Count -Expected 1 -Message 'XSS test sends one SMTP message through mocked sender'
Assert-Equal -Actual $script:MailOps[0].BodyAsHtml -Expected $true -Message 'XSS test sends HTML mail'
Assert-Like -Actual $script:MailOps[0].Body -Pattern '*<b>payload</b>*' -Message 'XSS test embeds selected payload'
Assert-ThrowsLike -ScriptBlock {
    Send-XssMail -Data @{ Sender = ''; Recipient = 'victim@mylab.local'; Smtp = '192.168.100.10'; Payload = '<b>payload</b>' } -Report { }
} -ExpectedText 'Sender is required' -Message 'XSS test validates sender before SMTP'

Write-Host ''
Write-Host 'CVE validation helper logic behind mocks' -ForegroundColor Cyan
Set-MockFunction -Name Get-Command -Body {
    param($Name, $ErrorAction)
    if ($Name -eq 'ExSetup.exe') {
        return [pscustomobject]@{ Source = 'C:\Exchange\Bin\ExSetup.exe' }
    }
    throw "Mocked Get-Command only supports ExSetup.exe, not '$Name'."
}
Set-MockFunction -Name Get-Item -Body {
    param($Path)
    [pscustomobject]@{
        VersionInfo = [pscustomobject]@{
            ProductVersion = '15.2.1258.12'
            FileVersion = '15.02.1258.012'
        }
    }
}
Set-MockFunction -Name Get-Service -Body {
    param($Name, $ErrorAction)
    [pscustomobject]@{ Name = $Name; DisplayName = 'Microsoft Exchange Mitigation'; Status = 'Running'; StartType = 'Automatic' }
}
Set-MockFunction -Name Get-ExchangeServer -Body {
    param($ErrorAction)
    [pscustomobject]@{
        Name = 'LAB-EX01'
        Edition = 'Standard'
        AdminDisplayVersion = 'Version 15.2'
        MitigationsEnabled = $true
        MitigationsApplied = @('M2.1.x', 'LabControl')
        MitigationsBlocked = @()
    }
}
Set-MockFunction -Name Invoke-WebRequest -Body {
    param($Uri, [switch]$UseBasicParsing, $ErrorAction)
    [pscustomobject]@{
        Headers = @{
            'Content-Security-Policy' = "default-src 'self'; script-src-attr 'none'"
        }
    }
}
Set-MockFunction -Name Get-WebConfiguration -Body {
    param($PSPath, $Filter, $ErrorAction)
    [pscustomobject]@{ name = 'OWA CSP Mitigation'; enabled = 'true'; preCondition = 'ResponseIsHtml1' }
}

$reports = New-ReportList
$buildInfo = Get-ExchangeBuildInfo -Report (New-ReportBlock $reports)
Assert-Equal -Actual $buildInfo.Status -Expected 'Found' -Message 'CVE build helper returns found status'
Assert-Equal -Actual $buildInfo.Build -Expected '15.2.1258.12' -Message 'CVE build helper returns product version'
Assert-Like -Actual (Get-ReportText $reports) -Pattern '*Exchange Build: 15.2.1258.12*' -Message 'CVE build helper reports version'

$reports = New-ReportList
$serviceInfo = Check-EmServiceStatus -Report (New-ReportBlock $reports)
Assert-Equal -Actual $serviceInfo.Exists -Expected $true -Message 'EM service helper detects mocked service'
Assert-Equal -Actual $serviceInfo.Status -Expected 'Running' -Message 'EM service helper returns running status'

$reports = New-ReportList
$mitigationInfo = Get-MitigationApplied -Report (New-ReportBlock $reports)
Assert-True -Condition ([bool]$mitigationInfo.HasCveMitigation) -Message 'CVE mitigation helper detects M2/M2.1.x mitigation'
Assert-Like -Actual (Get-ReportText $reports) -Pattern '*CVE-2026-42897 mitigation status: ACTIVE*' -Message 'CVE mitigation helper reports active mitigation'

$reports = New-ReportList
Verify-OwaCspHeader -OwaUrl 'https://lab-ex01.exchange-lab.test/owa' -Report (New-ReportBlock $reports)
Assert-Like -Actual (Get-ReportText $reports) -Pattern "*script-src-attr 'none'*" -Message 'CSP helper reports active script-src-attr mitigation'
$reports = New-ReportList
Verify-OwaCspHeader -OwaUrl '' -Report (New-ReportBlock $reports)
Assert-Like -Actual (Get-ReportText $reports) -Pattern '*OWA URL is required*' -Message 'CSP helper validates missing URL'

$reports = New-ReportList
$evidenceResult = Export-CveEvidence -Report (New-ReportBlock $reports)
$evidencePath = $evidenceResult.Directory
$zipPath = $evidenceResult.ZipBundle
try {
    Assert-True -Condition (Test-Path -LiteralPath $evidencePath -PathType Container) -Message 'Evidence export creates an evidence directory'
    Assert-True -Condition ((Get-ChildItem -LiteralPath $evidencePath -File | Measure-Object).Count -ge 4) -Message 'Evidence export writes expected evidence files'
    if ($zipPath) {
        Assert-True -Condition (Test-Path -LiteralPath $zipPath -PathType Leaf) -Message 'Evidence export writes ZIP bundle'
    }
    Assert-Like -Actual (Get-ReportText $reports) -Pattern '*All evidence exported to:*' -Message 'Evidence export reports final bundle path'
} finally {
    if ($evidencePath -and (Test-Path -LiteralPath $evidencePath)) {
        Remove-Item -LiteralPath $evidencePath -Recurse -Force -ErrorAction SilentlyContinue
    }
    if ($zipPath -and (Test-Path -LiteralPath $zipPath)) {
        Remove-Item -LiteralPath $zipPath -Force -ErrorAction SilentlyContinue
    }
}

Write-Host ''
Write-Host 'Launcher failure path' -ForegroundColor Cyan
$launcherTemp = Join-Path $env:TEMP ('ExchangeLabManager-LauncherQA-{0}' -f ([guid]::NewGuid()))
New-Item -Path $launcherTemp -ItemType Directory -Force | Out-Null
try {
    Copy-Item -LiteralPath (Join-Path $WorkspaceRoot 'run-gui.ps1') -Destination $launcherTemp
    $powershell = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
    $output = & $powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $launcherTemp 'run-gui.ps1') 2>&1
    $exitCode = $LASTEXITCODE
    Assert-Equal -Actual $exitCode -Expected 1 -Message 'PowerShell launcher exits non-zero when GUI script is missing'
    Assert-Like -Actual ($output | Out-String) -Pattern '*Unable to find ExchangeLabManager.ps1*' -Message 'PowerShell launcher explains missing GUI script'
} finally {
    Remove-Item -LiteralPath $launcherTemp -Recurse -Force -ErrorAction SilentlyContinue
}

if ($qaStateRoot -and (Test-Path -LiteralPath $qaStateRoot)) {
    Remove-Item -LiteralPath $qaStateRoot -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Host ''
if ($script:Failures -eq 0) {
    Write-Result 'PASS' 'Full non-destructive and mocked QA suite passed.' Green
    exit 0
}

Write-Result 'FAIL' ("{0} full QA test(s) failed." -f $script:Failures) Red
exit 1
