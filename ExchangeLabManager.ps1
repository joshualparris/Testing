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
    [switch]$NoRun
)

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

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
    'XssMailSent',
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
    XssMailSent = 'XSS mail sent'
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
    $profiles = Ensure-LabDataFolder 'profiles'
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
        Attacker = Get-UiTextValue 'Attacker' 'attacker@mylab.local'
        Victim = Get-UiTextValue 'Victim' 'victim@mylab.local'
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
    Set-UiTextValue 'Attacker' (Get-ObjectValue $Inputs 'Attacker' (Get-UiTextValue 'Attacker'))
    Set-UiTextValue 'Victim' (Get-ObjectValue $Inputs 'Victim' (Get-UiTextValue 'Victim'))
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
            'XssMailSent' { if ($script:Ui.XssPill) { Set-Pill $script:Ui.XssPill 'Validation sent' Good } }
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
        [Parameter(Mandatory)][System.Collections.Generic.List[object]]$Results,
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
    foreach ($button in $script:Buttons) { $button.Enabled = $Enabled }
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

function Get-WorkspaceRoot {
    if ($PSScriptRoot) { return $PSScriptRoot }
    if ($MyInvocation.MyCommand.Path) { return Split-Path -Parent $MyInvocation.MyCommand.Path }
    return (Get-Location).ProviderPath
}

$script:BasePath = Get-WorkspaceRoot
$script:CheckpointPath = Join-Path $script:BasePath 'lab-run-checkpoint.json'
$script:ProfileDirectory = Join-Path $script:BasePath 'lab-profiles'

function Load-RunCheckpoint {
    if (-not (Test-Path -LiteralPath $script:CheckpointPath)) { return @{} }
    try { Get-Content -Path $script:CheckpointPath -Raw | ConvertFrom-Json -ErrorAction Stop } catch { return @{} }
}

function Save-RunCheckpoint {
    param([Parameter(Mandatory)][hashtable]$Checkpoint)
    $checkpoint = [ordered]@{
        LastUpdated = (Get-Date).ToString('u')
        Steps = $Checkpoint.Steps
        Metadata = $Checkpoint.Metadata
    }
    $checkpoint | ConvertTo-Json -Depth 6 | Set-Content -Path $script:CheckpointPath -Encoding UTF8
    return $script:CheckpointPath
}

function Update-RunCheckpoint {
    param(
        [Parameter(Mandatory)][string]$StepName,
        [string]$State = 'Completed'
    )
    $checkpoint = Load-RunCheckpoint
    if (-not $checkpoint.Steps) { $checkpoint.Steps = @() }
    $step = $checkpoint.Steps | Where-Object { $_.Name -eq $StepName }
    if (-not $step) {
        $step = [ordered]@{ Name = $StepName; State = $State; Completed = (Get-Date).ToString('u') }
        $checkpoint.Steps += $step
    } else {
        $step.State = $State
        $step.Completed = (Get-Date).ToString('u')
    }
    Save-RunCheckpoint -Checkpoint $checkpoint | Out-Null
    return $checkpoint
}

function Apply-RunCheckpoint {
    $checkpoint = Load-RunCheckpoint
    if (-not $checkpoint.Steps) { return }
    $lastStep = $checkpoint.Steps[-1]
    foreach ($step in $checkpoint.Steps) {
        switch ($step.Name) {
            'Network setup' { Set-Pill $script:Ui.SystemPill 'Network configured' Good }
            'AD DS promotion' { Set-Pill $script:Ui.RebootPill 'AD DS promoted' Good }
            'Exchange AD prep' { Set-Pill $script:Ui.ExchangePill 'Exchange AD prep complete' Good }
            'Exchange install' { Set-Pill $script:Ui.ExchangePill 'Exchange installed' Good }
            'EOMT mitigation' { Set-Pill $script:Ui.MitigationPill 'EOMT mitigation applied' Good }
            'Mitigation status' { Set-Pill $script:Ui.MitigationPill 'Mitigation status checked' Good }
            'XSS email test' { Set-Pill $script:Ui.XssPill 'Validation test sent' Good }
            'Evidence export' { Set-Pill $script:Ui.CvePill 'Evidence exported' Good }
            'Preflight check' { if ($script:Ui.ProfilePill) { Set-Pill $script:Ui.ProfilePill 'Preflight passed' Good } }
            'Lab cleanup' { if ($script:Ui.ProfilePill) { Set-Pill $script:Ui.ProfilePill 'Cleanup run' Good } }
        }
    }
    if ($script:Ui.CheckpointPill -and $lastStep) {
        Set-Pill $script:Ui.CheckpointPill ("Last checkpoint: $($lastStep.Name)") Good
    }
    if ($lastStep) { Set-AppStatus ("Resumed from last checkpoint: $($lastStep.Name)") $script:Theme.Good }
}

function Set-TaskCheckpoint {
    param([Parameter(Mandatory)][string]$Name)
    $persistedTasks = @(
        'Network setup',
        'AD DS promotion',
        'Exchange AD prep',
        'Exchange install',
        'EOMT mitigation',
        'Mitigation status',
        'XSS email test',
        'Evidence export',
        'Preflight check',
        'Lab cleanup'
    )
    if ($Name -in $persistedTasks) { Update-RunCheckpoint -StepName $Name | Out-Null }
}

function Get-UiValue {
    param([string]$Field)
    if ($script:Ui.ContainsKey($Field) -and $script:Ui[$Field]) { return $script:Ui[$Field].Text }
    return $null
}

function Get-CurrentRunInputs {
    $payload = if ($script:Ui.ContainsKey('Payload') -and $script:Ui.Payload) { [string]$script:Ui.Payload.SelectedItem } else { $null }
    return [ordered]@{
        StaticIp = Get-UiValue 'Ip'
        SubnetMask = Get-UiValue 'Mask'
        Domain = Get-UiValue 'Domain'
        ExchangeIsoPath = Get-UiValue 'ExchangePath'
        EomtSourceUrl = Get-UiValue 'Eomt'
        SmtpTarget = Get-UiValue 'Smtp'
        Attacker = Get-UiValue 'Attacker'
        Victim = Get-UiValue 'Victim'
        Payload = $payload
        OwaUrl = Get-UiValue 'OwaUrl'
        ProfilePath = Get-UiValue 'ProfilePath'
    }
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
    $result = Invoke-PreflightReadiness -Report $Report
    if ($result.BlockingCount -gt 0) {
        throw "Preflight validation failed with $($result.BlockingCount) blocking issue(s)."
    }
    return $result
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
        @{ Name = 'Xss'; Field = 'XssLog' },
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
        $zipPath = if ($Data.OutputPath) { $Data.OutputPath } else { Join-Path $env:TEMP "ExchangeLabManager-Evidence-Bundle-$timestamp-$suffix.zip" }
        if (Test-Path -LiteralPath $zipPath -PathType Leaf) { Remove-Item -LiteralPath $zipPath -Force }
        Add-Type -AssemblyName System.IO.Compression.FileSystem
        [System.IO.Compression.ZipFile]::CreateFromDirectory($evidenceDir, $zipPath)
        Update-LabCheckpoint -Milestone 'EvidenceExported' -Status 'Complete' -Notes "Evidence exported to $zipPath" -Report $Report | Out-Null
        & $Report "Evidence bundle created: $zipPath" 'Good'
        & $Report "All evidence exported to: $evidenceDir (and bundled as ZIP)" 'Good'
        return @{ Directory = $evidenceDir; ZipBundle = $zipPath }
    } catch {
        & $Report "ZIP bundle creation skipped: $_" 'Warn'
        & $Report "Evidence files are available in: $evidenceDir" 'Good'
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
    param([hashtable]$Data, [scriptblock]$Report)
    Assert-Admin
    $ip = $Data.Ip.Trim()
    $mask = $Data.Mask.Trim()
    [void][System.Net.IPAddress]::Parse($ip)
    $prefix = Convert-MaskToPrefix $mask
    $gateway = Get-GatewayFromIp $ip

    $adapter = Get-NetAdapter -ErrorAction Stop |
        Where-Object { $_.Status -eq 'Up' -and $_.HardwareInterface } |
        Sort-Object Name |
        Select-Object -First 1
    if (-not $adapter) { throw 'No active physical network adapter was found.' }

    & $Report "Selected adapter '$($adapter.Name)'." 'Info'
    $current = Get-NetIPAddress -InterfaceAlias $adapter.Name -AddressFamily IPv4 -ErrorAction SilentlyContinue |
        Where-Object { $_.IPAddress -notlike '169.254.*' }
    foreach ($addr in $current) {
        if ($addr.IPAddress -ne $ip) {
            & $Report "Removing previous IPv4 address $($addr.IPAddress)." 'Warn'
            Remove-NetIPAddress -InterfaceAlias $adapter.Name -IPAddress $addr.IPAddress -Confirm:$false -ErrorAction SilentlyContinue
        }
    }

    $existing = Get-NetIPAddress -InterfaceAlias $adapter.Name -IPAddress $ip -AddressFamily IPv4 -ErrorAction SilentlyContinue
    if ($existing) {
        Set-NetIPAddress -InterfaceAlias $adapter.Name -IPAddress $ip -PrefixLength $prefix -ErrorAction Stop
    } else {
        New-NetIPAddress -InterfaceAlias $adapter.Name -IPAddress $ip -PrefixLength $prefix -DefaultGateway $gateway -AddressFamily IPv4 -ErrorAction Stop | Out-Null
    }
    Set-DnsClientServerAddress -InterfaceAlias $adapter.Name -ServerAddresses '127.0.0.1' -ErrorAction Stop
    & $Report "Network applied: $ip/$prefix, gateway $gateway, DNS 127.0.0.1." 'Good'
}

function Install-AdAndPromote {
    param([hashtable]$Data, [scriptblock]$Report)
    Assert-Admin
    $domain = $Data.Domain.Trim()
    if ($domain -notmatch '^[a-zA-Z0-9][a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$') { throw "Invalid domain name '$domain'." }
    & $Report 'Installing Active Directory Domain Services...' 'Info'
    Install-WindowsFeature -Name AD-Domain-Services -IncludeManagementTools -ErrorAction Stop | Out-Null
    Import-Module ADDSDeployment -ErrorAction Stop
    $safeMode = ConvertTo-SecureString 'P@ssw0rd!LabOnly' -AsPlainText -Force
    & $Report "Promoting server to forest '$domain'." 'Info'
    Install-ADDSForest -DomainName $domain -SafeModeAdministratorPassword $safeMode -InstallDns -CreateDnsDelegation:$false -Force -NoRebootOnCompletion -ErrorAction Stop
    & $Report 'Promotion finished. Reboot the server before Exchange setup.' 'Warn'
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
    param([hashtable]$Data, [scriptblock]$Report)
    Assert-Admin
    $source = $Data.Source.Trim()
    if (-not $source) { throw 'Enter an EOMT URL or local script path.' }
    $cache = Join-Path $env:TEMP 'ExchangeLabManager'
    if (-not (Test-Path -LiteralPath $cache)) { New-Item -Path $cache -ItemType Directory -Force | Out-Null }
    $local = Join-Path $cache 'EOMT.ps1'

    if ($source -match '^https?://') {
        & $Report "Downloading EOMT from $source." 'Info'
        Invoke-WebRequest -Uri $source -OutFile $local -UseBasicParsing -ErrorAction Stop
    } else {
        if (-not (Test-Path -LiteralPath $source)) { throw "EOMT source path not found: $source" }
        $local = (Resolve-Path -LiteralPath $source).Path
    }

    $powershell = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
    Invoke-LoggedProcess -FilePath $powershell -Arguments @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $local) -WorkingDirectory (Split-Path -Parent $local) -Report $Report
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

function Send-XssMail {
    param([hashtable]$Data, [scriptblock]$Report)
    foreach ($key in 'Sender','Recipient','Smtp') {
        if ([string]::IsNullOrWhiteSpace($Data[$key])) { throw "$key is required." }
    }
    $body = @"
<html>
<body>
    <h2>OWA XSS Lab Control Test</h2>
    <p>This message contains a benign validation payload for an isolated Exchange sandbox.</p>
    $($Data.Payload)
</body>
</html>
"@
    & $Report "Sending lab message from $($Data.Sender) to $($Data.Recipient) through $($Data.Smtp)." 'Info'
    Send-MailMessage -From $Data.Sender -To $Data.Recipient -Subject 'OWA XSS Lab Validation' -Body $body -BodyAsHtml -SmtpServer $Data.Smtp -ErrorAction Stop
    & $Report 'SMTP accepted the test message. Inspect OWA and browser console CSP behavior.' 'Good'
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
    $script:Ui.ProfilePill = New-Pill 'Profile ready' 22 214 260
    $script:Ui.CheckpointPill = New-Pill 'Checkpoint pending' 306 214 300
    $script:Ui.ProfileProgress = New-Progress 630 224 260
    $panel.Controls.AddRange(@($profileBrowse, $loadProfileBtn, $saveProfileBtn, $manifestBtn, $preflightBtn, $fullEvidenceBtn, $saveCheckpointBtn, $loadCheckpointBtn, $resetCheckpointBtn, $previewCleanupBtn, $cleanTempBtn, $script:Ui.ProfilePill, $script:Ui.CheckpointPill, $script:Ui.ProfileProgress))
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

function Build-XssTab {
    param([System.Windows.Forms.TabPage]$Tab)
    $panel = New-Section $Tab 'Automated XSS Test'
    $panel.Controls.Add((New-Label 'Attacker Email' 22 64))
    $script:Ui.Attacker = New-Input 190 62 320; $script:Ui.Attacker.Text = 'attacker@mylab.local'; $panel.Controls.Add($script:Ui.Attacker)
    $panel.Controls.Add((New-Label 'Victim Email' 22 104))
    $script:Ui.Victim = New-Input 190 102 320; $script:Ui.Victim.Text = 'victim@mylab.local'; $panel.Controls.Add($script:Ui.Victim)
    $panel.Controls.Add((New-Label 'Target SMTP Server IP' 22 144))
    $script:Ui.Smtp = New-Input 190 142 320; $script:Ui.Smtp.Text = '192.168.100.10'; $panel.Controls.Add($script:Ui.Smtp)
    $panel.Controls.Add((New-Label 'Harmless Payload' 22 184))
    $script:Ui.Payload = New-Object System.Windows.Forms.ComboBox
    $script:Ui.Payload.Location = New-Object System.Drawing.Point(190, 182)
    $script:Ui.Payload.Size = New-Object System.Drawing.Size(630, 28)
    $script:Ui.Payload.DropDownStyle = 'DropDownList'
    $script:Ui.Payload.BackColor = $script:Theme.Field
    $script:Ui.Payload.ForeColor = $script:Theme.Text
    $script:Ui.Payload.Font = New-Object System.Drawing.Font('Segoe UI', 9)
    $script:Ui.Payload.Items.AddRange(@(
        '<img src="x" onerror="alert(''XSS_Test_Triggered'')" />',
        '<svg onload="alert(''Lab_Control_Payload'')"></svg>',
        '<a href="javascript:alert(''Link_Control_Payload'')">Lab validation link</a>'
    ))
    $script:Ui.Payload.SelectedIndex = 0
    $panel.Controls.Add($script:Ui.Payload)
    $fire = New-Button 'Fire Test Email' 22 234 210
    $script:Ui.XssPill = New-Pill 'Test idle' 260 238 180
    $script:Ui.XssProgress = New-Progress 464 248 260
    $panel.Controls.AddRange(@($fire, $script:Ui.XssPill, $script:Ui.XssProgress))
    $script:Ui.XssLog = New-Log 22 290 1070 320; $panel.Controls.Add($script:Ui.XssLog)
    $fire.Add_Click({
        $data = @{
            Sender = $script:Ui.Attacker.Text.Trim()
            Recipient = $script:Ui.Victim.Text.Trim()
            Smtp = $script:Ui.Smtp.Text.Trim()
            Payload = [string]$script:Ui.Payload.SelectedItem
        }
        Start-LabTask 'XSS email test' $script:Ui.XssLog $script:Ui.XssPill $script:Ui.XssProgress { param($Data, $Report) Send-XssMail $Data $Report } $data 'Sending benign lab XSS validation email...' 'Lab XSS validation message submitted to SMTP.' 'XssMailSent'
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
                Xss = $script:Ui.XssLog
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
    $tabNames = 'Lab Control & Evidence','System & Network Setup','Exchange Prep & Install','Mitigation & EOMT','Automated XSS Test','CVE-2026-42897 Validation'
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
    Build-XssTab $tabPages[4]
    Build-CveValidationTab $tabPages[5]

    Apply-LabCheckpoint

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
