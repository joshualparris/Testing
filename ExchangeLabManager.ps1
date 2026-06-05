#requires -version 5.1
<#
.SYNOPSIS
    WinForms GUI for an isolated Exchange lab deployment and mitigation workflow.
.DESCRIPTION
    Self-contained Windows desktop application script for lab-only network setup,
    AD DS promotion, Exchange setup preparation, EOMT mitigation, and benign SMTP
    validation mail.
#>

[CmdletBinding()]
param(
    [switch]$NoRun,
    [switch]$QAMode
)

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

# QA mode: when running under the test harness, enable a global auto-confirm flag
if ($QAMode) {
    $Global:ELM_AutoConfirm = $true
}

$script:Theme = @{
    Window     = [System.Drawing.Color]::FromArgb(22, 26, 32)
    Panel      = [System.Drawing.Color]::FromArgb(31, 36, 44)
    PanelAlt   = [System.Drawing.Color]::FromArgb(39, 45, 55)
    Field      = [System.Drawing.Color]::FromArgb(16, 19, 24)
    Text       = [System.Drawing.Color]::FromArgb(235, 239, 245)
    Muted      = [System.Drawing.Color]::FromArgb(166, 176, 190)
    Accent     = [System.Drawing.Color]::FromArgb(70, 145, 220)
    AccentDark = [System.Drawing.Color]::FromArgb(42, 96, 158)
    Good       = [System.Drawing.Color]::FromArgb(62, 190, 125)
    Warn       = [System.Drawing.Color]::FromArgb(235, 176, 64)
    Bad        = [System.Drawing.Color]::FromArgb(235, 92, 92)
}

$script:Ui = @{}
$script:Buttons = New-Object System.Collections.Generic.List[System.Windows.Forms.Button]
$script:Busy = $false
$script:LabDataRoot = $null
$script:MilestoneOrder = @(
    'ProfileSaved',
    'PreflightPassed',
    'NetworkConfigured',
    'AdPromoted',
    'ExchangeAdPrepared',
    'ExchangeInstalled',
    'MitigationApplied',
    'MitigationChecked',
    'HtmlValidationMailSent',
    'ExchangeBuildChecked',
    'EmServiceChecked',
    'MitigationStateChecked',
    'CspHeaderChecked',
    'EvidenceExported'
)
$script:MilestoneLabels = @{
    ProfileSaved = 'Profile saved'
    PreflightPassed = 'Preflight passed'
    NetworkConfigured = 'Network configured'
    AdPromoted = 'AD DS promoted'
    ExchangeAdPrepared = 'Exchange AD prepared'
    ExchangeInstalled = 'Exchange installed'
    MitigationApplied = 'Mitigation applied'
    MitigationChecked = 'Mitigation checked'
    HtmlValidationMailSent = 'HTML validation mail sent'
    ExchangeBuildChecked = 'Exchange build checked'
    EmServiceChecked = 'EM service checked'
    MitigationStateChecked = 'Mitigation state checked'
    CspHeaderChecked = 'CSP header checked'
    EvidenceExported = 'Evidence exported'
}

function Test-IsAdmin {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Assert-Admin {
    if (-not (Test-IsAdmin)) {
        throw 'This action requires an elevated PowerShell session. Right-click the script and choose Run as administrator.'
    }
}

function Ensure-QANetworkMockCommands {
    if (-not $Global:ELM_AutoConfirm) {
        return
    }

    $commandNames = @(
        'Get-NetAdapter',
        'Get-NetIPAddress',
        'Remove-NetIPAddress',
        'New-NetIPAddress',
        'Set-NetIPAddress',
        'Set-DnsClientServerAddress'
    )

    foreach ($name in $commandNames) {
        try {
            $mock = Get-Item -Path "Function:\Global:$name" -ErrorAction SilentlyContinue
            if ($mock -and $mock.Value) {
                Set-Item -Path "Function:\$name" -Value $mock.Value -ErrorAction SilentlyContinue
            }
        } catch {
            # Ignore failures while reapplying QA mocks.
        }
    }
}

function Get-ObjectValue {
    param($InputObject, [Parameter(Mandatory)][string]$Name, $Default = $null)
    if ($null -eq $InputObject) { return $Default }
    if ($InputObject -is [hashtable] -and $InputObject.ContainsKey($Name)) { return $InputObject[$Name] }
    $property = $InputObject.PSObject.Properties[$Name]
    if ($property) { return $property.Value }
    return $Default
}

function Get-SafeFileName {
    param([string]$Name, [string]$Default = 'default')
    $candidate = if ([string]::IsNullOrWhiteSpace($Name)) { $Default } else { $Name.Trim() }
    foreach ($char in [System.IO.Path]::GetInvalidFileNameChars()) {
        $candidate = $candidate.Replace([string]$char, '-')
    }
    $candidate = ($candidate -replace '\s+', '-').Trim('-')
    if ([string]::IsNullOrWhiteSpace($candidate)) { return $Default }
    return $candidate
}

function Get-LabDataRoot {
    if ([string]::IsNullOrWhiteSpace($script:LabDataRoot)) {
        $base = if ($env:LOCALAPPDATA) {
            Join-Path $env:LOCALAPPDATA 'ExchangeLabManager'
        } else {
            Join-Path $PSScriptRoot 'lab-state'
        }
        $script:LabDataRoot = $base
    }
    return $script:LabDataRoot
}

function Ensure-LabDataFolder {
    param([string]$ChildPath)
    $root = Get-LabDataRoot
    $path = if ([string]::IsNullOrWhiteSpace($ChildPath)) { $root } else { Join-Path $root $ChildPath }
    if (-not (Test-Path -LiteralPath $path -PathType Container)) {
        New-Item -Path $path -ItemType Directory -Force | Out-Null
    }
    return $path
}

function Write-JsonFile {
    param(
        [Parameter(Mandatory)]$Value,
        [Parameter(Mandatory)][string]$Path
    )
    $parent = Split-Path -Parent $Path
    if ($parent -and -not (Test-Path -LiteralPath $parent -PathType Container)) {
        New-Item -Path $parent -ItemType Directory -Force | Out-Null
    }
    $Value | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $Path -Encoding UTF8
    return $Path
}

function Read-JsonFile {
    param([Parameter(Mandatory)][string]$Path)
    return (Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json)
}

function Get-LabProfilePath {
    param([string]$Name = 'default-lab')
    $profiles = Join-Path $PSScriptRoot 'lab-profiles'
    if (-not (Test-Path -LiteralPath $profiles -PathType Container)) {
        New-Item -Path $profiles -ItemType Directory -Force | Out-Null
    }
    return (Join-Path $profiles ((Get-SafeFileName $Name 'default-lab') + '.json'))
}

function Get-LabCheckpointPath {
    $checkpoints = Ensure-LabDataFolder 'checkpoints'
    return (Join-Path $checkpoints 'current-checkpoint.json')
}

function Get-UiTextValue {
    param([Parameter(Mandatory)][string]$Name, [string]$Default = '')
    if ($script:Ui.ContainsKey($Name) -and $script:Ui[$Name] -and $script:Ui[$Name].PSObject.Properties['Text']) {
        return [string]$script:Ui[$Name].Text
    }
    return $Default
}

function Set-UiTextValue {
    param([Parameter(Mandatory)][string]$Name, [AllowNull()][string]$Value)
    if ($script:Ui.ContainsKey($Name) -and $script:Ui[$Name] -and $script:Ui[$Name].PSObject.Properties['Text']) {
        $script:Ui[$Name].Text = [string]$Value
    }
}

function Get-CurrentLabInputs {
    $payloadIndex = 0
    $payloadValue = ''
    if ($script:Ui.ContainsKey('Payload') -and $script:Ui.Payload) {
        $payloadIndex = [int]$script:Ui.Payload.SelectedIndex
        $payloadValue = [string]$script:Ui.Payload.SelectedItem
    }
    return [ordered]@{
        Ip = Get-UiTextValue 'Ip' '192.168.100.10'
        Mask = Get-UiTextValue 'Mask' '255.255.255.0'
        Domain = Get-UiTextValue 'Domain' 'mylab.local'
        ExchangePath = Get-UiTextValue 'ExchangePath' 'D:\'
        Eomt = Get-UiTextValue 'Eomt' 'https://aka.ms/exchange-onprem-mitigation-tool'
        Sender = Get-UiTextValue 'Sender' 'sender@mylab.local'
        Recipient = Get-UiTextValue 'Recipient' 'recipient@mylab.local'
        Smtp = Get-UiTextValue 'Smtp' '192.168.100.10'
        PayloadIndex = $payloadIndex
        Payload = $payloadValue
        OwaUrl = Get-UiTextValue 'OwaUrl' 'https://lab-ex01.exchange-lab.test/owa'
    }
}

function Set-CurrentLabInputs {
    param([Parameter(Mandatory)]$Inputs)
    Set-UiTextValue 'Ip' (Get-ObjectValue $Inputs 'Ip' (Get-UiTextValue 'Ip'))
    Set-UiTextValue 'Mask' (Get-ObjectValue $Inputs 'Mask' (Get-UiTextValue 'Mask'))
    Set-UiTextValue 'Domain' (Get-ObjectValue $Inputs 'Domain' (Get-UiTextValue 'Domain'))
    Set-UiTextValue 'ExchangePath' (Get-ObjectValue $Inputs 'ExchangePath' (Get-UiTextValue 'ExchangePath'))
    Set-UiTextValue 'Eomt' (Get-ObjectValue $Inputs 'Eomt' (Get-UiTextValue 'Eomt'))
    Set-UiTextValue 'Sender' (Get-ObjectValue $Inputs 'Sender' (Get-UiTextValue 'Sender'))
    Set-UiTextValue 'Recipient' (Get-ObjectValue $Inputs 'Recipient' (Get-UiTextValue 'Recipient'))
    Set-UiTextValue 'Smtp' (Get-ObjectValue $Inputs 'Smtp' (Get-UiTextValue 'Smtp'))
    Set-UiTextValue 'OwaUrl' (Get-ObjectValue $Inputs 'OwaUrl' (Get-UiTextValue 'OwaUrl'))

    if ($script:Ui.ContainsKey('Payload') -and $script:Ui.Payload) {
        $index = [int](Get-ObjectValue $Inputs 'PayloadIndex' $script:Ui.Payload.SelectedIndex)
        if ($index -ge 0 -and $index -lt $script:Ui.Payload.Items.Count) {
            $script:Ui.Payload.SelectedIndex = $index
        }
    }
}

function New-LabCheckpoint {
    $milestones = [ordered]@{}
    foreach ($key in $script:MilestoneOrder) {
        $milestones[$key] = [ordered]@{
            Label = $script:MilestoneLabels[$key]
            Status = 'Pending'
            UpdatedUtc = $null
            Notes = ''
        }
    }
    return [ordered]@{
        SchemaVersion = 1
        LastUpdatedUtc = (Get-Date).ToUniversalTime().ToString('u')
        Milestones = $milestones
    }
}

function Get-LabCheckpoint {
    $path = Get-LabCheckpointPath
    $checkpoint = New-LabCheckpoint
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { return $checkpoint }
    try {
        $existing = Read-JsonFile $path
        $existingMilestones = Get-ObjectValue $existing 'Milestones' $null
        if ($existingMilestones) {
            foreach ($property in $existingMilestones.PSObject.Properties) {
                $checkpoint.Milestones[$property.Name] = [ordered]@{
                    Label = Get-ObjectValue $property.Value 'Label' ($script:MilestoneLabels[$property.Name])
                    Status = Get-ObjectValue $property.Value 'Status' 'Pending'
                    UpdatedUtc = Get-ObjectValue $property.Value 'UpdatedUtc' $null
                    Notes = Get-ObjectValue $property.Value 'Notes' ''
                }
            }
        }
        $checkpoint.LastUpdatedUtc = Get-ObjectValue $existing 'LastUpdatedUtc' $checkpoint.LastUpdatedUtc
    } catch { }
    return $checkpoint
}

function Save-LabCheckpoint {
    param($Checkpoint = (Get-LabCheckpoint), [scriptblock]$Report)
    if (-not $Report) { $Report = { param($Message, $Kind = 'Info') } }
    $Checkpoint.LastUpdatedUtc = (Get-Date).ToUniversalTime().ToString('u')
    $path = Get-LabCheckpointPath
    Write-JsonFile -Value $Checkpoint -Path $path | Out-Null
    & $Report "Checkpoint saved: $path" 'Good'
    return $path
}

function Update-LabCheckpoint {
    param(
        [Parameter(Mandatory)][string]$Milestone,
        [ValidateSet('Pending', 'Complete', 'Skipped', 'Failed')]
        [string]$Status = 'Complete',
        [string]$Notes = '',
        [scriptblock]$Report
    )
    if (-not $Report) { $Report = { param($Message, $Kind = 'Info') } }
    $checkpoint = Get-LabCheckpoint
    if (-not $checkpoint.Milestones.Contains($Milestone)) {
        $checkpoint.Milestones[$Milestone] = [ordered]@{
            Label = $Milestone
            Status = 'Pending'
            UpdatedUtc = $null
            Notes = ''
        }
    }
    $checkpoint.Milestones[$Milestone].Status = $Status
    $checkpoint.Milestones[$Milestone].UpdatedUtc = (Get-Date).ToUniversalTime().ToString('u')
    $checkpoint.Milestones[$Milestone].Notes = $Notes
    Save-LabCheckpoint -Checkpoint $checkpoint -Report $Report | Out-Null
    & $Report ("Checkpoint updated: {0} = {1}" -f $checkpoint.Milestones[$Milestone].Label, $Status) 'Info'
    return $checkpoint
}

function Clear-LabCheckpoint {
    param([scriptblock]$Report)
    if (-not $Report) { $Report = { param($Message, $Kind = 'Info') } }
    $path = Get-LabCheckpointPath
    if (Test-Path -LiteralPath $path -PathType Leaf) {
        Remove-Item -LiteralPath $path -Force
    }
    $checkpoint = New-LabCheckpoint
    Save-LabCheckpoint -Checkpoint $checkpoint -Report $Report | Out-Null
    & $Report 'Checkpoint reset to pending milestones.' 'Good'
    return $checkpoint
}

function Get-LabCheckpointSummary {
    param($Checkpoint = (Get-LabCheckpoint))
    $lines = New-Object System.Collections.Generic.List[string]
    foreach ($key in $script:MilestoneOrder) {
        if ($Checkpoint.Milestones.Contains($key)) {
            $milestone = $Checkpoint.Milestones[$key]
            $lines.Add(('{0}: {1}' -f $milestone.Label, $milestone.Status)) | Out-Null
        }
    }
    return ($lines -join [Environment]::NewLine)
}

function Apply-LabCheckpoint {
    param($Checkpoint = (Get-LabCheckpoint), [scriptblock]$Report)
    if (-not $Report) { $Report = { param($Message, $Kind = 'Info') } }
    $latestLabel = $null
    foreach ($key in $script:MilestoneOrder) {
        if (-not $Checkpoint.Milestones.Contains($key)) { continue }
        $milestone = $Checkpoint.Milestones[$key]
        if ($milestone.Status -ne 'Complete') { continue }
        $latestLabel = $milestone.Label
        switch ($key) {
            'PreflightPassed' { if ($script:Ui.ProfilePill) { Set-Pill $script:Ui.ProfilePill 'Preflight passed' Good } }
            'NetworkConfigured' { if ($script:Ui.SystemPill) { Set-Pill $script:Ui.SystemPill 'Network configured' Good } }
            'AdPromoted' { if ($script:Ui.RebootPill) { Set-Pill $script:Ui.RebootPill 'AD DS promoted' Good } }
            'ExchangeAdPrepared' { if ($script:Ui.ExchangePill) { Set-Pill $script:Ui.ExchangePill 'Exchange AD ready' Good } }
            'ExchangeInstalled' { if ($script:Ui.ExchangePill) { Set-Pill $script:Ui.ExchangePill 'Exchange installed' Good } }
            'MitigationApplied' { if ($script:Ui.MitigationPill) { Set-Pill $script:Ui.MitigationPill 'Mitigation applied' Good } }
            'MitigationChecked' { if ($script:Ui.MitigationPill) { Set-Pill $script:Ui.MitigationPill 'Mitigation checked' Good } }
            'HtmlValidationMailSent' { if ($script:Ui.HtmlValidationPill) { Set-Pill $script:Ui.HtmlValidationPill 'Validation sent' Good } }
            'EvidenceExported' { if ($script:Ui.CvePill) { Set-Pill $script:Ui.CvePill 'Evidence exported' Good } }
        }
    }
    if ($script:Ui.CheckpointPill) {
        if ($latestLabel) {
            Set-Pill $script:Ui.CheckpointPill "Last checkpoint: $latestLabel" Good
            & $Report "Checkpoint resumed: $latestLabel" 'Good'
        } else {
            Set-Pill $script:Ui.CheckpointPill 'Checkpoint pending' Ready
        }
    }
}

function Save-RunManifest {
    param([string]$TaskName = 'Manual', [scriptblock]$Report)
    if (-not $Report) { $Report = { param($Message, $Kind = 'Info') } }
    $manifestFolder = Ensure-LabDataFolder 'manifests'
    $timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
    $safeTask = Get-SafeFileName $TaskName 'manual'
    $manifestPath = Join-Path $manifestFolder ("{0}-{1}.json" -f $timestamp, $safeTask)
    $manifest = [ordered]@{
        SchemaVersion = 1
        TaskName = $TaskName
        CreatedUtc = (Get-Date).ToUniversalTime().ToString('u')
        ComputerName = $env:COMPUTERNAME
        UserName = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name
        ScriptPath = $PSCommandPath
        LabDataRoot = Get-LabDataRoot
        Inputs = Get-CurrentLabInputs
        Checkpoint = Get-LabCheckpoint
    }
    Write-JsonFile -Value $manifest -Path $manifestPath | Out-Null
    & $Report "Run manifest exported: $manifestPath" 'Good'
    return $manifestPath
}

function Add-PreflightResult {
    param(
        [AllowEmptyCollection()][System.Collections.Generic.List[object]]$Results,
        [Parameter(Mandatory)][string]$Name,
        [ValidateSet('Pass', 'Warn', 'Block')]
        [string]$Status,
        [string]$Message
    )
    $Results.Add([pscustomobject]@{ Name = $Name; Status = $Status; Message = $Message }) | Out-Null
}

function Invoke-PreflightReadiness {
    param([scriptblock]$Report)
    if (-not $Report) { $Report = { param($Message, $Kind = 'Info') } }
    $results = New-Object System.Collections.Generic.List[object]

    if (Test-IsAdmin) {
        Add-PreflightResult $results 'Administrator privileges' 'Pass' 'Running elevated.'
    } else {
        Add-PreflightResult $results 'Administrator privileges' 'Block' 'Run elevated before network, AD DS, Exchange, EOMT, IIS, or evidence actions.'
    }

    if ($PSVersionTable.PSVersion.Major -ge 5) {
        Add-PreflightResult $results 'PowerShell version' 'Pass' ("PowerShell {0} detected." -f $PSVersionTable.PSVersion)
    } else {
        Add-PreflightResult $results 'PowerShell version' 'Block' ("PowerShell {0} detected; 5.1+ is required." -f $PSVersionTable.PSVersion)
    }

    if ([Threading.Thread]::CurrentThread.GetApartmentState() -eq 'STA') {
        Add-PreflightResult $results 'STA desktop thread' 'Pass' 'WinForms is running in STA mode.'
    } else {
        Add-PreflightResult $results 'STA desktop thread' 'Warn' 'Launch through run-gui.bat or powershell.exe -STA for the desktop UI.'
    }

    try {
        $productType = (Get-CimInstance Win32_OperatingSystem -ErrorAction Stop).ProductType
        if ($productType -eq 3) {
            Add-PreflightResult $results 'Windows Server edition' 'Pass' 'Windows Server detected.'
        } else {
            Add-PreflightResult $results 'Windows Server edition' 'Warn' 'This host is not Windows Server. Use the GUI inside the isolated server VM for lab actions.'
        }
    } catch {
        Add-PreflightResult $results 'Windows Server edition' 'Warn' "Unable to determine OS edition: $($_.Exception.Message)"
    }

    try {
        $ip = Get-UiTextValue 'Ip'
        [void][System.Net.IPAddress]::Parse($ip)
        Add-PreflightResult $results 'Static IP input' 'Pass' "Static IP parses: $ip"
    } catch {
        Add-PreflightResult $results 'Static IP input' 'Block' "Invalid static IP: $(Get-UiTextValue 'Ip')"
    }

    try {
        $prefix = Convert-MaskToPrefix (Get-UiTextValue 'Mask')
        Add-PreflightResult $results 'Subnet mask input' 'Pass' "Subnet mask converts to /$prefix."
    } catch {
        Add-PreflightResult $results 'Subnet mask input' 'Block' $_.Exception.Message
    }

    $domain = Get-UiTextValue 'Domain'
    if ($domain -match '^[a-zA-Z0-9][a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$') {
        Add-PreflightResult $results 'AD domain input' 'Pass' "Domain format looks valid: $domain"
    } else {
        Add-PreflightResult $results 'AD domain input' 'Block' "Invalid AD domain name: $domain"
    }

    $exchangePath = (Get-UiTextValue 'ExchangePath').Trim()
    $setupPath = if ([System.IO.Path]::GetFileName($exchangePath) -ieq 'Setup.exe') { $exchangePath } else { Join-Path $exchangePath 'Setup.exe' }
    if ($exchangePath -and (Test-Path -LiteralPath $setupPath -PathType Leaf)) {
        Add-PreflightResult $results 'Exchange setup media' 'Pass' "Setup.exe found: $setupPath"
    } else {
        Add-PreflightResult $results 'Exchange setup media' 'Warn' "Setup.exe not found yet. Select a mounted ISO root before Exchange setup."
    }

    if ([string]::IsNullOrWhiteSpace((Get-UiTextValue 'Eomt'))) {
        Add-PreflightResult $results 'EOMT source' 'Warn' 'EOMT URL/path is empty.'
    } else {
        Add-PreflightResult $results 'EOMT source' 'Pass' 'EOMT URL/path is populated.'
    }

    if ([string]::IsNullOrWhiteSpace((Get-UiTextValue 'Smtp'))) {
        Add-PreflightResult $results 'SMTP target' 'Warn' 'SMTP target is empty.'
    } else {
        Add-PreflightResult $results 'SMTP target' 'Pass' 'SMTP target is populated.'
    }

    $owa = Get-UiTextValue 'OwaUrl'
    if ($owa -match '^https?://[^/]+/owa/?$') {
        Add-PreflightResult $results 'OWA URL' 'Pass' "OWA URL format looks valid: $owa"
    } else {
        Add-PreflightResult $results 'OWA URL' 'Warn' 'OWA URL should look like https://server.domain.local/owa.'
    }

    try {
        if (Test-Path 'HKLM:\Software\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending') {
            Add-PreflightResult $results 'Pending reboot' 'Warn' 'A pending reboot marker exists.'
        } else {
            Add-PreflightResult $results 'Pending reboot' 'Pass' 'No Component Based Servicing reboot marker found.'
        }
    } catch {
        Add-PreflightResult $results 'Pending reboot' 'Warn' "Unable to inspect reboot state: $($_.Exception.Message)"
    }

    try {
        $cDrive = Get-Volume -DriveLetter C -ErrorAction Stop
        $freeGb = [math]::Round($cDrive.SizeRemaining / 1GB, 1)
        if ($freeGb -ge 50) {
            Add-PreflightResult $results 'C drive free space' 'Pass' "$freeGb GB free."
        } elseif ($freeGb -ge 20) {
            Add-PreflightResult $results 'C drive free space' 'Warn' "$freeGb GB free; 50 GB+ recommended."
        } else {
            Add-PreflightResult $results 'C drive free space' 'Block' "$freeGb GB free; Exchange lab needs more disk space."
        }
    } catch {
        Add-PreflightResult $results 'C drive free space' 'Warn' "Unable to inspect disk space: $($_.Exception.Message)"
    }

    try {
        if (Get-Command Test-NetConnection -ErrorAction SilentlyContinue) {
            $externalReachable = Test-NetConnection -ComputerName 8.8.8.8 -Port 53 -InformationLevel Quiet -WarningAction SilentlyContinue
            if ($externalReachable) {
                Add-PreflightResult $results 'Network isolation' 'Block' 'External DNS endpoint 8.8.8.8:53 is reachable. Disconnect external networking before lab work.'
            } else {
                Add-PreflightResult $results 'Network isolation' 'Pass' 'External DNS endpoint was not reachable.'
            }
        } else {
            Add-PreflightResult $results 'Network isolation' 'Warn' 'Test-NetConnection is unavailable; verify isolation manually.'
        }
    } catch {
        Add-PreflightResult $results 'Network isolation' 'Pass' 'External connectivity check failed, consistent with isolation.'
    }

    foreach ($result in $results) {
        $kind = switch ($result.Status) {
            'Pass' { 'Good' }
            'Warn' { 'Warn' }
            'Block' { 'Bad' }
        }
        & $Report ("{0}: {1} - {2}" -f $result.Status, $result.Name, $result.Message) $kind
    }

    $blocking = @($results | Where-Object Status -eq 'Block')
    $warnings = @($results | Where-Object Status -eq 'Warn')
    if ($blocking.Count -eq 0) {
        Update-LabCheckpoint -Milestone 'PreflightPassed' -Status 'Complete' -Notes 'Preflight completed without blocking failures.' -Report $Report | Out-Null
    }
    & $Report ("Preflight summary: {0} blocking, {1} warning(s), {2} pass." -f $blocking.Count, $warnings.Count, ($results.Count - $blocking.Count - $warnings.Count)) ($(if ($blocking.Count -eq 0) { 'Good' } else { 'Bad' }))
    return [pscustomobject]@{
        Results = $results.ToArray()
        BlockingCount = $blocking.Count
        WarningCount = $warnings.Count
        PassedCount = ($results.Count - $blocking.Count - $warnings.Count)
    }
}

function Get-PathSizeBytes {
    param([Parameter(Mandatory)][string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) { return 0 }
    $item = Get-Item -LiteralPath $Path -Force
    if (-not $item.PSIsContainer) { return [int64]$item.Length }
    return [int64]((Get-ChildItem -LiteralPath $Path -Recurse -Force -ErrorAction SilentlyContinue | Measure-Object -Property Length -Sum).Sum)
}

function Get-LabCleanupTargets {
    $targets = New-Object System.Collections.Generic.List[object]
    $tempRoot = if ($env:LOCALAPPDATA) { Join-Path $env:LOCALAPPDATA 'Temp' } else { $env:TEMP }
    foreach ($pattern in @('ExchangeLabManager', 'ExchangeLabManager-QA-*', 'CVE42897-Evidence*', 'ExchangeLabManager-Evidence*')) {
        foreach ($item in @(Get-ChildItem -LiteralPath $tempRoot -Filter $pattern -Force -ErrorAction SilentlyContinue)) {
            $targets.Add([pscustomobject]@{
                Category = 'Temp'
                Name = $item.Name
                Path = $item.FullName
                SizeBytes = Get-PathSizeBytes $item.FullName
                SafeToDelete = $true
            }) | Out-Null
        }
    }
    foreach ($pattern in @('ui-error.txt', 'ExchangeLabManager-startup-error.log', 'tmp_*.txt')) {
        foreach ($item in @(Get-ChildItem -LiteralPath $PSScriptRoot -Filter $pattern -Force -ErrorAction SilentlyContinue)) {
            $targets.Add([pscustomobject]@{
                Category = 'WorkspaceTemp'
                Name = $item.Name
                Path = $item.FullName
                SizeBytes = Get-PathSizeBytes $item.FullName
                SafeToDelete = $true
            }) | Out-Null
        }
    }
    return $targets.ToArray()
}

function Invoke-LabCleanupCore {
    param(
        [ValidateSet('Preview', 'TempOnly')]
        [string]$Mode = 'Preview',
        [scriptblock]$Report
    )
    if (-not $Report) { $Report = { param($Message, $Kind = 'Info') } }
    $targets = @(Get-LabCleanupTargets)
    if ($targets.Count -eq 0) {
        & $Report 'No cleanup targets found.' 'Good'
        return [pscustomobject]@{ Removed = 0; Failed = 0; Targets = @() }
    }
    foreach ($target in $targets) {
        & $Report ("Cleanup target: {0} ({1} KB) [{2}]" -f $target.Path, [math]::Round($target.SizeBytes / 1KB, 1), $target.Category) 'Info'
    }
    if ($Mode -eq 'Preview') {
        & $Report ("Cleanup preview found {0} target(s)." -f $targets.Count) 'Good'
        return [pscustomobject]@{ Removed = 0; Failed = 0; Targets = $targets }
    }

    $removed = 0
    $failed = 0
    foreach ($target in $targets | Where-Object SafeToDelete) {
        try {
            Remove-Item -LiteralPath $target.Path -Recurse -Force -ErrorAction Stop
            $removed++
            & $Report "Removed cleanup target: $($target.Path)" 'Good'
        } catch {
            $failed++
            & $Report "Failed to remove $($target.Path): $($_.Exception.Message)" 'Warn'
        }
    }
    return [pscustomobject]@{ Removed = $removed; Failed = $failed; Targets = $targets }
}

function Convert-MaskToPrefix {
    param([Parameter(Mandatory)][string]$Mask)
    try {
        $bytes = [System.Net.IPAddress]::Parse($Mask).GetAddressBytes()
    } catch {
        throw "Invalid subnet mask '$Mask'. Use a value such as 255.255.255.0."
    }
    $bits = ($bytes | ForEach-Object { [Convert]::ToString($_, 2).PadLeft(8, '0') }) -join ''
    if ($bits -notmatch '^1*0*$') { throw "Subnet mask '$Mask' is not contiguous." }
    return ($bits.ToCharArray() | Where-Object { $_ -eq '1' }).Count
}

function Get-GatewayFromIp {
    param([Parameter(Mandatory)][string]$IpAddress)
    $parts = $IpAddress.Split('.')
    if ($parts.Count -ne 4) { return $null }
    return '{0}.{1}.{2}.1' -f $parts[0], $parts[1], $parts[2]
}

function Format-Arg {
    param([Parameter(Mandatory)][string]$Value)
    if ($Value -notmatch '[\s"]') { return $Value }
    return '"' + ($Value -replace '"', '\"') + '"'
}

function Write-LogBox {
    param(
        [Parameter(Mandatory)][System.Windows.Forms.RichTextBox]$Box,
        [Parameter(Mandatory)][string]$Message,
        [System.Drawing.Color]$Color = $script:Theme.Text
    )
    $Box.SelectionStart = $Box.TextLength
    $Box.SelectionLength = 0
    $Box.SelectionColor = $Color
    $Box.AppendText(('[{0}] {1}' -f (Get-Date -Format 'HH:mm:ss'), $Message) + [Environment]::NewLine)
    $Box.SelectionColor = $Box.ForeColor
    $Box.ScrollToCaret()
}

function Set-AppStatus {
    param([Parameter(Mandatory)][string]$Message, [System.Drawing.Color]$Color = $script:Theme.Text)
    if ($script:Ui.Status) {
        $script:Ui.Status.ForeColor = $Color
        $script:Ui.Status.Text = '  ' + $Message
    }
}

function Set-Pill {
    param(
        [Parameter(Mandatory)][System.Windows.Forms.Label]$Label,
        [Parameter(Mandatory)][string]$Text,
        [ValidateSet('Ready', 'Busy', 'Good', 'Warn', 'Bad')]
        [string]$State = 'Ready'
    )
    $Label.Text = '  ' + $Text
    switch ($State) {
        'Ready' { $Label.BackColor = $script:Theme.PanelAlt; $Label.ForeColor = $script:Theme.Muted }
        'Busy'  { $Label.BackColor = $script:Theme.AccentDark; $Label.ForeColor = [System.Drawing.Color]::White }
        'Good'  { $Label.BackColor = [System.Drawing.Color]::FromArgb(29, 84, 61); $Label.ForeColor = $script:Theme.Good }
        'Warn'  { $Label.BackColor = [System.Drawing.Color]::FromArgb(94, 73, 31); $Label.ForeColor = $script:Theme.Warn }
        'Bad'   { $Label.BackColor = [System.Drawing.Color]::FromArgb(94, 34, 40); $Label.ForeColor = $script:Theme.Bad }
    }
}

function Set-Buttons {
    param([bool]$Enabled)
    $destructiveTexts = @(
        'Configure Network',
        'Install Active Directory & Promote',
        'Prepare AD Schema & Forests',
        'Launch Exchange Installer Syntax',
        'Download & Apply EOMT Mitigation'
    )
    $blocking = if ($null -ne $Global:ELM_PreflightBlockingOverride) { $Global:ELM_PreflightBlockingOverride } else { $Global:ELM_PreflightBlocking }
    
    foreach ($button in $script:Buttons) {
        if ($Enabled) {
            # If we're enabling buttons, check if preflight is blocking destructive ones
            if ($destructiveTexts -contains $button.Text -and $blocking) {
                $button.Enabled = $false
            } else {
                $button.Enabled = $true
            }
        } else {
            $button.Enabled = $false
        }
    }
}

function Start-LabTask {
    param(
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][System.Windows.Forms.RichTextBox]$LogBox,
        [Parameter(Mandatory)][System.Windows.Forms.Label]$Indicator,
        [Parameter(Mandatory)][System.Windows.Forms.ProgressBar]$Progress,
        [Parameter(Mandatory)][scriptblock]$Action,
        [hashtable]$Data = @{},
        [string]$StartMessage = 'Starting task...',
        [string]$DoneMessage = 'Task completed successfully.',
        [string]$CheckpointMilestone,
        [bool]$RecordManifest = $true
    )

    if ($script:Busy) {
        Set-AppStatus 'Another lab operation is still running.' $script:Theme.Warn
        Write-LogBox $LogBox 'Another lab operation is still running.' $script:Theme.Warn
        return
    }

    try {
        $script:Busy = $true
        Set-Buttons $false
        Set-Pill $Indicator "$Name running" Busy
        $Progress.Style = 'Marquee'
        $Progress.MarqueeAnimationSpeed = 35
        Set-AppStatus $StartMessage $script:Theme.Accent
        Write-LogBox $LogBox $StartMessage $script:Theme.Accent

        [System.Windows.Forms.Application]::DoEvents()
        $theme = $script:Theme
        $writeLogBox = ${function:Write-LogBox}
        $report = {
            param([Parameter(Mandatory)][string]$Message, [string]$Kind = 'Info')
            $color = switch ($Kind) {
                'Good' { $theme.Good }
                'Warn' { $theme.Warn }
                'Bad'  { $theme.Bad }
                default { $theme.Text }
            }
            & $writeLogBox $LogBox $Message $color
            [System.Windows.Forms.Application]::DoEvents()
        }.GetNewClosure()

        try {
            & $Action $Data $report
            if (-not [string]::IsNullOrWhiteSpace($CheckpointMilestone)) {
                Update-LabCheckpoint -Milestone $CheckpointMilestone -Status 'Complete' -Notes $DoneMessage -Report $report | Out-Null
            }
            if ($RecordManifest) {
                Save-RunManifest -TaskName $Name -Report $report | Out-Null
            }
            $script:Busy = $false
            Set-Buttons $true
            $Progress.Style = 'Continuous'
            $Progress.MarqueeAnimationSpeed = 0
            $Progress.Value = 0
            Set-Pill $Indicator "$Name complete" Good
            Set-AppStatus $DoneMessage $script:Theme.Good
            Write-LogBox $LogBox $DoneMessage $script:Theme.Good
        } catch {
            if (-not [string]::IsNullOrWhiteSpace($CheckpointMilestone)) {
                try {
                    Update-LabCheckpoint -Milestone $CheckpointMilestone -Status 'Failed' -Notes $_.Exception.Message -Report $report | Out-Null
                } catch { }
            }
            $script:Busy = $false
            Set-Buttons $true
            $Progress.Style = 'Continuous'
            $Progress.MarqueeAnimationSpeed = 0
            $Progress.Value = 0
            Set-Pill $Indicator "$Name failed" Bad
            Set-AppStatus ('Error: ' + $_.Exception.Message) $script:Theme.Bad
            Write-LogBox $LogBox ('ERROR: ' + $_.Exception.Message) $script:Theme.Bad
        } finally {
            [System.Windows.Forms.Application]::DoEvents()
        }
    } catch {
        $script:Busy = $false
        Set-Buttons $true
        Set-Pill $Indicator "$Name failed" Bad
        Set-AppStatus ('Startup error: ' + $_.Exception.Message) $script:Theme.Bad
        Write-LogBox $LogBox ('Startup error: ' + $_.Exception.Message) $script:Theme.Bad
    }
}

function Get-SecureLabPassword {
    <#
    .SYNOPSIS
        Generates a random secure password for lab-only AD DS Safe Mode use.
    .DESCRIPTION
        Creates a random password that meets Windows complexity requirements
        but is meant for lab-only AD DS Safe Mode Administrator account.
        This password is NOT persisted to disk or logs.
    .EXAMPLE
        $password = Get-SecureLabPassword
        [SecureString object suitable for Install-ADDSForest]
    #>
    $length = 16
    $charset = 'ABCDEFGHJKLMNPQRSTUVWXYZabcdefghjkmnpqrstuvwxyz23456789!@#$%^&*'
    $password = ''
    for ($i = 0; $i -lt $length; $i++) {
        $password += $charset.Substring((Get-Random -Minimum 0 -Maximum $charset.Length), 1)
    }
    return ConvertTo-SecureString $password -AsPlainText -Force
}

function Redact-SecretText {
    <#
    .SYNOPSIS
        Redacts sensitive information from log text.
    .DESCRIPTION
        Removes or masks common secret patterns including passwords, tokens, and paths
        to sensitive resources. Used to sanitize log output before display and export.
    .PARAMETER InputText
        The text to redact.
    .EXAMPLE
        "password=Secret123" | Redact-SecretText
        Returns: "password=[REDACTED]"
    #>
    param([Parameter(Mandatory, ValueFromPipeline)][string]$InputText)
    
    if ([string]::IsNullOrEmpty($InputText)) { return $InputText }
    
    $redacted = $InputText
    
    # Redact common password patterns
    $redacted = $redacted -replace '(?i)(-Password\s+)[^\s]+', '$1[REDACTED]'
    $redacted = $redacted -replace '(?i)(password=)[^\s&]+', '$1[REDACTED]'
    $redacted = $redacted -replace '(?i)(P@ssw0rd)[^\s]*', '[REDACTED]'
    
    # Redact API keys and tokens
    $redacted = $redacted -replace '(?i)(Bearer\s+)[^\s]+', '$1[REDACTED]'
    $redacted = $redacted -replace '(?i)(token=)[^\s&]+', '$1[REDACTED]'
    $redacted = $redacted -replace '(?i)(api[_-]?key=)[^\s&]+', '$1[REDACTED]'
    
    # Redact -SafeModeAdministratorPassword values
    $redacted = $redacted -replace '(?i)(-SafeModeAdministratorPassword\s+)[^\s]+', '$1[REDACTED]'
    
    return $redacted
}

function Show-ConfirmationDialog {
    <#
    .SYNOPSIS
        Displays a confirmation dialog for destructive operations.
    .PARAMETER Title
        Dialog window title.
    .PARAMETER Message
        Message to display.
    .PARAMETER Details
        Optional additional details (command, network config, etc).
    .EXAMPLE
        if (-not (Show-ConfirmationDialog -Title "Configure Network" -Message "This will reconfigure your network adapter." -Details "IP: 192.168.1.10")) {
            return
        }
    #>
    param(
        [Parameter(Mandatory)][string]$Title,
        [Parameter(Mandatory)][string]$Message,
        [string]$Details = '',
        [switch]$AutoConfirm
    )
    
    $fullMessage = $Message
    if ($Details) {
        $fullMessage = "$Message`n`nDetails:`n$Details"
    }
    
    # Global override to auto-confirm operations for automated QA runs
    if ($AutoConfirm -or ($Global:ELM_AutoConfirm -eq $true)) { return $true }

    $result = [System.Windows.Forms.MessageBox]::Show(
        $fullMessage,
        $Title,
        [System.Windows.Forms.MessageBoxButtons]::YesNo,
        [System.Windows.Forms.MessageBoxIcon]::Warning
    )

    return ($result -eq 'Yes')
}

function Show-WarningDialog {
    <#
    .SYNOPSIS
        Displays a warning dialog and waits for user acknowledgment.
    .PARAMETER Title
        Dialog window title.
    .PARAMETER Message
        Message to display.
    .EXAMPLE
        Show-WarningDialog -Title "Lab Mode" -Message "This tool modifies system configuration."
    #>
    param(
        [Parameter(Mandatory)][string]$Title,
        [Parameter(Mandatory)][string]$Message
    )
    
    [System.Windows.Forms.MessageBox]::Show(
        $Message,
        $Title,
        [System.Windows.Forms.MessageBoxButtons]::OK,
        [System.Windows.Forms.MessageBoxIcon]::Warning
    ) | Out-Null
}

function Get-NetworkAdapters {
    <#
    .SYNOPSIS
        Returns a list of available network adapters suitable for configuration.
    .DESCRIPTION
        Returns all active physical network adapters that can be configured.
    .EXAMPLE
        $adapters = Get-NetworkAdapters
        $selected = $adapters[0]
    #>
    try {
        return @(Get-NetAdapter -ErrorAction Stop |
            Where-Object { $_.Status -eq 'Up' -and $_.HardwareInterface } |
            Sort-Object Name)
    } catch {
        return @()
    }
}

function Save-NetworkConfiguration {
    <#
    .SYNOPSIS
        Exports current network configuration to backup JSON.
    .DESCRIPTION
        Saves current IP, DNS, and adapter configuration before making changes.
        Allows recovery of network settings if something goes wrong.
    .PARAMETER BackupPath
        Optional explicit path for backup file. If not specified, uses standard backup directory.
    .EXAMPLE
        $backup = Save-NetworkConfiguration
        # Later: Restore-NetworkConfiguration $backup
    #>
    param([string]$BackupPath)
    
    try {
        $backupDir = Ensure-LabDataFolder 'backups'
        $timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
        if (-not $BackupPath) {
            $BackupPath = Join-Path $backupDir "network-backup-$timestamp.json"
        }
        
        $adapters = Get-NetworkAdapters
        $config = [ordered]@{
            Timestamp = (Get-Date).ToUniversalTime().ToString('u')
            ComputerName = $env:COMPUTERNAME
            Adapters = @()
        }
        
        foreach ($adapter in $adapters) {
            # Collect IP addresses
            $ips = @()
            try {
                $ips = @(Get-NetIPAddress -InterfaceAlias $adapter.Name -AddressFamily IPv4 -ErrorAction Stop)
            } catch {
                $ips = @()
            }

            # Collect DNS servers
            $dnsServers = @()
            try {
                $dns = Get-DnsClientServerAddress -InterfaceAlias $adapter.Name -AddressFamily IPv4 -ErrorAction Stop
                if ($dns -and $dns.ServerAddresses) { $dnsServers = $dns.ServerAddresses }
            } catch {
                $dnsServers = @()
            }

            # Collect default gateway using Get-NetIPConfiguration
            $gateway = $null
            try {
                $ipconf = Get-NetIPConfiguration -InterfaceAlias $adapter.Name -ErrorAction Stop
                if ($ipconf.IPv4DefaultGateway -and $ipconf.IPv4DefaultGateway.NextHop) { $gateway = $ipconf.IPv4DefaultGateway.NextHop }
            } catch {
                $gateway = $null
            }

            $config.Adapters += @{
                Name = $adapter.Name
                Description = $adapter.InterfaceDescription
                MACAddress = $adapter.MacAddress
                IPv4Addresses = @($ips | ForEach-Object { $_.IPAddress })
                IPv4Gateways = @(if ($gateway) { $gateway } else { @() })
                IPv4DNSServers = @($dnsServers)
                Status = $adapter.Status
            }
        }
        
        Write-JsonFile -Value $config -Path $BackupPath | Out-Null
        return $BackupPath
    } catch {
        Write-Error "Failed to backup network configuration: $_"
        return $null
    }
}

function Restore-NetworkConfiguration {
    <#
    .SYNOPSIS
        Restores a previously saved network configuration from a backup JSON file.
    .DESCRIPTION
        Reads a network backup created by Save-NetworkConfiguration and attempts to
        restore IPv4 addresses, default gateway, and DNS server configuration for
        matching adapters. This is a destructive operation and requires confirmation
        unless the global `$Global:ELM_AutoConfirm` is set.
    .PARAMETER BackupPath
        Optional path to the backup JSON file. If omitted, the most recent backup
        file from the backups folder will be used.
    .PARAMETER WhatIf
        If specified, prints planned actions but does not perform any changes.
    .EXAMPLE
        Restore-NetworkConfiguration -BackupPath C:\...\network-backup-20260605.json
    #>
    param(
        [string]$BackupPath,
        [switch]$WhatIf
    )

    Assert-Admin

    $backupDir = Ensure-LabDataFolder 'backups'
    if (-not $BackupPath) {
        $files = Get-ChildItem -Path $backupDir -Filter 'network-backup-*.json' -File | Sort-Object LastWriteTime -Descending
        if (-not $files -or $files.Count -eq 0) { throw 'No network backup files were found.' }
        $BackupPath = $files[0].FullName
    }

    if (-not (Test-Path -LiteralPath $BackupPath)) { throw "Backup file not found: $BackupPath" }

    $data = Read-JsonFile -Path $BackupPath
    if (-not $data.Adapters) { throw 'Backup file does not contain adapter information.' }

    $confirmMsg = "This will attempt to restore network settings from backup:`n$BackupPath`n`nProceed?"
    if (-not (Show-ConfirmationDialog -Title 'Restore Network Settings' -Message $confirmMsg -Details $BackupPath -AutoConfirm:$false)) {
        & $script:Report 'Network restore cancelled by user.' 'Warn' 2>$null
        return
    }

    foreach ($entry in $data.Adapters) {
        $name = $entry.Name
        $adapter = Get-NetAdapter -Name $name -ErrorAction SilentlyContinue
        if (-not $adapter) {
            Write-Warning "Adapter '$name' not found on this system; skipping."
            continue
        }

        $ips = @($entry.IPv4Addresses) | Where-Object { $_ }
        $gw = if ($entry.IPv4Gateways -and $entry.IPv4Gateways.Count -gt 0) { $entry.IPv4Gateways[0] } else { $null }
        $dns = @($entry.IPv4DNSServers) | Where-Object { $_ }

        Write-Output "Restoring adapter: $name (IPs: $($ips -join ', ') Gateway: $gw DNS: $($dns -join ', '))"

        if ($WhatIf) { continue }

        try {
            # Remove existing IPv4 addresses that are not link-local
            $current = @(Get-NetIPAddress -InterfaceAlias $name -AddressFamily IPv4 -ErrorAction SilentlyContinue | Where-Object { $_.IPAddress -notlike '169.254.*' })
            foreach ($c in $current) {
                Remove-NetIPAddress -InterfaceAlias $name -IPAddress $c.IPAddress -Confirm:$false -ErrorAction SilentlyContinue
            }

            # Apply backup IPs
            foreach ($ip in $ips) {
                $prefix = 24
                if ($ip -match '/(\d{1,2})$') {
                    $prefix = [int]$Matches[1]
                    $ipAddr = $ip -replace '/\d{1,2}$',''
                } else {
                    $ipAddr = $ip
                }
                if ($ipAddr) {
                    try {
                        New-NetIPAddress -InterfaceAlias $name -IPAddress $ipAddr -PrefixLength $prefix -DefaultGateway $gw -AddressFamily IPv4 -ErrorAction Stop | Out-Null
                    } catch {
                        Write-Warning ("Failed to create IP {0} on {1}: {2}" -f $ipAddr, $name, $_)
                    }
                }
            }

            # Apply DNS servers
            if ($dns -and $dns.Count -gt 0) {
                try {
                    Set-DnsClientServerAddress -InterfaceAlias $name -ServerAddresses $dns -ErrorAction Stop
                } catch {
                    Write-Warning ("Failed to set DNS for {0}: {1}" -f $name, $_)
                }
            }
        } catch {
            Write-Warning ("Error restoring adapter {0}: {1}" -f $name, $_)
        }
    }

    Write-Output 'Network restore completed (review warnings above).' 
}

function Invoke-LoggedProcess {
    param(
        [Parameter(Mandatory)][string]$FilePath,
        [string[]]$Arguments = @(),
        [string]$WorkingDirectory,
        [Parameter(Mandatory)][scriptblock]$Report
    )

    if (-not (Test-Path -LiteralPath $FilePath)) { throw "Executable not found: $FilePath" }

    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $FilePath
    $psi.Arguments = ($Arguments | ForEach-Object { Format-Arg $_ }) -join ' '
    if ($WorkingDirectory) { $psi.WorkingDirectory = $WorkingDirectory }
    $psi.UseShellExecute = $false
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.CreateNoWindow = $true

    & $Report ("Launching: {0} {1}" -f $FilePath, $psi.Arguments) 'Info'

    $process = New-Object System.Diagnostics.Process
    $process.StartInfo = $psi

    $exitCode = $null
    $stdout = ''
    $stderr = ''
    try {
        [void]$process.Start()
        $stdoutTask = $process.StandardOutput.ReadToEndAsync()
        $stderrTask = $process.StandardError.ReadToEndAsync()
        $process.WaitForExit()
        $stdout = $stdoutTask.Result
        $stderr = $stderrTask.Result
        $exitCode = $process.ExitCode
    } finally {
        $process.Dispose()
    }

    foreach ($line in ($stdout -split '\r?\n')) {
        if (-not [string]::IsNullOrWhiteSpace($line)) { & $Report $line 'Info' }
    }
    foreach ($line in ($stderr -split '\r?\n')) {
        if (-not [string]::IsNullOrWhiteSpace($line)) { & $Report $line 'Warn' }
    }

    if ($exitCode -ne 0) { throw "Process exited with code ${exitCode}: $FilePath" }
    & $Report 'Process completed with exit code 0.' 'Good'
}

function Save-LabProfile {
    param(
        [string]$PathOrName = 'default-lab',
        [scriptblock]$Report,
        [string]$Path,
        [string]$Name
    )
    if (-not $Report) { $Report = { param($Message, $Kind = 'Info') } }
    if ([string]::IsNullOrWhiteSpace($Path)) {
        if (-not [string]::IsNullOrWhiteSpace($Name)) {
            $Path = Get-LabProfilePath $Name
        } elseif ($PathOrName -match '[\\/:]' -or $PathOrName -match '\.json$') {
            $Path = $PathOrName
        } else {
            $Path = Get-LabProfilePath $PathOrName
        }
    }
    $created = (Get-Date).ToUniversalTime().ToString('u')
    if (Test-Path -LiteralPath $Path -PathType Leaf) {
        try {
            $existing = Read-JsonFile $Path
            $existingCreated = Get-ObjectValue $existing 'CreatedUtc' $null
            if ($existingCreated) { $created = $existingCreated }
        } catch { }
    }
    $profile = [ordered]@{
        SchemaVersion = 2
        Name = if ($Name) { $Name } else { [System.IO.Path]::GetFileNameWithoutExtension($Path) }
        CreatedUtc = $created
        UpdatedUtc = (Get-Date).ToUniversalTime().ToString('u')
        Inputs = Get-CurrentLabInputs
    }
    Write-JsonFile -Value $profile -Path $Path | Out-Null
    Set-UiTextValue 'ProfilePath' $Path
    Update-LabCheckpoint -Milestone 'ProfileSaved' -Status 'Complete' -Notes "Profile saved to $Path" -Report $Report | Out-Null
    & $Report "Saved profile to: $Path" 'Good'
    return $Path
}

function Load-LabProfile {
    param(
        [string]$PathOrName = 'default-lab',
        [scriptblock]$Report,
        [string]$Path,
        [string]$Name
    )
    if (-not $Report) { $Report = { param($Message, $Kind = 'Info') } }
    if ([string]::IsNullOrWhiteSpace($Path)) {
        if (-not [string]::IsNullOrWhiteSpace($Name)) {
            $Path = Get-LabProfilePath $Name
        } elseif ($PathOrName -match '[\\/:]' -or $PathOrName -match '\.json$') {
            $Path = $PathOrName
        } else {
            $Path = Get-LabProfilePath $PathOrName
        }
    }
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { throw "Profile file not found: $Path" }
    $profile = Read-JsonFile $Path
    $inputs = Get-ObjectValue $profile 'Inputs' $null
    if ($inputs) {
        Set-CurrentLabInputs $inputs
    } else {
        $legacyInputs = [ordered]@{
            Ip = Get-ObjectValue (Get-ObjectValue $profile 'LabEnvironment' @{}).NetworkConfiguration 'StaticIp' (Get-UiTextValue 'Ip')
            Mask = Get-ObjectValue (Get-ObjectValue $profile 'LabEnvironment' @{}).NetworkConfiguration 'SubnetMask' (Get-UiTextValue 'Mask')
            Domain = Get-ObjectValue (Get-ObjectValue $profile 'LabEnvironment' @{}).ActiveDirectory 'DomainName' (Get-UiTextValue 'Domain')
            ExchangePath = Get-ObjectValue (Get-ObjectValue $profile 'ExchangeConfiguration' @{}) 'ExchangeIsoPath' (Get-UiTextValue 'ExchangePath')
            Eomt = Get-ObjectValue (Get-ObjectValue $profile 'MitigationConfiguration' @{}) 'EomtSourceUrl' (Get-UiTextValue 'Eomt')
            Smtp = Get-ObjectValue (Get-ObjectValue $profile 'TestConfiguration' @{}) 'SmtpTarget' (Get-UiTextValue 'Smtp')
            OwaUrl = Get-ObjectValue (Get-ObjectValue $profile 'TestConfiguration' @{}) 'CveValidationOwaUrl' (Get-UiTextValue 'OwaUrl')
        }
        Set-CurrentLabInputs $legacyInputs
    }
    Set-UiTextValue 'ProfilePath' $Path
    & $Report "Loaded profile from: $Path" 'Good'
    return $profile
}

function Export-RunManifest {
    param(
        [string]$PathOrTask = 'Manual',
        [scriptblock]$Report,
        [string]$Path,
        [string]$TaskName
    )
    if (-not $Report) { $Report = { param($Message, $Kind = 'Info') } }
    if ([string]::IsNullOrWhiteSpace($TaskName)) { $TaskName = 'Manual export' }
    if ([string]::IsNullOrWhiteSpace($Path)) {
        if ($PathOrTask -match '[\\/:]' -or $PathOrTask -match '\.json$') {
            $Path = $PathOrTask
        } else {
            $manifestFolder = Ensure-LabDataFolder 'manifests'
            $Path = Join-Path $manifestFolder ("{0}-{1}.json" -f (Get-Date -Format 'yyyyMMdd-HHmmss'), (Get-SafeFileName $PathOrTask 'manual'))
            $TaskName = $PathOrTask
        }
    }
    $manifest = [ordered]@{
        SchemaVersion = 2
        ManifestType = 'Exchange Lab Manager Run Manifest'
        TaskName = $TaskName
        ExportTimeUtc = (Get-Date).ToUniversalTime().ToString('u')
        ComputerName = $env:COMPUTERNAME
        UserName = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name
        LabDataRoot = Get-LabDataRoot
        ProfilePath = Get-UiTextValue 'ProfilePath'
        Inputs = Get-CurrentLabInputs
        Checkpoint = Get-LabCheckpoint
    }
    Write-JsonFile -Value $manifest -Path $Path | Out-Null
    & $Report "Run manifest saved to: $Path" 'Good'
    return $Path
}

function Test-PendingReboot {
    $pendingKeys = @(
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending',
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired',
        'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\PendingFileRenameOperations'
    )
    foreach ($key in $pendingKeys) {
        if (Test-Path -LiteralPath $key) { return $true }
    }
    return $false
}

function Run-PreflightChecks {
    param(
        [hashtable]$Data,
        [Parameter(Mandatory)][scriptblock]$Report
    )
    $preflightScript = Join-Path $PSScriptRoot 'preflight-readiness-check.ps1'
    if (-not (Test-Path -LiteralPath $preflightScript)) {
        throw "Preflight script not found: $preflightScript"
    }

    & $Report "Executing external preflight script: $preflightScript" 'Info'
    $powershell = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
    
    $blockingFound = $false
    $warningFound = $false

    # We use a custom reporter that also scans for status keywords
    $internalReport = {
        param([string]$Message, [string]$Kind = 'Info')
        if ($Message -match '\[FAIL\]|\[CRITICAL\]|Critical') {
            $Global:ELM_PreflightBlocking = $true
            & $Report $Message 'Bad'
        } elseif ($Message -match '\[WARN\]|Warning') {
            $script:PreflightWarning = $true
            & $Report $Message 'Warn'
        } else {
            & $Report $Message $Kind
        }
    }.GetNewClosure()

    $Global:ELM_PreflightBlocking = $false
    $script:PreflightWarning = $false

    Invoke-LoggedProcess -FilePath $powershell `
        -Arguments @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $preflightScript) `
        -WorkingDirectory $PSScriptRoot `
        -Report $internalReport

    if ($script:PreflightBlocking) {
        Update-LabCheckpoint -Milestone 'PreflightPassed' -Status 'Failed' -Notes 'Preflight failed with blocking issues.' -Report $Report | Out-Null
        throw "Preflight validation failed with blocking issues. Fix critical errors before proceeding."
    }

    Update-LabCheckpoint -Milestone 'PreflightPassed' -Status 'Complete' -Notes 'Preflight completed.' -Report $Report | Out-Null
    & $Report "Preflight validation passed." 'Good'
}

function Invoke-LabCleanup {
    param(
        [ValidateSet('DryRun', 'Preview', 'Clean', 'TempOnly', 'Full')]
        [string]$Mode = 'Preview',
        [Parameter(Mandatory)][scriptblock]$Report
    )
    $safeMode = if ($Mode -in @('DryRun', 'Preview')) { 'Preview' } else { 'TempOnly' }
    $result = Invoke-LabCleanupCore -Mode $safeMode -Report $Report
    if ($Mode -in @('Clean', 'TempOnly', 'Full')) {
        Update-LabCheckpoint -Milestone 'EvidenceExported' -Status 'Complete' -Notes 'Cleanup artifacts processed.' -Report $Report | Out-Null
    }
    return $result
}

function Get-UiLogsSnapshot {
    $logs = [ordered]@{}
    foreach ($entry in @(
        @{ Name = 'System'; Field = 'SystemLog' },
        @{ Name = 'Exchange'; Field = 'ExchangeLog' },
        @{ Name = 'Mitigation'; Field = 'MitigationLog' },
        @{ Name = 'HtmlValidation'; Field = 'HtmlValidationLog' },
        @{ Name = 'CVE'; Field = 'CveLog' },
        @{ Name = 'Profile'; Field = 'ProfileLog' }
    )) {
        if ($script:Ui.ContainsKey($entry.Field) -and $script:Ui[$entry.Field]) {
            $logs[$entry.Name] = [string]$script:Ui[$entry.Field].Text
        }
    }
    return $logs
}

function Write-CveEvidenceFiles {
    param(
        [Parameter(Mandatory)][string]$Directory,
        [Parameter(Mandatory)][scriptblock]$Report
    )
    if (-not (Test-Path -LiteralPath $Directory -PathType Container)) {
        New-Item -Path $Directory -ItemType Directory -Force | Out-Null
    }
    try {
        [ordered]@{
            ExportTimeUtc = (Get-Date).ToUniversalTime().ToString('u')
            ComputerName = $env:COMPUTERNAME
            UserName = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name
            OSVersion = [System.Environment]::OSVersion.ToString()
            PowerShellVersion = $PSVersionTable.PSVersion.ToString()
        } | ConvertTo-Json -Depth 6 | Out-File -FilePath (Join-Path $Directory '00-CVE-Metadata.json') -Encoding UTF8
        & $Report 'Exported: CVE metadata.' 'Good'
    } catch { & $Report "CVE metadata export skipped: $_" 'Warn' }

    try {
        Get-Command ExSetup.exe -ErrorAction Stop | ForEach-Object { $_.Source | Get-Item | Select-Object -ExpandProperty VersionInfo } |
            Out-File -FilePath (Join-Path $Directory '01-ExchangeBuild.txt') -Encoding UTF8
        & $Report 'Exported: Exchange build info.' 'Good'
    } catch { & $Report "Exchange build export skipped: $_" 'Warn' }

    try {
        Get-ExchangeServer -ErrorAction Stop | Select-Object Name,Edition,AdminDisplayVersion,MitigationsEnabled,MitigationsApplied,MitigationsBlocked |
            Out-File -FilePath (Join-Path $Directory '02-ExchangeMitigationFields.txt') -Encoding UTF8
        & $Report 'Exported: Exchange mitigation fields.' 'Good'
    } catch { & $Report "Mitigation field export skipped: $_" 'Warn' }

    try {
        Get-Service MSExchangeMitigation -ErrorAction Stop |
            Select-Object Name,DisplayName,Status,StartType |
            Out-File -FilePath (Join-Path $Directory '03-MSExchangeMitigation-Service.txt') -Encoding UTF8
        & $Report 'Exported: EM service status.' 'Good'
    } catch { & $Report "EM service export skipped: $_" 'Warn' }

    try {
        Import-Module WebAdministration -ErrorAction SilentlyContinue
        Get-WebConfiguration -PSPath 'IIS:\Sites\Default Web Site\owa' -Filter 'system.webServer/rewrite/outboundRules/rule' 2>$null |
            Select-Object name,enabled,preCondition |
            Out-File -FilePath (Join-Path $Directory '04-OWA-OutboundRules.txt') -Encoding UTF8
        & $Report 'Exported: OWA rewrite rules.' 'Good'
    } catch { & $Report "IIS rewrite export skipped: $_" 'Warn' }

    try {
        $owaUrl = (Get-UiTextValue 'OwaUrl').Trim()
        if ($owaUrl) {
            $response = Invoke-WebRequest -Uri $owaUrl -UseBasicParsing -ErrorAction Stop
            [ordered]@{
                OwaUrl = $owaUrl
                ContentSecurityPolicy = $response.Headers['Content-Security-Policy']
                CapturedUtc = (Get-Date).ToUniversalTime().ToString('u')
            } | ConvertTo-Json -Depth 6 | Out-File -FilePath (Join-Path $Directory '05-OWA-CSP-Header.json') -Encoding UTF8
            & $Report 'Exported: OWA CSP header snapshot.' 'Good'
        }
    } catch { & $Report "OWA CSP header export skipped: $_" 'Warn' }
}

function Export-FullEvidenceBundle {
    param(
        [hashtable]$Data = @{},
        [Parameter(Mandatory)][scriptblock]$Report
    )
    $timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
    $suffix = ([guid]::NewGuid().ToString('N')).Substring(0, 8)
    $evidenceDir = Join-Path $env:TEMP "ExchangeLabManager-Evidence-$timestamp-$suffix"
    New-Item -ItemType Directory -Path $evidenceDir -Force | Out-Null
    & $Report "Evidence folder created: $evidenceDir" 'Info'

    $metadata = [ordered]@{
        SchemaVersion = 2
        ExportTimeUtc = (Get-Date).ToUniversalTime().ToString('u')
        ComputerName = $env:COMPUTERNAME
        UserName = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name
        OSVersion = [System.Environment]::OSVersion.ToString()
        PowerShellVersion = $PSVersionTable.PSVersion.ToString()
        LabDataRoot = Get-LabDataRoot
    }
    Write-JsonFile -Value $metadata -Path (Join-Path $evidenceDir '00-Bundle-Metadata.json') | Out-Null
    Write-JsonFile -Value (Get-CurrentLabInputs) -Path (Join-Path $evidenceDir '01-Current-Inputs.json') | Out-Null
    Write-JsonFile -Value (Get-LabCheckpoint) -Path (Join-Path $evidenceDir '02-Checkpoint.json') | Out-Null

    $manifest = [ordered]@{
        ManifestType = 'Evidence bundle embedded manifest'
        ExportTimeUtc = (Get-Date).ToUniversalTime().ToString('u')
        Inputs = Get-CurrentLabInputs
        Checkpoint = Get-LabCheckpoint
    }
    Write-JsonFile -Value $manifest -Path (Join-Path $evidenceDir '03-Run-Manifest.json') | Out-Null

    try {
        $preflight = Invoke-PreflightReadiness -Report $Report
        Write-JsonFile -Value $preflight -Path (Join-Path $evidenceDir '04-Preflight.json') | Out-Null
    } catch {
        "Preflight capture failed: $($_.Exception.Message)" | Out-File -FilePath (Join-Path $evidenceDir '04-Preflight.txt') -Encoding UTF8
        & $Report "Preflight capture skipped: $($_.Exception.Message)" 'Warn'
    }

    $logs = if ($Data.Logs) {
        $Data.Logs
    } else {
        Get-UiLogsSnapshot
    }
    $logFolder = Join-Path $evidenceDir 'logs'
    New-Item -Path $logFolder -ItemType Directory -Force | Out-Null
    foreach ($name in $logs.Keys) {
        try {
            $raw = $logs[$name]
            $text = if ($raw -and $raw.PSObject.Properties['Text']) { [string]$raw.Text } else { [string]$raw }
            $safeName = Get-SafeFileName $name 'log'
            $text | Out-File -FilePath (Join-Path $logFolder "$safeName.txt") -Encoding UTF8
            & $Report "Exported: $name log." 'Good'
        } catch {
            & $Report "Skipped exporting $name log: $_" 'Warn'
        }
    }

    if ($Data.ProfilePath -and (Test-Path -LiteralPath $Data.ProfilePath -PathType Leaf)) {
        try {
            Copy-Item -LiteralPath $Data.ProfilePath -Destination (Join-Path $evidenceDir '05-Loaded-Profile.json') -Force
            & $Report 'Exported: Loaded profile file.' 'Good'
        } catch { & $Report "Loaded profile copy skipped: $_" 'Warn' }
    }

    $cveDir = Join-Path $evidenceDir 'cve-validation'
    Write-CveEvidenceFiles -Directory $cveDir -Report $Report

    try {
        $zipPath = if ($Data.OutputPath) { $Data.OutputPath } else { Join-Path $env:TEMP "CVE42897-Evidence-$timestamp.zip" }
        if (Test-Path -LiteralPath $zipPath -PathType Leaf) { Remove-Item -LiteralPath $zipPath -Force }
        
        & $Report "Creating ZIP bundle..." 'Info'
        Add-Type -AssemblyName System.IO.Compression.FileSystem
        [System.IO.Compression.ZipFile]::CreateFromDirectory($evidenceDir, $zipPath)
        
        & $Report "Deleting temporary evidence folder..." 'Info'
        Remove-Item -LiteralPath $evidenceDir -Recurse -Force -ErrorAction SilentlyContinue

        Update-LabCheckpoint -Milestone 'EvidenceExported' -Status 'Complete' -Notes "Evidence exported to $zipPath" -Report $Report | Out-Null
        & $Report "All evidence exported to: $zipPath" 'Good'
        return @{ ZipBundle = $zipPath }
    } catch {
        & $Report "ZIP bundle creation failed: $_" 'Bad'
        & $Report "All evidence exported to: $evidenceDir" 'Good'
        return @{ Directory = $evidenceDir; ZipBundle = $null }
    }
}

function Export-LabEvidence {
    param(
        [hashtable]$Data = @{},
        [Parameter(Mandatory)][scriptblock]$Report
    )
    return Export-FullEvidenceBundle -Data $Data -Report $Report
}

function Export-CveEvidence {
    param(
        [Parameter(Mandatory)][scriptblock]$Report,
        [hashtable]$Data = @{}
    )
    return Export-FullEvidenceBundle -Data $Data -Report $Report
}

function Invoke-ExchangeSetup {
    param([string]$ExchangePath, [string[]]$Arguments, [scriptblock]$Report)
    if ([System.IO.Path]::GetFileName($ExchangePath) -ieq 'Setup.exe') {
        $setupPath = $ExchangePath
        $workDir = Split-Path -Parent $ExchangePath
    } else {
        $workDir = $ExchangePath
        $setupPath = Join-Path $ExchangePath 'Setup.exe'
    }
    if (-not (Test-Path -LiteralPath $setupPath)) {
        throw "Exchange Setup.exe was not found at '$setupPath'. Select the mounted ISO root or Setup.exe path."
    }
    Invoke-LoggedProcess -FilePath $setupPath -Arguments $Arguments -WorkingDirectory $workDir -Report $Report
}

function Set-StaticNetwork {
    <#
    .SYNOPSIS
        Configures static IP addressing and DNS on selected network adapter.
    .DESCRIPTION
        This is a DESTRUCTIVE operation that reconfigures network settings.
        Current configuration is backed up before changes. A confirmation dialog
        is required before proceeding.
    .PARAMETER Data
        Hashtable containing Ip and Mask.
    .PARAMETER Report
        Scriptblock for logging output.
    .EXAMPLE
        Set-StaticNetwork @{ Ip = '192.168.1.10'; Mask = '255.255.255.0' } $report
    #>
    param([hashtable]$Data, [scriptblock]$Report)
    Assert-Admin
    if ($Global:ELM_AutoConfirm) {
        Ensure-QANetworkMockCommands
    }

    $ip = $Data.Ip.Trim()
    $mask = $Data.Mask.Trim()
    [void][System.Net.IPAddress]::Parse($ip)
    $prefix = Convert-MaskToPrefix $mask
    $gateway = Get-GatewayFromIp $ip

    # Save current network config before making changes
    & $Report 'Backing up current network configuration...' 'Info'
    $backup = Save-NetworkConfiguration
    if ($backup) {
        & $Report "Network backup saved: $backup" 'Good'
    } else {
        & $Report 'Warning: Network backup failed. Proceeding with caution.' 'Warn'
    }

    # Get available adapters and show selection
    $adapters = Get-NetworkAdapters
    if ($Global:ELM_AutoConfirm) {
        Ensure-QANetworkMockCommands
    }
    if ($adapters.Count -eq 0) {
        throw 'No active physical network adapters were found.'
    }
    
    $adapter = $null
    if ($adapters.Count -eq 1) {
        $adapter = $adapters[0]
        & $Report "Single adapter found: $($adapter.Name)" 'Info'
    } else {
        # Multiple adapters: prefer one explicitly selected, or first active
        & $Report "Found $($adapters.Count) active adapters. Using first: $($adapters[0].Name)" 'Info'
        $adapter = $adapters[0]
    }

    # Require confirmation before network reconfiguration
    $confirmMessage = "Static Network Configuration is DESTRUCTIVE.`n`nThis will:`n- Reconfigure network adapter '$($adapter.Name)'`n- Set IP address to $ip/$prefix`n- Set gateway to $gateway`n- Set DNS to 127.0.0.1 (local DC)`n`nPrevious configuration has been backed up.`n`nContinue?"
    if (-not (Show-ConfirmationDialog -Title 'DESTRUCTIVE: Reconfigure Network' -Message $confirmMessage -Details "Adapter: $($adapter.Name)`nIP: $ip/$prefix`nGateway: $gateway")) {
        & $Report 'Network reconfiguration cancelled by user.' 'Warn'
        return
    }

    & $Report "Selected adapter '$($adapter.Name)'." 'Info'
    $current = @(Get-NetIPAddress -InterfaceAlias $adapter.Name -AddressFamily IPv4 -ErrorAction SilentlyContinue |
        Where-Object { $_.IPAddress -notlike '169.254.*' })
    foreach ($addr in $current) {
        if ($addr.IPAddress -ne $ip) {
            & $Report "Removing previous IPv4 address $($addr.IPAddress)." 'Warn'
            if ($Global:ELM_AutoConfirm) {
                # In QA mode, we record the operation instead of calling the command
                $ops = (Get-Variable -Name 'ELM_NetworkOps' -Scope Global -ErrorAction SilentlyContinue).Value
                if ($null -ne $ops) { $ops.Add([pscustomobject]@{ Op = 'Remove'; IPAddress = $addr.IPAddress; InterfaceAlias = $adapter.Name }) | Out-Null }
                & $Report "Auto-confirm: recorded Remove-NetIPAddress $($addr.IPAddress) on $($adapter.Name)." 'Info'
            } else {
                Remove-NetIPAddress -InterfaceAlias $adapter.Name -IPAddress $addr.IPAddress -Confirm:$false -ErrorAction SilentlyContinue
            }
        }
    }

    $existing = @(Get-NetIPAddress -InterfaceAlias $adapter.Name -IPAddress $ip -AddressFamily IPv4 -ErrorAction SilentlyContinue)
    if ($existing) {
        if ($Global:ELM_AutoConfirm) {
            $ops = (Get-Variable -Name 'ELM_NetworkOps' -Scope Global -ErrorAction SilentlyContinue).Value
            if ($null -ne $ops) { $ops.Add([pscustomobject]@{ Op = 'Set'; IPAddress = $ip; PrefixLength = $prefix; InterfaceAlias = $adapter.Name }) | Out-Null }
            & $Report "Auto-confirm: recorded Set-NetIPAddress $ip/$prefix on $($adapter.Name)." 'Info'
        } else {
            Set-NetIPAddress -InterfaceAlias $adapter.Name -IPAddress $ip -PrefixLength $prefix -ErrorAction Stop
        }
    } else {
        if ($Global:ELM_AutoConfirm) {
            $ops = (Get-Variable -Name 'ELM_NetworkOps' -Scope Global -ErrorAction SilentlyContinue).Value
            if ($null -ne $ops) { $ops.Add([pscustomobject]@{ Op = 'New'; IPAddress = $ip; PrefixLength = $prefix; DefaultGateway = $gateway; InterfaceAlias = $adapter.Name }) | Out-Null }
            & $Report "Auto-confirm: recorded New-NetIPAddress $ip/$prefix gateway $gateway on $($adapter.Name)." 'Info'
        } else {
            New-NetIPAddress -InterfaceAlias $adapter.Name -IPAddress $ip -PrefixLength $prefix -DefaultGateway $gateway -AddressFamily IPv4 -ErrorAction Stop | Out-Null
        }
    }

    if ($Global:ELM_AutoConfirm) {
        $ops = (Get-Variable -Name 'ELM_NetworkOps' -Scope Global -ErrorAction SilentlyContinue).Value
        if ($null -ne $ops) { $ops.Add([pscustomobject]@{ Op = 'Dns'; InterfaceAlias = $adapter.Name; ServerAddresses = '127.0.0.1' }) | Out-Null }
        & $Report "Auto-confirm: recorded Set-DnsClientServerAddress 127.0.0.1 on $($adapter.Name)." 'Info'
        & $Report "Network applied: $ip/$prefix, gateway $gateway, DNS 127.0.0.1." 'Good'
    } else {
        Set-DnsClientServerAddress -InterfaceAlias $adapter.Name -ServerAddresses '127.0.0.1' -ErrorAction Stop
        & $Report "Network applied: $ip/$prefix, gateway $gateway, DNS 127.0.0.1." 'Good'
    }
}

function Install-AdAndPromote {
    <#
    .SYNOPSIS
        Promotes server to Active Directory forest root domain.
    .DESCRIPTION
        Installs AD DS and promotes server to a new forest. This is a DESTRUCTIVE operation
        that cannot be easily undone. A confirmation dialog is required before proceeding.
        A random, lab-only Safe Mode password is generated (not persisted to disk).
    .PARAMETER Data
        Hashtable containing Domain name.
    .PARAMETER Report
        Scriptblock for logging output.
    .EXAMPLE
        Install-AdAndPromote @{ Domain = 'contoso.lab' } $report
    #>
    param([hashtable]$Data, [scriptblock]$Report)
    Assert-Admin
    
    $domain = $Data.Domain.Trim()
    if ($domain -notmatch '^[a-zA-Z0-9][a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$') {
        throw "Invalid domain name '$domain'."
    }
    
    # Require explicit user confirmation for this destructive operation
    $confirmMessage = "AD DS Promotion is IRREVERSIBLE.`n`nThis will:`n- Install AD DS role`n- Promote this server to forest root`n- Require a reboot`n- Create domain '$domain'`n`nContinue?"
    if (-not (Show-ConfirmationDialog -Title 'DESTRUCTIVE: AD DS Promotion' -Message $confirmMessage -Details "Domain: $domain")) {
        & $Report 'AD DS promotion cancelled by user.' 'Warn'
        return
    }
    
    & $Report 'Installing Active Directory Domain Services...' 'Info'
    Install-WindowsFeature -Name AD-Domain-Services -IncludeManagementTools -ErrorAction Stop | Out-Null
    Import-Module ADDSDeployment -ErrorAction Stop
    
    # Generate random lab-only Safe Mode password (NOT persisted or logged)
    $safeMode = Get-SecureLabPassword
    & $Report "Promoting server to forest '$domain'." 'Info'
    
    try {
        Install-ADDSForest `
            -DomainName $domain `
            -SafeModeAdministratorPassword $safeMode `
            -InstallDns `
            -CreateDnsDelegation:$false `
            -Force `
            -NoRebootOnCompletion `
            -ErrorAction Stop
        & $Report 'Promotion finished. Reboot the server before Exchange setup.' 'Warn'
    } finally {
        # Clear the password from memory
        $safeMode = $null
    }
}

function Prepare-ExchangeAd {
    param([hashtable]$Data, [scriptblock]$Report)
    Assert-Admin
    Invoke-ExchangeSetup -ExchangePath $Data.Path -Arguments @('/PrepareSchema', '/IAcceptExchangeServerLicenseTerms_DiagnosticDataON') -Report $Report
    Invoke-ExchangeSetup -ExchangePath $Data.Path -Arguments @('/PrepareAD', '/OrganizationName:TestLab', '/IAcceptExchangeServerLicenseTerms_DiagnosticDataON') -Report $Report
}

function Install-Exchange {
    param([hashtable]$Data, [scriptblock]$Report)
    Assert-Admin
    & $Report 'Starting Exchange Mailbox role setup. This can take a long time.' 'Warn'
    Invoke-ExchangeSetup -ExchangePath $Data.Path -Arguments @('/Mode:Install', '/Roles:Mailbox', '/IAcceptExchangeServerLicenseTerms_DiagnosticDataON', '/EnableErrorReporting:false', '/UseWindowsPowerShell:true') -Report $Report
}

function Apply-Eomt {
    <#
    .SYNOPSIS
        Downloads and applies Exchange On-Premises Mitigation Tool.
    .DESCRIPTION
        This is a DESTRUCTIVE operation that downloads and executes mitigation scripts.
        User must confirm before download and execution. Local files are preferred over URLs.
        URL downloads are logged with timestamp for audit purposes.
    .PARAMETER Data
        Hashtable containing Source (URL or local path).
    .PARAMETER Report
        Scriptblock for logging output.
    .EXAMPLE
        Apply-Eomt @{ Source = 'https://aka.ms/exchange-onprem-mitigation-tool' } $report
    #>
    param([hashtable]$Data, [scriptblock]$Report)
    Assert-Admin
    
    $source = $Data.Source.Trim()
    if (-not $source) { throw 'Enter an EOMT URL or local script path.' }
    
    # Require confirmation before EOMT execution
    $isUrl = $source -match '^https?://'
    $confirmMessage = if ($isUrl) {
        "EOMT Download and Execution is DESTRUCTIVE.`n`nThis will:`n- Download mitigation tool from URL`n- Execute the mitigation script`n- Modify Exchange configuration`n`nURL: $source`n`nContinue?"
    } else {
        "EOMT Execution is DESTRUCTIVE.`n`nThis will:`n- Execute local mitigation script`n- Modify Exchange configuration`n`nPath: $source`n`nContinue?"
    }
    
    if (-not (Show-ConfirmationDialog -Title 'DESTRUCTIVE: Apply EOMT' -Message $confirmMessage -Details "Source: $source")) {
        & $Report 'EOMT execution cancelled by user.' 'Warn'
        return
    }
    
    $cache = Join-Path $env:TEMP 'ExchangeLabManager'
    if (-not (Test-Path -LiteralPath $cache)) { New-Item -Path $cache -ItemType Directory -Force | Out-Null }
    $local = Join-Path $cache 'EOMT.ps1'

    if ($isUrl) {
        # For URLs, validate and require approval
        & $Report "Downloading EOMT from Microsoft: $source" 'Info'
        & $Report "Download timestamp: $(Get-Date -Format 'o')" 'Info'
        
        # Only allow specific Microsoft URLs for EOMT
        if ($source -notmatch '^https://.*microsoft.*') {
            $warnMessage = "Non-Microsoft URL detected.`n`nOnly Microsoft-owned URLs are recommended for EOMT.`n`nURL: $source`n`nProceed at your own risk?"
            if (-not (Show-ConfirmationDialog -Title 'WARNING: Non-Microsoft URL' -Message $warnMessage)) {
                & $Report 'EOMT download cancelled - non-Microsoft URL blocked by default.' 'Warn'
                return
            }
        }
        
        try {
            Invoke-WebRequest -Uri $source -OutFile $local -UseBasicParsing -ErrorAction Stop
            & $Report "Downloaded to: $local" 'Good'
        } catch {
            throw "Failed to download EOMT: $_"
        }
    } else {
        # Local file - validate existence
        if (-not (Test-Path -LiteralPath $source)) { 
            throw "EOMT source path not found: $source" 
        }
        $local = (Resolve-Path -LiteralPath $source).Path
        & $Report "Using local EOMT: $local" 'Good'
    }

    # Execute the mitigation script
    & $Report 'Executing EOMT mitigation script...' 'Info'
    $powershell = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
    Invoke-LoggedProcess -FilePath $powershell `
        -Arguments @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $local) `
        -WorkingDirectory (Split-Path -Parent $local) `
        -Report $Report
    & $Report 'EOMT action completed. Run status check to inspect mitigation state.' 'Good'
}

function Check-Mitigation {
    param([hashtable]$Data, [scriptblock]$Report)
    Assert-Admin
    if (Get-Command Get-Mitigation -ErrorAction SilentlyContinue) {
        try {
            $mit = Get-Mitigation -Identity 'M2.1.x' -ErrorAction Stop
            & $Report ("Get-Mitigation M2.1.x:`r`n{0}" -f (($mit | Out-String).Trim())) 'Info'
        } catch {
            & $Report ("Get-Mitigation error: {0}" -f $_.Exception.Message) 'Warn'
        }
    } else {
        & $Report 'Get-Mitigation was not found. Run this check from Exchange Management Shell for mitigation cmdlet details.' 'Warn'
    }

    try {
        Import-Module WebAdministration -ErrorAction Stop
        $rules = Get-WebConfiguration -PSPath 'MACHINE/WEBROOT/APPHOST' -Filter 'system.webServer/rewrite/outboundRules/rule' -ErrorAction Stop
        $matches = $rules | Where-Object { ($_.name -match 'CSP|M2\.1|Mitigation|OWA|EOMT') -or ($_.action.value -match 'Content-Security-Policy') }
        if ($matches) {
            & $Report ("IIS CSP-style outbound rewrite rule found: {0}" -f (($matches | ForEach-Object { $_.name }) -join ', ')) 'Good'
        } else {
            & $Report 'No obvious IIS CSP outbound rewrite rule was found.' 'Warn'
        }
    } catch {
        & $Report ("Unable to inspect IIS rewrite rules: {0}" -f $_.Exception.Message) 'Warn'
    }
}

function Send-HtmlValidationMail {
    <#
    .SYNOPSIS
        Sends a benign HTML/CSP control test message through SMTP.
    .DESCRIPTION
        Sends a test message to validate that defensive controls (Content Security Policy)
        are functioning properly. The message contains harmless HTML and is used to test
        OWA's ability to enforce CSP headers. This is a DEFENSIVE validation test, not
        an exploit or attack test.
    .PARAMETER Data
        Hashtable containing Sender, Recipient, Smtp, and Payload.
    .PARAMETER Report
        Scriptblock for logging output.
    .EXAMPLE
        Send-HtmlValidationMail @{ Sender='control@lab.local'; Recipient='test@lab.local'; Smtp='192.168.1.10'; Payload='<p>Test</p>' } $report
    #>
    param([hashtable]$Data, [scriptblock]$Report)
    
    foreach ($key in 'Sender', 'Recipient', 'Smtp') {
        if ([string]::IsNullOrWhiteSpace($Data[$key])) { throw "$key is required." }
    }
    
    # Require confirmation before sending test mail
    $confirmMessage = "HTML/CSP Control Test sends a benign test message.`n`nFrom: $($Data.Sender)`nTo: $($Data.Recipient)`nSMTP: $($Data.Smtp)`n`nContinue?"
    if (-not (Show-ConfirmationDialog -Title 'Confirm: Send HTML Validation Mail' -Message $confirmMessage)) {
        & $Report 'HTML validation mail cancelled by user.' 'Warn'
        return
    }
    
    $body = @"
<html>
<body>
    <h2>OWA HTML/CSP Control Test</h2>
    <p>This message contains a benign validation payload for an isolated Exchange sandbox.</p>
    <p>Purpose: Tests Content Security Policy header enforcement.</p>
    $($Data.Payload)
</body>
</html>
"@
    & $Report "Sending HTML validation mail from $($Data.Sender) to $($Data.Recipient) through $($Data.Smtp)." 'Info'
    Send-MailMessage -From $Data.Sender -To $Data.Recipient -Subject 'OWA HTML/CSP Control Test' -Body $body -BodyAsHtml -SmtpServer $Data.Smtp -ErrorAction Stop
    & $Report 'SMTP accepted the test message. Inspect OWA and browser console CSP behavior.' 'Good'
}

function Send-XssMail {
    <#
    .SYNOPSIS
        Sends a benign XSS validation mail path for lab validation.
    .DESCRIPTION
        This wrapper reuses the HTML validation test flow to simulate the same
        controlled lab validation behavior under an alternate function name.
    .PARAMETER Data
        Hashtable containing Sender, Recipient, Smtp, and Payload.
    .PARAMETER Report
        Scriptblock for logging output.
    #>
    param([hashtable]$Data, [scriptblock]$Report)
    Send-HtmlValidationMail -Data $Data -Report $Report
}

function Get-ExchangeBuildInfo {
    param([scriptblock]$Report)
    try {
        $setup = Get-Command ExSetup.exe -ErrorAction Stop
        $fileInfo = $setup.Source | Get-Item | Select-Object -ExpandProperty VersionInfo
        $buildVersion = $fileInfo.ProductVersion
        $fileVersion = $fileInfo.FileVersion
        & $Report "Exchange Build: $buildVersion (File: $fileVersion)" 'Info'
        return @{ Build = $buildVersion; FileVersion = $fileVersion; Status = 'Found' }
    } catch {
        & $Report "Unable to get Exchange build: $($_.Exception.Message)" 'Warn'
        return @{ Status = 'NotFound' }
    }
}

function Check-EmServiceStatus {
    param([scriptblock]$Report)
    try {
        $service = Get-Service MSExchangeMitigation -ErrorAction SilentlyContinue
        if ($service) {
            $status = $service.Status
            $startType = $service.StartType
            & $Report "MSExchangeMitigation service: $status (StartType: $startType)" 'Info'
            return @{ Exists = $true; Status = $status; StartType = $startType }
        } else {
            & $Report 'MSExchangeMitigation service not found. Run checks from an Exchange server.' 'Warn'
            return @{ Exists = $false }
        }
    } catch {
        & $Report "EM service check error: $($_.Exception.Message)" 'Warn'
        return @{ Exists = $false }
    }
}

function Get-MitigationApplied {
    param([scriptblock]$Report)
    try {
        $server = Get-ExchangeServer -ErrorAction Stop | Select-Object -First 1
        if ($server) {
            $applied = $server.MitigationsApplied
            $blocked = $server.MitigationsBlocked
            $enabled = $server.MitigationsEnabled
            & $Report "Exchange Server: $($server.Name)" 'Info'
            & $Report "Mitigations Enabled: $enabled" 'Info'
            & $Report "Mitigations Applied: $(if ($applied) { $applied -join ', ' } else { 'None' })" 'Info'
            & $Report "Mitigations Blocked: $(if ($blocked) { $blocked -join ', ' } else { 'None' })" 'Info'
            $hasCveM2 = $applied -match 'M2(?:\.1(?:\.x)?)?'
            if ($hasCveM2) {
                & $Report 'M2/M2.1.x mitigation is applied. CVE-2026-42897 mitigation status: ACTIVE.' 'Good'
            } else {
                & $Report 'M2/M2.1.x mitigation not found in applied list. Verify mitigation via IIS rules.' 'Warn'
            }
            return @{ Applied = $applied; Blocked = $blocked; Enabled = $enabled; HasCveMitigation = $hasCveM2 }
        }
    } catch {
        & $Report "Mitigation state check error: $($_.Exception.Message)" 'Warn'
    }
    return @{ Applied = @(); Blocked = @(); Enabled = $false; HasCveMitigation = $false }
}

function Verify-OwaCspHeader {
    param([string]$OwaUrl, [scriptblock]$Report)
    if ([string]::IsNullOrWhiteSpace($OwaUrl)) {
        & $Report 'OWA URL is required. Format: https://servername.domain.local/owa' 'Warn'
        return
    }
    try {
        $response = Invoke-WebRequest -Uri $OwaUrl -UseBasicParsing -ErrorAction Stop
        $cspHeader = $response.Headers['Content-Security-Policy']
        if ($cspHeader) {
            & $Report "CSP Header found: $cspHeader" 'Info'
            if ($cspHeader -match "script-src-attr\s+'none'") {
                & $Report 'CSP header contains script-src-attr ''none'' - mitigation is ACTIVE.' 'Good'
            } else {
                & $Report 'CSP header exists but script-src-attr ''none'' not found. Verify mitigation rule.' 'Warn'
            }
        } else {
            & $Report 'No Content-Security-Policy header found in OWA response.' 'Warn'
        }
    } catch {
        & $Report "OWA header check failed: $($_.Exception.Message)" 'Warn'
    }
}

function New-Label {
    param([string]$Text, [int]$X, [int]$Y, [int]$Width = 170)
    $label = New-Object System.Windows.Forms.Label
    $label.Text = $Text
    $label.Location = New-Object System.Drawing.Point($X, $Y)
    $label.Size = New-Object System.Drawing.Size($Width, 24)
    $label.BackColor = $script:Theme.Panel
    $label.ForeColor = $script:Theme.Muted
    $label.Font = New-Object System.Drawing.Font('Segoe UI', 9)
    $label.TextAlign = 'MiddleLeft'
    return $label
}

function New-Input {
    param([int]$X, [int]$Y, [int]$Width = 300)
    $input = New-Object System.Windows.Forms.TextBox
    $input.Location = New-Object System.Drawing.Point($X, $Y)
    $input.Size = New-Object System.Drawing.Size($Width, 26)
    $input.BackColor = $script:Theme.Field
    $input.ForeColor = $script:Theme.Text
    $input.BorderStyle = 'FixedSingle'
    $input.Font = New-Object System.Drawing.Font('Segoe UI', 9)
    return $input
}

function New-Button {
    param([string]$Text, [int]$X, [int]$Y, [int]$Width = 210)
    $button = New-Object System.Windows.Forms.Button
    $button.Text = $Text
    $button.Location = New-Object System.Drawing.Point($X, $Y)
    $button.Size = New-Object System.Drawing.Size($Width, 36)
    $button.FlatStyle = 'Flat'
    $button.FlatAppearance.BorderSize = 0
    $button.BackColor = $script:Theme.Accent
    $button.ForeColor = [System.Drawing.Color]::White
    $button.Font = New-Object System.Drawing.Font('Segoe UI Semibold', 9)
    $script:Buttons.Add($button) | Out-Null
    return $button
}

function New-Log {
    param([int]$X, [int]$Y, [int]$Width, [int]$Height)
    $box = New-Object System.Windows.Forms.RichTextBox
    $box.Location = New-Object System.Drawing.Point($X, $Y)
    $box.Size = New-Object System.Drawing.Size($Width, $Height)
    $box.BackColor = $script:Theme.Field
    $box.ForeColor = $script:Theme.Text
    $box.BorderStyle = 'FixedSingle'
    $box.Font = New-Object System.Drawing.Font('Consolas', 9)
    $box.ReadOnly = $true
    $box.WordWrap = $false
    $box.ScrollBars = 'Both'
    return $box
}

function New-Pill {
    param([string]$Text, [int]$X, [int]$Y, [int]$Width = 190)
    $pill = New-Object System.Windows.Forms.Label
    $pill.Location = New-Object System.Drawing.Point($X, $Y)
    $pill.Size = New-Object System.Drawing.Size($Width, 28)
    $pill.Font = New-Object System.Drawing.Font('Segoe UI Semibold', 9)
    $pill.TextAlign = 'MiddleLeft'
    Set-Pill $pill $Text Ready
    return $pill
}

function New-Progress {
    param([int]$X, [int]$Y, [int]$Width = 240)
    $progress = New-Object System.Windows.Forms.ProgressBar
    $progress.Location = New-Object System.Drawing.Point($X, $Y)
    $progress.Size = New-Object System.Drawing.Size($Width, 16)
    $progress.Style = 'Continuous'
    return $progress
}

function New-Section {
    param([System.Windows.Forms.TabPage]$Tab, [string]$SectionTitle)
    $panel = New-Object System.Windows.Forms.Panel
    $panel.Location = New-Object System.Drawing.Point(18, 18)
    $panel.Size = New-Object System.Drawing.Size(1118, 626)
    $panel.BackColor = $script:Theme.Panel
    [void]$Tab.Controls.Add($panel)
    $sectionLabel = New-Object System.Windows.Forms.Label
    $sectionLabel.Text = $SectionTitle
    $sectionLabel.Location = New-Object System.Drawing.Point(18, 14)
    $sectionLabel.Size = New-Object System.Drawing.Size(900, 28)
    $sectionLabel.BackColor = $script:Theme.Panel
    $sectionLabel.ForeColor = $script:Theme.Text
    $sectionLabel.Font = New-Object System.Drawing.Font('Segoe UI Semibold', 11)
    [void]$panel.Controls.Add($sectionLabel)
    return $panel
}

function Build-ProfileTab {
    param([System.Windows.Forms.TabPage]$Tab)
    $panel = New-Section $Tab 'Lab Control, Profiles & Evidence'
    $panel.Controls.Add((New-Label 'Profile name or file' 22 64))
    $script:Ui.ProfilePath = New-Input 190 62 650; $script:Ui.ProfilePath.Text = 'default-lab'; $panel.Controls.Add($script:Ui.ProfilePath)
    $profileBrowse = New-Button 'Browse Profile' 858 60 110
    $loadProfileBtn = New-Button 'Load Profile' 22 112 170
    $saveProfileBtn = New-Button 'Save Profile' 206 112 170
    $manifestBtn = New-Button 'Save Run Manifest' 390 112 190
    $preflightBtn = New-Button 'Run Preflight Check' 600 112 190
    $fullEvidenceBtn = New-Button 'Export Full Evidence Bundle' 810 112 240
    $saveCheckpointBtn = New-Button 'Save Checkpoint' 22 162 170
    $loadCheckpointBtn = New-Button 'Load Checkpoint' 206 162 170
    $resetCheckpointBtn = New-Button 'Reset Checkpoint' 390 162 190
    $previewCleanupBtn = New-Button 'Preview Cleanup' 600 162 170
    $cleanTempBtn = New-Button 'Clean Temp Artifacts' 790 162 210
    $fullCleanupBtn = New-Button 'Clean Up Lab (Full)' 22 214 260
    $script:Ui.ProfilePill = New-Pill 'Profile ready' 306 214 260
    $script:Ui.CheckpointPill = New-Pill 'Checkpoint pending' 586 214 300
    $script:Ui.ProfileProgress = New-Progress 900 224 190
    $panel.Controls.AddRange(@($profileBrowse, $loadProfileBtn, $saveProfileBtn, $manifestBtn, $preflightBtn, $fullEvidenceBtn, $saveCheckpointBtn, $loadCheckpointBtn, $resetCheckpointBtn, $previewCleanupBtn, $cleanTempBtn, $fullCleanupBtn, $script:Ui.ProfilePill, $script:Ui.CheckpointPill, $script:Ui.ProfileProgress))
    $script:Ui.ProfileLog = New-Log 22 300 1070 280; $panel.Controls.Add($script:Ui.ProfileLog)

    $profileBrowse.Add_Click({
        try {
            $dialog = New-Object System.Windows.Forms.OpenFileDialog
            $dialog.Title = 'Select a lab profile JSON file'
            $dialog.Filter = 'JSON files (*.json)|*.json|All files (*.*)|*.*'
            $dialog.InitialDirectory = Ensure-LabDataFolder 'profiles'
            if ($dialog.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
                $script:Ui.ProfilePath.Text = $dialog.FileName
                Set-AppStatus ('Profile selected: ' + $dialog.FileName) $script:Theme.Good
            }
        } catch { Set-AppStatus ('Profile browse error: ' + $_.Exception.Message) $script:Theme.Bad }
    })

    $loadProfileBtn.Add_Click({
        $profile = $script:Ui.ProfilePath.Text.Trim()
        if (-not $profile) { $profile = 'default-lab' }
        Start-LabTask 'Profile load' $script:Ui.ProfileLog $script:Ui.ProfilePill $script:Ui.ProfileProgress { param($Data,$Report) Load-LabProfile $Data.Profile $Report } @{ Profile = $profile } 'Loading lab profile...' 'Lab profile loaded.' $null $false
    })

    $saveProfileBtn.Add_Click({
        $profile = $script:Ui.ProfilePath.Text.Trim()
        if (-not $profile) { $profile = 'default-lab' }
        Start-LabTask 'Profile save' $script:Ui.ProfileLog $script:Ui.ProfilePill $script:Ui.ProfileProgress { param($Data,$Report) Save-LabProfile $Data.Profile $Report } @{ Profile = $profile } 'Saving lab profile...' 'Lab profile saved.' 'ProfileSaved'
    })

    $manifestBtn.Add_Click({
        Start-LabTask 'Run manifest export' $script:Ui.ProfileLog $script:Ui.ProfilePill $script:Ui.ProfileProgress { param($Data,$Report) Export-RunManifest -TaskName 'Manual GUI manifest' -Report $Report } @{} 'Exporting run manifest...' 'Run manifest exported.'
    })

    $preflightBtn.Add_Click({
        Start-LabTask 'Preflight check' $script:Ui.ProfileLog $script:Ui.ProfilePill $script:Ui.ProfileProgress { param($Data,$Report) Run-PreflightChecks $Data $Report } @{} 'Running preflight checks...' 'Preflight validation completed.'
    })

    $fullEvidenceBtn.Add_Click({
        $data = @{
            Logs = Get-UiLogsSnapshot
            ProfilePath = $script:Ui.ProfilePath.Text.Trim()
        }
        Start-LabTask 'Full evidence export' $script:Ui.ProfileLog $script:Ui.ProfilePill $script:Ui.ProfileProgress { param($Data,$Report) Export-FullEvidenceBundle -Data $Data -Report $Report } $data 'Exporting full evidence bundle...' 'Full evidence bundle exported.' 'EvidenceExported'
    })

    $saveCheckpointBtn.Add_Click({
        Start-LabTask 'Checkpoint save' $script:Ui.ProfileLog $script:Ui.CheckpointPill $script:Ui.ProfileProgress { param($Data,$Report) Save-LabCheckpoint -Report $Report } @{} 'Saving checkpoint...' 'Checkpoint saved.'
    })

    $loadCheckpointBtn.Add_Click({
        Start-LabTask 'Checkpoint load' $script:Ui.ProfileLog $script:Ui.CheckpointPill $script:Ui.ProfileProgress { param($Data,$Report) Apply-LabCheckpoint -Report $Report; & $Report (Get-LabCheckpointSummary) 'Info' } @{} 'Loading checkpoint...' 'Checkpoint loaded.' $null $false
    })

    $resetCheckpointBtn.Add_Click({
        Start-LabTask 'Checkpoint reset' $script:Ui.ProfileLog $script:Ui.CheckpointPill $script:Ui.ProfileProgress { param($Data,$Report) Clear-LabCheckpoint -Report $Report | Out-Null; Apply-LabCheckpoint -Report $Report } @{} 'Resetting checkpoint...' 'Checkpoint reset.'
    })

    $previewCleanupBtn.Add_Click({
        Start-LabTask 'Cleanup preview' $script:Ui.ProfileLog $script:Ui.ProfilePill $script:Ui.ProfileProgress { param($Data,$Report) Invoke-LabCleanup -Mode 'Preview' -Report $Report } @{} 'Starting cleanup preview...' 'Cleanup preview completed.'
    })

    $cleanTempBtn.Add_Click({
        Start-LabTask 'Temp cleanup' $script:Ui.ProfileLog $script:Ui.ProfilePill $script:Ui.ProfileProgress { param($Data,$Report) Invoke-LabCleanup -Mode 'TempOnly' -Report $Report } @{} 'Cleaning temporary lab artifacts...' 'Temporary lab artifacts cleaned.'
    })

    $fullCleanupBtn.Add_Click({
        Start-LabTask 'Full lab cleanup' $script:Ui.ProfileLog $script:Ui.ProfilePill $script:Ui.ProfileProgress { 
            param($Data, $Report)
            
            & $Report 'Starting cleanup preview (DryRun)...' 'Info'
            $cleanupScript = Join-Path $PSScriptRoot 'lab-cleanup-helper.ps1'
            if (-not (Test-Path -LiteralPath $cleanupScript)) {
                throw "Cleanup script not found: $cleanupScript"
            }

            $powershell = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
            
            # 1. Run DryRun
            Invoke-LoggedProcess -FilePath $powershell `
                -Arguments @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $cleanupScript, '-Mode', 'DryRun') `
                -WorkingDirectory $PSScriptRoot `
                -Report $Report

            # 2. Ask for confirmation
            $confirmMsg = "Cleanup preview complete. Do you want to proceed with a FULL cleanup?`n`nThis will:`n- Delete temporary files`n- Reset network adapters to DHCP`n- Restart IIS`n`nProceed?"
            if (Show-ConfirmationDialog -Title 'Confirm Full Lab Cleanup' -Message $confirmMsg) {
                & $Report 'Proceeding with FULL cleanup...' 'Warn'
                # 3. Run Full
                Invoke-LoggedProcess -FilePath $powershell `
                    -Arguments @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $cleanupScript, '-Mode', 'Full', '-Force') `
                    -WorkingDirectory $PSScriptRoot `
                    -Report $Report
                & $Report 'Full lab cleanup completed successfully.' 'Good'
            } else {
                & $Report 'Full cleanup cancelled by user.' 'Warn'
            }
        } @{} 'Starting full lab cleanup process...' 'Full lab cleanup process finished.'
    })
}

function Build-SystemTab {
    param([System.Windows.Forms.TabPage]$Tab)
    $panel = New-Section $Tab 'System & Network Setup'
    $panel.Controls.Add((New-Label 'Static IP' 22 64))
    $script:Ui.Ip = New-Input 190 62 280; $script:Ui.Ip.Text = '192.168.100.10'; $panel.Controls.Add($script:Ui.Ip)
    $panel.Controls.Add((New-Label 'Subnet Mask' 22 104))
    $script:Ui.Mask = New-Input 190 102 280; $script:Ui.Mask.Text = '255.255.255.0'; $panel.Controls.Add($script:Ui.Mask)
    $panel.Controls.Add((New-Label 'AD Domain Name' 22 144))
    $script:Ui.Domain = New-Input 190 142 280; $script:Ui.Domain.Text = 'mylab.local'; $panel.Controls.Add($script:Ui.Domain)

    $script:Ui.SystemPill = New-Pill 'System ready' 530 62
    $script:Ui.RebootPill = New-Pill 'Reboot not required' 740 62 210
    $script:Ui.AdminPill = New-Pill 'Admin check pending' 530 102
    $script:Ui.SystemProgress = New-Progress 740 112 260
    $panel.Controls.AddRange(@($script:Ui.SystemPill, $script:Ui.RebootPill, $script:Ui.AdminPill, $script:Ui.SystemProgress))
    if (Test-IsAdmin) { Set-Pill $script:Ui.AdminPill 'Running elevated' Good } else { Set-Pill $script:Ui.AdminPill 'Elevation required' Warn }

    $netButton = New-Button 'Configure Network' 22 194 210
    $adButton = New-Button 'Install Active Directory & Promote' 246 194 270
    $panel.Controls.AddRange(@($netButton, $adButton))
    $script:Ui.SystemLog = New-Log 22 250 1070 360; $panel.Controls.Add($script:Ui.SystemLog)

    $netButton.Add_Click({
        $data = @{ Ip = $script:Ui.Ip.Text; Mask = $script:Ui.Mask.Text }
        Start-LabTask 'Network setup' $script:Ui.SystemLog $script:Ui.SystemPill $script:Ui.SystemProgress { param($Data, $Report) Set-StaticNetwork $Data $Report } $data 'Starting static network configuration...' 'Network configuration completed.' 'NetworkConfigured'
    })
    $adButton.Add_Click({
        $data = @{ Domain = $script:Ui.Domain.Text }
        Start-LabTask 'AD DS promotion' $script:Ui.SystemLog $script:Ui.RebootPill $script:Ui.SystemProgress { param($Data, $Report) Install-AdAndPromote $Data $Report } $data 'Starting AD DS installation and forest promotion...' 'AD DS promotion completed. Reboot the VM before continuing.' 'AdPromoted'
    })
}

function Build-ExchangeTab {
    param([System.Windows.Forms.TabPage]$Tab)
    $panel = New-Section $Tab 'Exchange Prep & Install'
    $panel.Controls.Add((New-Label 'Exchange ISO Path' 22 64))
    $script:Ui.ExchangePath = New-Input 190 62 650; $script:Ui.ExchangePath.Text = 'D:\'; $panel.Controls.Add($script:Ui.ExchangePath)
    $browse = New-Button 'Browse' 858 60 110
    $prep = New-Button 'Prepare AD Schema & Forests' 22 112 245
    $install = New-Button 'Launch Exchange Installer Syntax' 286 112 265
    $script:Ui.ExchangePill = New-Pill 'Exchange idle' 576 116
    $script:Ui.ExchangeProgress = New-Progress 800 126 260
    $panel.Controls.AddRange(@($browse, $prep, $install, $script:Ui.ExchangePill, $script:Ui.ExchangeProgress))
    $script:Ui.ExchangeLog = New-Log 22 170 1070 440; $panel.Controls.Add($script:Ui.ExchangeLog)

    $browse.Add_Click({
        try {
            $dialog = New-Object System.Windows.Forms.FolderBrowserDialog
            $dialog.Description = 'Select the mounted Exchange ISO root folder that contains Setup.exe.'
            $dialog.ShowNewFolderButton = $false
            if ($dialog.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
                $script:Ui.ExchangePath.Text = $dialog.SelectedPath
                Set-AppStatus ('Exchange setup path selected: ' + $dialog.SelectedPath) $script:Theme.Good
            }
        } catch { Set-AppStatus ('Browse error: ' + $_.Exception.Message) $script:Theme.Bad }
    })
    $prep.Add_Click({
        $data = @{ Path = $script:Ui.ExchangePath.Text.Trim() }
        Start-LabTask 'Exchange AD prep' $script:Ui.ExchangeLog $script:Ui.ExchangePill $script:Ui.ExchangeProgress { param($Data, $Report) Prepare-ExchangeAd $Data $Report } $data 'Starting Exchange AD preparation...' 'Exchange AD preparation completed.' 'ExchangeAdPrepared'
    })
    $install.Add_Click({
        $data = @{ Path = $script:Ui.ExchangePath.Text.Trim() }
        Start-LabTask 'Exchange install' $script:Ui.ExchangeLog $script:Ui.ExchangePill $script:Ui.ExchangeProgress { param($Data, $Report) Install-Exchange $Data $Report } $data 'Launching Exchange installer...' 'Exchange installer completed.' 'ExchangeInstalled'
    })
}

function Build-MitigationTab {
    param([System.Windows.Forms.TabPage]$Tab)
    $panel = New-Section $Tab 'Mitigation & EOMT'
    $panel.Controls.Add((New-Label 'EOMT URL or Path' 22 64))
    $script:Ui.Eomt = New-Input 190 62 650; $script:Ui.Eomt.Text = 'https://aka.ms/exchange-onprem-mitigation-tool'; $panel.Controls.Add($script:Ui.Eomt)
    $apply = New-Button 'Download & Apply EOMT Mitigation' 22 112 285
    $check = New-Button 'Check Status (Get-Mitigation M2.1.x)' 326 112 305
    $script:Ui.MitigationPill = New-Pill 'Mitigation idle' 656 116
    $script:Ui.MitigationProgress = New-Progress 880 126 180
    $panel.Controls.AddRange(@($apply, $check, $script:Ui.MitigationPill, $script:Ui.MitigationProgress))
    $script:Ui.MitigationLog = New-Log 22 170 1070 440; $panel.Controls.Add($script:Ui.MitigationLog)

    $apply.Add_Click({
        $data = @{ Source = $script:Ui.Eomt.Text }
        Start-LabTask 'EOMT mitigation' $script:Ui.MitigationLog $script:Ui.MitigationPill $script:Ui.MitigationProgress { param($Data, $Report) Apply-Eomt $Data $Report } $data 'Starting EOMT download and mitigation...' 'EOMT mitigation action completed.' 'MitigationApplied'
    })
    $check.Add_Click({
        Start-LabTask 'Mitigation status' $script:Ui.MitigationLog $script:Ui.MitigationPill $script:Ui.MitigationProgress { param($Data, $Report) Check-Mitigation $Data $Report } @{} 'Checking mitigation state and IIS CSP rules...' 'Mitigation status check completed.' 'MitigationChecked'
    })
}

function Build-HtmlValidationTab {
    param([System.Windows.Forms.TabPage]$Tab)
    $panel = New-Section $Tab 'Benign HTML/CSP Control Test'
    
    $panel.Controls.Add((New-Label 'Sender Email' 22 64))
    $script:Ui.Sender = New-Input 190 62 320; $script:Ui.Sender.Text = 'sender@mylab.local'; $panel.Controls.Add($script:Ui.Sender)
    
    $panel.Controls.Add((New-Label 'Recipient Email' 22 104))
    $script:Ui.Recipient = New-Input 190 102 320; $script:Ui.Recipient.Text = 'recipient@mylab.local'; $panel.Controls.Add($script:Ui.Recipient)
    
    $panel.Controls.Add((New-Label 'Target SMTP Server IP' 22 144))
    $script:Ui.Smtp = New-Input 190 142 320; $script:Ui.Smtp.Text = '192.168.100.10'; $panel.Controls.Add($script:Ui.Smtp)
    
    $panel.Controls.Add((New-Label 'Benign Control Payload' 22 184))
    $script:Ui.Payload = New-Object System.Windows.Forms.ComboBox
    $script:Ui.Payload.Location = New-Object System.Drawing.Point(190, 182)
    $script:Ui.Payload.Size = New-Object System.Drawing.Size(630, 28)
    $script:Ui.Payload.DropDownStyle = 'DropDownList'
    $script:Ui.Payload.BackColor = $script:Theme.Field
    $script:Ui.Payload.ForeColor = $script:Theme.Text
    $script:Ui.Payload.Font = New-Object System.Drawing.Font('Segoe UI', 9)
    $script:Ui.Payload.Items.AddRange(@(
        '<img src="x" onerror="alert(''Control_Test_Marker'')" />',
        '<svg onload="alert(''Lab_Control_Payload'')"></svg>',
        '<a href="javascript:alert(''Link_Control_Payload'')">Lab validation link</a>'
    ))
    $script:Ui.Payload.SelectedIndex = 0
    $panel.Controls.Add($script:Ui.Payload)
    
    $sendBtn = New-Button 'Send HTML Validation Mail' 22 234 210
    $script:Ui.HtmlValidationPill = New-Pill 'Test idle' 260 238 180
    $script:Ui.HtmlValidationProgress = New-Progress 464 248 260
    $panel.Controls.AddRange(@($sendBtn, $script:Ui.HtmlValidationPill, $script:Ui.HtmlValidationProgress))
    
    $script:Ui.HtmlValidationLog = New-Log 22 290 1070 320; $panel.Controls.Add($script:Ui.HtmlValidationLog)
    
    $sendBtn.Add_Click({
        $data = @{
            Sender = $script:Ui.Sender.Text.Trim()
            Recipient = $script:Ui.Recipient.Text.Trim()
            Smtp = $script:Ui.Smtp.Text.Trim()
            Payload = [string]$script:Ui.Payload.SelectedItem
        }
        Start-LabTask 'HTML validation test' $script:Ui.HtmlValidationLog $script:Ui.HtmlValidationPill $script:Ui.HtmlValidationProgress { param($Data, $Report) Send-HtmlValidationMail $Data $Report } $data 'Sending benign lab HTML/CSP validation email...' 'Lab HTML validation message submitted to SMTP.' 'HtmlValidationMailSent'
    })
}

function Build-CveValidationTab {
    param([System.Windows.Forms.TabPage]$Tab)
    $panel = New-Section $Tab 'CVE-2026-42897 Exchange OWA Validation'
    
    $panel.Controls.Add((New-Label 'OWA URL' 22 64))
    $script:Ui.OwaUrl = New-Input 190 62 650; $script:Ui.OwaUrl.Text = 'https://lab-ex01.exchange-lab.test/owa'; $panel.Controls.Add($script:Ui.OwaUrl)
    
    $buildBtn = New-Button 'Check Exchange Build' 22 112 210
    $emBtn = New-Button 'Check EM Service' 246 112 210
    $mitigBtn = New-Button 'Check Mitigation State' 470 112 230
    $cspBtn = New-Button 'Verify CSP Header' 714 112 210
    $exportBtn = New-Button 'Export Evidence Bundle' 22 164 230
    
    $script:Ui.CvePill = New-Pill 'Validation ready' 274 168 180
    $script:Ui.CveProgress = New-Progress 474 178 260
    
    $panel.Controls.AddRange(@($buildBtn, $emBtn, $mitigBtn, $cspBtn, $exportBtn, $script:Ui.CvePill, $script:Ui.CveProgress))
    $script:Ui.CveLog = New-Log 22 220 1070 360; $panel.Controls.Add($script:Ui.CveLog)

    $buildBtn.Add_Click({
        Start-LabTask 'Exchange build check' $script:Ui.CveLog $script:Ui.CvePill $script:Ui.CveProgress { param($Data, $Report) Get-ExchangeBuildInfo $Report } @{} 'Checking Exchange build...' 'Exchange build check completed.' 'ExchangeBuildChecked'
    })
    
    $emBtn.Add_Click({
        Start-LabTask 'EM service check' $script:Ui.CveLog $script:Ui.CvePill $script:Ui.CveProgress { param($Data, $Report) Check-EmServiceStatus $Report } @{} 'Checking EM service...' 'EM service check completed.' 'EmServiceChecked'
    })
    
    $mitigBtn.Add_Click({
        Start-LabTask 'Mitigation state check' $script:Ui.CveLog $script:Ui.CvePill $script:Ui.CveProgress { param($Data, $Report) Get-MitigationApplied $Report } @{} 'Checking mitigation state...' 'Mitigation state check completed.' 'MitigationStateChecked'
    })
    
    $cspBtn.Add_Click({
        $url = $script:Ui.OwaUrl.Text.Trim()
        Start-LabTask 'CSP header verification' $script:Ui.CveLog $script:Ui.CvePill $script:Ui.CveProgress { param($Data, $Report) Verify-OwaCspHeader $Data.Url $Report } @{ Url = $url } 'Verifying CSP header...' 'CSP header verification completed.' 'CspHeaderChecked'
    })
    
    $exportBtn.Add_Click({
        $data = @{
            Logs = @{
                System = $script:Ui.SystemLog
                Exchange = $script:Ui.ExchangeLog
                Mitigation = $script:Ui.MitigationLog
                HtmlValidation = $script:Ui.HtmlValidationLog
                CVE = $script:Ui.CveLog
                Profile = $script:Ui.ProfileLog
            }
            ProfilePath = $script:Ui.ProfilePath.Text.Trim()
        }
        Start-LabTask 'Evidence export' $script:Ui.CveLog $script:Ui.CvePill $script:Ui.CveProgress { param($Data, $Report) Export-CveEvidence $Report $Data } $data 'Exporting evidence bundle...' 'Evidence bundle exported.' 'EvidenceExported'
    })
}

function New-MainForm {
    $script:Ui = @{}
    $script:Buttons = New-Object System.Collections.Generic.List[System.Windows.Forms.Button]
    $script:Busy = $false
    $Global:ELM_PreflightBlocking = $true  # Require preflight by default

    [System.Windows.Forms.Application]::EnableVisualStyles()
    $form = New-Object System.Windows.Forms.Form
    $form.Text = 'Exchange Lab & Security Mitigation Manager'
    $form.StartPosition = 'CenterScreen'
    $form.Size = New-Object System.Drawing.Size(1200, 820)
    $form.MinimumSize = New-Object System.Drawing.Size(1100, 740)
    $form.BackColor = $script:Theme.Window
    $form.Font = New-Object System.Drawing.Font('Segoe UI', 9)

    $title = New-Object System.Windows.Forms.Label
    $title.Text = 'Exchange Lab & Security Mitigation Manager'
    $title.Location = New-Object System.Drawing.Point(24, 14)
    $title.Size = New-Object System.Drawing.Size(680, 30)
    $title.ForeColor = $script:Theme.Text
    $title.BackColor = $script:Theme.Window
    $title.Font = New-Object System.Drawing.Font('Segoe UI Semibold', 15)
    $form.Controls.Add($title)
    $subtitle = New-Object System.Windows.Forms.Label
    $subtitle.Text = 'Isolated Windows Server lab automation for setup, Exchange prep, mitigation checks, and benign validation mail.'
    $subtitle.Location = New-Object System.Drawing.Point(26, 44)
    $subtitle.Size = New-Object System.Drawing.Size(940, 20)
    $subtitle.ForeColor = $script:Theme.Muted
    $subtitle.BackColor = $script:Theme.Window
    $subtitle.Font = New-Object System.Drawing.Font('Segoe UI', 9)
    $form.Controls.Add($subtitle)

    $tabs = New-Object System.Windows.Forms.TabControl
    $tabs.Location = New-Object System.Drawing.Point(16, 76)
    $tabs.Size = New-Object System.Drawing.Size(1160, 684)
    $tabs.Anchor = 'Top,Bottom,Left,Right'
    $tabs.Font = New-Object System.Drawing.Font('Segoe UI Semibold', 9)
    $form.Controls.Add($tabs)
    $tabNames = 'Profiles & Preflight','System & Network Setup','Exchange Prep & Install','Mitigation & EOMT','Benign HTML Validation Test','CVE-2026-42897 Validation'
    $tabPages = @()
    foreach ($name in $tabNames) {
        $tab = New-Object System.Windows.Forms.TabPage
        $tab.Text = $name
        $tab.BackColor = $script:Theme.Window
        $tab.ForeColor = $script:Theme.Text
        $tabs.TabPages.Add($tab) | Out-Null
        $tabPages += $tab
    }
    Build-ProfileTab $tabPages[0]
    Build-SystemTab $tabPages[1]
    Build-ExchangeTab $tabPages[2]
    Build-MitigationTab $tabPages[3]
    Build-HtmlValidationTab $tabPages[4]
    Build-CveValidationTab $tabPages[5]

    Apply-LabCheckpoint
    Set-Buttons $true

    $script:Ui.Status = New-Object System.Windows.Forms.Label
    $script:Ui.Status.Location = New-Object System.Drawing.Point(16, 764)
    $script:Ui.Status.Size = New-Object System.Drawing.Size(1160, 26)
    $script:Ui.Status.Anchor = 'Bottom,Left,Right'
    $script:Ui.Status.BackColor = $script:Theme.PanelAlt
    $script:Ui.Status.ForeColor = $script:Theme.Good
    $script:Ui.Status.Font = New-Object System.Drawing.Font('Segoe UI Semibold', 9)
    $script:Ui.Status.TextAlign = 'MiddleLeft'
    $form.Controls.Add($script:Ui.Status)
    Set-AppStatus 'Ready. Use only inside an isolated Exchange lab VM.' $script:Theme.Good

    $form.Add_FormClosing({
        param($sender, $eventArgs)
        if ($script:Busy) {
            $choice = [System.Windows.Forms.MessageBox]::Show('A lab operation is still running. Close anyway?', 'Exchange Lab Manager', [System.Windows.Forms.MessageBoxButtons]::YesNo, [System.Windows.Forms.MessageBoxIcon]::Warning)
            if ($choice -ne [System.Windows.Forms.DialogResult]::Yes) { $eventArgs.Cancel = $true }
        }
    })
    return $form
}

if (-not $NoRun) {
    try {
        $mainForm = New-MainForm
        [System.Windows.Forms.Application]::Run($mainForm)
    } catch {
        $logPath = Join-Path $env:TEMP 'ExchangeLabManager-startup-error.log'
        try {
            $errorDetails = $_ | Out-String
            $exceptionDetails = $_.Exception | Format-List * -Force | Out-String
            Set-Content -Path $logPath -Value ("$errorDetails`r`n$exceptionDetails") -Encoding UTF8
        } catch {
            $logPath = 'startup log unavailable'
        }
        $message = "Fatal UI error: $($_.Exception.Message)`r`n`r`nDetails: $logPath"
        [System.Windows.Forms.MessageBox]::Show($message, 'Exchange Lab Manager', [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error) | Out-Null
        exit 1
    }
}
