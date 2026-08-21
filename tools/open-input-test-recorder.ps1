param(
    [ValidateRange(1, 1000)]
    [int]$MinimumCyclesPerHost = 20,
    [string]$RecordDirectory = '',
    [string]$ResumeRecordPath = '',
    [switch]$SelfTest
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

function New-HostStats {
    param([string]$Id, [string]$Name, [string]$Architecture)

    [pscustomobject]@{
        Id = $Id; Name = $Name; Architecture = $Architecture
        First = 0; Middle = 0; Final = 0; Failures = 0
        CompletionAnnounced = $false
    }
}

function New-TestSession {
    param([int]$Required, [datetime]$Now = (Get-Date))

    [pscustomobject]@{
        SessionId  = [guid]::NewGuid().ToString('N')
        Required   = $Required
        StartedAt  = $Now
        RecordPath = ''
        Hosts      = [ordered]@{
            notepad = New-HostStats -Id 'notepad' -Name 'x64 Notepad' -Architecture 'x64'
            codex   = New-HostStats -Id 'codex' -Name 'Codex IDE' -Architecture 'x64'
            charmap = New-HostStats -Id 'charmap' -Name 'x86 SysWOW64 charmap' -Architecture 'x86'
        }
        Events     = [Collections.Generic.List[object]]::new()
    }
}

function Get-CompletedCycles {
    param([Parameter(Mandatory)]$HostStats)
    return [math]::Min($HostStats.First, [math]::Min($HostStats.Middle, $HostStats.Final))
}

function Add-SegmentResult {
    param(
        [Parameter(Mandatory)]$Session,
        [ValidateSet('notepad', 'codex', 'charmap')][string]$HostId,
        [ValidateSet('First', 'Middle', 'Final', 'Failure')][string]$Position,
        $Evidence = $null,
        [datetime]$Now = (Get-Date)
    )

    $hostStats = $Session.Hosts[$HostId]
    if ($Position -eq 'Failure') { $hostStats.Failures++ } else { $hostStats.$Position++ }
    $event = [pscustomobject]@{
        EventId = [guid]::NewGuid().ToString('N'); Timestamp = $Now
        HostId = $HostId; Position = $Position; Evidence = $Evidence
    }
    $Session.Events.Add($event)
    return $event
}

function Undo-LastSegmentResult {
    param([Parameter(Mandatory)]$Session)

    if ($Session.Events.Count -eq 0) { return $null }
    $index = $Session.Events.Count - 1
    $event = $Session.Events[$index]
    $Session.Events.RemoveAt($index)
    $hostStats = $Session.Hosts[$event.HostId]
    if ($event.Position -eq 'Failure') {
        $hostStats.Failures = [math]::Max(0, $hostStats.Failures - 1)
    } else {
        $hostStats.($event.Position) = [math]::Max(0, $hostStats.($event.Position) - 1)
    }
    if ((Get-CompletedCycles $hostStats) -lt $Session.Required) { $hostStats.CompletionAnnounced = $false }
    return $event
}

function Get-HostOutcome {
    param($HostStats, [int]$Required)
    if ($HostStats.Failures -gt 0) { return 'fail' }
    if ((Get-CompletedCycles $HostStats) -ge $Required) { return 'pass' }
    return 'not-recorded'
}

function Resolve-HostIdentity {
    param(
        [string]$ProcessName,
        [AllowNull()][string]$Executable,
        [string]$Architecture,
        [AllowEmptyString()][string]$WindowTitle = ''
    )

    $hostId = $null
    $reason = $null
    if ($ProcessName -ieq 'notepad') {
        if ($Architecture -eq 'x64') { $hostId = 'notepad' } else { $reason = "Notepad 架构为 $Architecture，要求 x64" }
    } elseif ($ProcessName -ieq 'charmap') {
        if ($Architecture -eq 'x86' -and $Executable -match '(?i)\\SysWOW64\\charmap\.exe$') { $hostId = 'charmap' }
        else { $reason = "charmap 必须是 C:\Windows\SysWOW64\charmap.exe；当前为 $Executable ($Architecture)" }
    } elseif ($ProcessName -match '(?i)^(codex|chatgpt)$' -or $WindowTitle -match '(?i)Codex') {
        if ($Architecture -eq 'x64') { $hostId = 'codex' } else { $reason = "Codex IDE 架构为 $Architecture，要求 x64" }
    } else {
        $reason = "前台窗口不属于三宿主：$ProcessName / $WindowTitle"
    }
    return [pscustomobject]@{ Supported = ($null -ne $hostId); HostId = $hostId; Reason = $reason }
}

function Get-TestSummary {
    param([Parameter(Mandatory)]$Session)
    $lines = foreach ($hostId in @('notepad', 'codex', 'charmap')) {
        $hostStats = $Session.Hosts[$hostId]
        "$($hostStats.Name)：首 $($hostStats.First)，中 $($hostStats.Middle)，末 $($hostStats.Final)，完整轮次 $(Get-CompletedCycles $hostStats)，失败 $($hostStats.Failures)"
    }
    return "三宿主分段验收（每宿主要求 $($Session.Required) 轮）`r`n" + ($lines -join "`r`n")
}

function Get-PositionRecordedStatus {
    param($HostStats, [string]$PositionName, [int]$Required)
    return "$($HostStats.Name)：${PositionName}正确已记录；完整轮次 $(Get-CompletedCycles $HostStats)/$Required。"
}

function Import-TestSession {
    param([Parameter(Mandatory)][string]$Path)

    $fullPath = [IO.Path]::GetFullPath($Path)
    if (-not (Test-Path -LiteralPath $fullPath -PathType Leaf)) { throw "续接记录不存在：$fullPath" }
    $records = @(Get-Content -LiteralPath $fullPath | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | ForEach-Object { $_ | ConvertFrom-Json })
    if ($records.Count -eq 0 -or [int]$records[0].schema_version -ne 2) { throw "续接记录不是 schema 2：$fullPath" }
    $session = New-TestSession -Required ([int]$records[0].minimum_cycles_per_host) -Now ([datetime]$records[0].timestamp)
    $session.SessionId = [string]$records[0].session_id
    $session.RecordPath = $fullPath
    foreach ($record in $records) {
        if ($record.event -eq 'segment_result') {
            $position = [Globalization.CultureInfo]::InvariantCulture.TextInfo.ToTitleCase([string]$record.position)
            [void](Add-SegmentResult -Session $session -HostId ([string]$record.host_id) -Position $position -Evidence $record.foreground -Now ([datetime]$record.timestamp))
            $session.Events[$session.Events.Count - 1].EventId = [string]$record.segment_event_id
        } elseif ($record.event -eq 'undo') {
            [void](Undo-LastSegmentResult -Session $session)
        }
    }
    foreach ($hostId in @('notepad', 'codex', 'charmap')) {
        $hostStats = $session.Hosts[$hostId]
        $hostStats.CompletionAnnounced = (Get-CompletedCycles $hostStats) -ge $session.Required
    }
    return $session
}

function Get-CaptureCommand {
    param([Parameter(Mandatory)]$Session)
    if (-not [string]::IsNullOrWhiteSpace([string]$Session.RecordPath)) {
        $escapedRecordPath = ([string]$Session.RecordPath).Replace("'", "''")
        return @(
            '.\tools\capture-sentence-segment-evidence.ps1 `',
            "  -RecorderRecordPath '$escapedRecordPath' ``",
            '  -RequireComplete'
        ) -join "`r`n"
    }
    $notepad = $Session.Hosts.notepad; $codex = $Session.Hosts.codex; $charmap = $Session.Hosts.charmap
    $lines = @(
        '.\tools\capture-sentence-segment-evidence.ps1 `',
        "  -MinimumCyclesPerHost $($Session.Required) ``",
        "  -MinimumCorrelatedRpcTransactions $($Session.Required * 9) ``",
        "  -NotepadOutcome $(Get-HostOutcome $notepad $Session.Required) ``",
        "  -NotepadFirstSegmentSwitches $($notepad.First) ``",
        "  -NotepadMiddleSegmentSwitches $($notepad.Middle) ``",
        "  -NotepadFinalSegmentSwitches $($notepad.Final) ``",
        "  -CodexIdeOutcome $(Get-HostOutcome $codex $Session.Required) ``",
        "  -CodexIdeFirstSegmentSwitches $($codex.First) ``",
        "  -CodexIdeMiddleSegmentSwitches $($codex.Middle) ``",
        "  -CodexIdeFinalSegmentSwitches $($codex.Final) ``",
        "  -SysWow64CharmapOutcome $(Get-HostOutcome $charmap $Session.Required) ``",
        "  -SysWow64CharmapFirstSegmentSwitches $($charmap.First) ``",
        "  -SysWow64CharmapMiddleSegmentSwitches $($charmap.Middle) ``",
        "  -SysWow64CharmapFinalSegmentSwitches $($charmap.Final) ``",
        '  -RequireLongSession `',
        '  -RequireComplete'
    )
    return $lines -join "`r`n"
}

function Invoke-SelfTest {
    $session = New-TestSession -Required 2 -Now ([datetime]'2026-08-21T10:00:00')
    foreach ($hostId in @('notepad', 'codex', 'charmap')) {
        foreach ($position in @('First', 'Middle', 'Final')) {
            [void](Add-SegmentResult -Session $session -HostId $hostId -Position $position)
            [void](Add-SegmentResult -Session $session -HostId $hostId -Position $position)
        }
    }
    foreach ($hostId in @('notepad', 'codex', 'charmap')) {
        if ((Get-CompletedCycles $session.Hosts[$hostId]) -ne 2 -or (Get-HostOutcome $session.Hosts[$hostId] 2) -ne 'pass') {
            throw "Per-host cycle counting failed: $hostId"
        }
    }
    [void](Add-SegmentResult -Session $session -HostId 'codex' -Position Failure)
    if ((Get-HostOutcome $session.Hosts.codex 2) -ne 'fail') { throw 'Failure outcome failed.' }
    $undone = Undo-LastSegmentResult -Session $session
    if ($undone.Position -ne 'Failure' -or $session.Hosts.codex.Failures -ne 0) { throw 'Undo failed.' }
    $command = Get-CaptureCommand -Session $session
    foreach ($fragment in @('-NotepadFirstSegmentSwitches 2', '-CodexIdeMiddleSegmentSwitches 2', '-SysWow64CharmapFinalSegmentSwitches 2', '-MinimumCorrelatedRpcTransactions 18')) {
        if (-not $command.Contains($fragment)) { throw "Capture command is missing: $fragment" }
    }
    $session.RecordPath = "C:\evidence\three-host-'quoted'.jsonl"
    $recordCommand = Get-CaptureCommand -Session $session
    if (-not $recordCommand.Contains("-RecorderRecordPath 'C:\evidence\three-host-''quoted''.jsonl'") -or
        -not $recordCommand.Contains('-RequireComplete')) {
        throw 'Recorder-backed capture command is invalid.'
    }
    $identities = @(
        (Resolve-HostIdentity 'notepad' 'C:\Program Files\WindowsApps\Notepad\Notepad.exe' 'x64'),
        (Resolve-HostIdentity 'ChatGPT' 'C:\Program Files\WindowsApps\ChatGPT\ChatGPT.exe' 'x64' 'ChatGPT'),
        (Resolve-HostIdentity 'charmap' 'C:\Windows\SysWOW64\charmap.exe' 'x86')
    )
    if (@($identities | Where-Object { -not $_.Supported }).Count -ne 0 -or
        (Resolve-HostIdentity 'charmap' 'C:\Windows\System32\charmap.exe' 'x64').Supported -or
        (Resolve-HostIdentity 'powershell' 'C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe' 'x64' 'Yime 三宿主测试记录').Supported) {
        throw 'Three-host identity classification failed.'
    }
    if ((Get-PositionRecordedStatus $session.Hosts.notepad '首段' 2) -notmatch '首段正确已记录') {
        throw 'Position status interpolation failed.'
    }
    Write-Host 'Three-host input test recorder self-test passed.'
}

if ($SelfTest) { Invoke-SelfTest; exit 0 }

if ([string]::IsNullOrWhiteSpace($RecordDirectory)) {
    $localData = if ([string]::IsNullOrWhiteSpace($env:LOCALAPPDATA)) { [Environment]::GetFolderPath([Environment+SpecialFolder]::LocalApplicationData) } else { $env:LOCALAPPDATA }
    $RecordDirectory = Join-Path $localData 'PIME\Yime\ThreeHostTestRecords'
}
$RecordDirectory = [IO.Path]::GetFullPath($RecordDirectory)
[IO.Directory]::CreateDirectory($RecordDirectory) | Out-Null

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
Add-Type -ReferencedAssemblies @('System.Windows.Forms.dll', 'System.dll') -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
using System.Text;
using System.Windows.Forms;

public sealed class YimeHotKeyEventArgs : EventArgs {
    public int Id { get; private set; }
    public YimeHotKeyEventArgs(int id) { Id = id; }
}
public sealed class YimeHotKeyForm : Form {
    public event EventHandler<YimeHotKeyEventArgs> HotKeyPressed;
    public string LastDispatchError { get; private set; }
    protected override void WndProc(ref Message message) {
        if (message.Msg == 0x0312) {
            EventHandler<YimeHotKeyEventArgs> handler = HotKeyPressed;
            try {
                if (handler != null) handler(this, new YimeHotKeyEventArgs(message.WParam.ToInt32()));
            } catch (Exception error) {
                LastDispatchError = error.ToString();
                System.Media.SystemSounds.Hand.Play();
            }
            return;
        }
        base.WndProc(ref message);
    }
}
public static class YimeThreeHostNative {
    [DllImport("user32.dll", SetLastError=true)] public static extern bool RegisterHotKey(IntPtr hwnd, int id, uint modifiers, uint virtualKey);
    [DllImport("user32.dll", SetLastError=true)] public static extern bool UnregisterHotKey(IntPtr hwnd, int id);
    [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
    [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr hwnd, out uint processId);
    [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern int GetWindowText(IntPtr hwnd, StringBuilder text, int maximum);
    [DllImport("kernel32.dll", SetLastError=true)] public static extern bool IsWow64Process(IntPtr process, out bool wow64);
}
'@

function Get-ForegroundHost {
    $hwnd = [YimeThreeHostNative]::GetForegroundWindow()
    [uint32]$processId = 0
    [void][YimeThreeHostNative]::GetWindowThreadProcessId($hwnd, [ref]$processId)
    $titleBuilder = New-Object Text.StringBuilder 1024
    [void][YimeThreeHostNative]::GetWindowText($hwnd, $titleBuilder, $titleBuilder.Capacity)
    $title = $titleBuilder.ToString()
    try {
        $process = [Diagnostics.Process]::GetProcessById([int]$processId)
        $processName = $process.ProcessName
        $path = $null
        try { $path = $process.MainModule.FileName } catch {}
        $wow64 = $false; $architecture = 'unknown'
        if ([Environment]::Is64BitOperatingSystem -and [YimeThreeHostNative]::IsWow64Process($process.Handle, [ref]$wow64)) {
            $architecture = if ($wow64) { 'x86' } else { 'x64' }
        } elseif (-not [Environment]::Is64BitOperatingSystem) { $architecture = 'x86' }
    } catch {
        return [pscustomobject]@{
            Supported = $false; Reason = "无法读取前台宿主进程：$($_.Exception.Message)"; HostId = $null
            ProcessId = [int]$processId; ProcessName = $null; Executable = $null; Architecture = 'unknown'
            WindowTitle = $title; WindowHandle = ('0x{0:X}' -f $hwnd.ToInt64())
        }
    }

    $identity = Resolve-HostIdentity -ProcessName $processName -Executable $path -Architecture $architecture -WindowTitle $title

    return [pscustomobject]@{
        Supported = $identity.Supported; Reason = $identity.Reason; HostId = $identity.HostId
        ProcessId = [int]$processId; ProcessName = $processName; Executable = $path
        Architecture = $architecture; WindowTitle = $title; WindowHandle = ('0x{0:X}' -f $hwnd.ToInt64())
    }
}

[Windows.Forms.Application]::EnableVisualStyles()
$form = New-Object YimeHotKeyForm
$form.Text = 'Yime 三宿主测试记录'; $form.StartPosition = 'CenterScreen'
$form.ClientSize = New-Object Drawing.Size(900, 580); $form.MinimumSize = New-Object Drawing.Size(780, 560)
$form.Font = New-Object Drawing.Font('Microsoft YaHei UI', 10); $form.AutoScaleMode = [Windows.Forms.AutoScaleMode]::Dpi; $form.TopMost = $true

$titleLabel = New-Object Windows.Forms.Label
$titleLabel.Text = '三宿主长会话旁路计数器'; $titleLabel.Font = New-Object Drawing.Font('Microsoft YaHei UI', 16, [Drawing.FontStyle]::Bold)
$titleLabel.AutoSize = $true; $titleLabel.Location = New-Object Drawing.Point(24, 16); $form.Controls.Add($titleLabel)
$descriptionLabel = New-Object Windows.Forms.Label
$descriptionLabel.Text = '本窗口不接收测试输入。请把焦点留在被测宿主，完成一次分段切换后按对应全局快捷键。'
$descriptionLabel.AutoSize = $true; $descriptionLabel.Location = New-Object Drawing.Point(27, 55); $form.Controls.Add($descriptionLabel)
$hotKeyLabel = New-Object Windows.Forms.Label
$hotKeyLabel.Text = '推荐：Ctrl+Alt+J 首段正确    Ctrl+Alt+K 中段正确    Ctrl+Alt+L 末段正确    Ctrl+Alt+X 失败    Ctrl+Alt+Z 撤销'
$hotKeyLabel.Font = New-Object Drawing.Font('Microsoft YaHei UI', 10, [Drawing.FontStyle]::Bold); $hotKeyLabel.AutoSize = $true
$hotKeyLabel.Location = New-Object Drawing.Point(27, 83); $form.Controls.Add($hotKeyLabel)
$alternateHotKeyLabel = New-Object Windows.Forms.Label
$alternateHotKeyLabel.Text = '备用：Ctrl+Alt+F6 / F7 / F8 / F9 / F10（部分笔记本需要同时按 Fn）'
$alternateHotKeyLabel.AutoSize = $true; $alternateHotKeyLabel.Location = New-Object Drawing.Point(27, 108); $form.Controls.Add($alternateHotKeyLabel)
$scenarioLabel = New-Object Windows.Forms.Label
$scenarioLabel.Text = "流程：同一宿主会话依次完成首段、中段、末段；每宿主至少 $MinimumCyclesPerHost 轮。计数时自动核对前台进程与 x86/x64 架构。"
$scenarioLabel.AutoSize = $true; $scenarioLabel.Location = New-Object Drawing.Point(27, 133); $form.Controls.Add($scenarioLabel)

$table = New-Object Windows.Forms.TableLayoutPanel
$table.Location = New-Object Drawing.Point(30, 162); $table.Size = New-Object Drawing.Size(840, 243); $table.Anchor = 'Top, Left, Right'
$table.ColumnCount = 5; $table.RowCount = 6; $table.CellBorderStyle = [Windows.Forms.TableLayoutPanelCellBorderStyle]::Single
foreach ($percent in @(19, 25, 22, 25, 9)) { $table.ColumnStyles.Add((New-Object Windows.Forms.ColumnStyle([Windows.Forms.SizeType]::Percent, $percent))) }
$form.Controls.Add($table)
$cellLabels = @{}
function Add-TableCell {
    param([string]$Key, [string]$Text, [int]$Column, [int]$Row, [switch]$Bold)
    $label = New-Object Windows.Forms.Label
    $label.Text = $Text; $label.Dock = 'Fill'; $label.TextAlign = [Drawing.ContentAlignment]::MiddleCenter
    if ($Bold) { $label.Font = New-Object Drawing.Font('Microsoft YaHei UI', 10, [Drawing.FontStyle]::Bold) }
    $table.Controls.Add($label, $Column, $Row)
    if ($Key) { $script:cellLabels[$Key] = $label }
}
Add-TableCell '' '统计项' 0 0 -Bold; Add-TableCell '' 'x64 Notepad' 1 0 -Bold; Add-TableCell '' 'Codex IDE' 2 0 -Bold
Add-TableCell '' 'x86 SysWOW64 charmap' 3 0 -Bold; Add-TableCell '' '门槛' 4 0 -Bold
$rowDefinitions = @(
    @{ Key = 'First'; Label = '首段正确' }, @{ Key = 'Middle'; Label = '中段正确' },
    @{ Key = 'Final'; Label = '末段正确' }, @{ Key = 'Cycles'; Label = '完整轮次' }, @{ Key = 'Failures'; Label = '失败记录' }
)
for ($row = 0; $row -lt $rowDefinitions.Count; $row++) {
    $definition = $rowDefinitions[$row]
    Add-TableCell '' $definition.Label 0 ($row + 1) -Bold
    Add-TableCell "notepad-$($definition.Key)" '0' 1 ($row + 1); Add-TableCell "codex-$($definition.Key)" '0' 2 ($row + 1)
    Add-TableCell "charmap-$($definition.Key)" '0' 3 ($row + 1)
    Add-TableCell '' $(if ($definition.Key -eq 'Failures') { '0' } else { "$MinimumCyclesPerHost" }) 4 ($row + 1)
}

$statusLabel = New-Object Windows.Forms.Label
$statusLabel.AutoSize = $false; $statusLabel.TextAlign = [Drawing.ContentAlignment]::MiddleCenter
$statusLabel.Location = New-Object Drawing.Point(30, 417); $statusLabel.Size = New-Object Drawing.Size(840, 46); $statusLabel.Anchor = 'Top, Left, Right'; $form.Controls.Add($statusLabel)

function Add-ActionButton([string]$Text, [int]$X, [int]$Width) {
    $button = New-Object Windows.Forms.Button
    $button.Text = $Text; $button.Location = New-Object Drawing.Point($X, 478); $button.Size = New-Object Drawing.Size($Width, 36)
    $button.Anchor = 'Bottom, Left'; $form.Controls.Add($button); return $button
}
$newButton = Add-ActionButton '开始新记录' 30 118; $undoButton = Add-ActionButton '撤销上一笔' 158 118
$summaryButton = Add-ActionButton '复制统计摘要' 286 126; $commandButton = Add-ActionButton '复制证据命令' 422 126
$openButton = Add-ActionButton '打开记录目录' 558 126
$topMostCheck = New-Object Windows.Forms.CheckBox
$topMostCheck.Text = '窗口置顶'; $topMostCheck.Checked = $true; $topMostCheck.AutoSize = $true
$topMostCheck.Location = New-Object Drawing.Point(710, 486); $topMostCheck.Anchor = 'Bottom, Right'; $form.Controls.Add($topMostCheck)
$pathLabel = New-Object Windows.Forms.Label
$pathLabel.AutoEllipsis = $true; $pathLabel.Location = New-Object Drawing.Point(30, 530); $pathLabel.Size = New-Object Drawing.Size(840, 28)
$pathLabel.Anchor = 'Bottom, Left, Right'; $form.Controls.Add($pathLabel)

$session = $null; $registeredHotKeyIds = [Collections.Generic.List[int]]::new()

function Write-RecordEvent {
    param([string]$EventType, $SegmentEvent = $null, $Foreground = $null)
    $record = [ordered]@{ schema_version = 2; event = $EventType; session_id = $session.SessionId; timestamp = (Get-Date).ToString('o'); minimum_cycles_per_host = $session.Required }
    if ($null -ne $SegmentEvent) { $record.segment_event_id = $SegmentEvent.EventId; $record.host_id = $SegmentEvent.HostId; $record.position = $SegmentEvent.Position.ToLowerInvariant() }
    if ($null -ne $Foreground) {
        $record.foreground = [ordered]@{ process_id = $Foreground.ProcessId; process_name = $Foreground.ProcessName; executable = $Foreground.Executable; architecture = $Foreground.Architecture; window_title = $Foreground.WindowTitle; window_handle = $Foreground.WindowHandle; rejection_reason = $Foreground.Reason }
    }
    $record.host_counts = [ordered]@{}
    foreach ($hostId in @('notepad', 'codex', 'charmap')) {
        $hostStats = $session.Hosts[$hostId]
        $record.host_counts[$hostId] = [ordered]@{ first = $hostStats.First; middle = $hostStats.Middle; final = $hostStats.Final; completed_cycles = (Get-CompletedCycles $hostStats); failures = $hostStats.Failures }
    }
    try { ($record | ConvertTo-Json -Compress -Depth 6) | Add-Content -LiteralPath $session.RecordPath -Encoding utf8 }
    catch { $statusLabel.ForeColor = [Drawing.Color]::DarkRed; $statusLabel.Text = "记录写入失败：$($_.Exception.Message)" }
}

function Update-Display {
    foreach ($hostId in @('notepad', 'codex', 'charmap')) {
        $hostStats = $session.Hosts[$hostId]
        $cellLabels["$hostId-First"].Text = "$($hostStats.First)"; $cellLabels["$hostId-Middle"].Text = "$($hostStats.Middle)"
        $cellLabels["$hostId-Final"].Text = "$($hostStats.Final)"; $cellLabels["$hostId-Cycles"].Text = "$(Get-CompletedCycles $hostStats)"
        $cellLabels["$hostId-Failures"].Text = "$($hostStats.Failures)"
        $passed = (Get-HostOutcome $hostStats $session.Required) -eq 'pass'
        $color = if ($passed) { [Drawing.Color]::DarkGreen } elseif ($hostStats.Failures -gt 0) { [Drawing.Color]::DarkRed } else { [Drawing.Color]::Black }
        foreach ($key in @('First', 'Middle', 'Final', 'Cycles', 'Failures')) { $cellLabels["$hostId-$key"].ForeColor = $color }
    }
    $pathLabel.Text = "记录文件：$($session.RecordPath)"
}

function Start-NewSession {
    if ($null -ne $session) { Write-RecordEvent -EventType 'session_ended' }
    $script:session = New-TestSession -Required $MinimumCyclesPerHost
    $stamp = $session.StartedAt.ToString('yyyyMMdd-HHmmss')
    $session.RecordPath = Join-Path $RecordDirectory ("three-host-$stamp-$($session.SessionId.Substring(0, 8)).jsonl")
    Write-RecordEvent -EventType 'session_started'; Update-Display
    $statusLabel.ForeColor = [Drawing.Color]::DimGray; $statusLabel.Text = '新记录已开始。请切换到第一个被测宿主；本窗口不会接收测试文字。'
}

function Record-Position {
    param([ValidateSet('First', 'Middle', 'Final', 'Failure')][string]$Position)
    $foreground = Get-ForegroundHost
    if (-not $foreground.Supported) {
        Write-RecordEvent -EventType 'hotkey_rejected' -Foreground $foreground
        $statusLabel.ForeColor = [Drawing.Color]::DarkRed; $statusLabel.Text = "未计数：$($foreground.Reason)"
        [System.Media.SystemSounds]::Exclamation.Play(); return
    }
    $event = Add-SegmentResult -Session $session -HostId $foreground.HostId -Position $Position -Evidence $foreground
    Write-RecordEvent -EventType 'segment_result' -SegmentEvent $event -Foreground $foreground; Update-Display
    $hostStats = $session.Hosts[$foreground.HostId]; $positionName = @{ First = '首段'; Middle = '中段'; Final = '末段'; Failure = '失败' }[$Position]
    if ($Position -eq 'Failure') { $statusLabel.ForeColor = [Drawing.Color]::DarkRed; $statusLabel.Text = "$($hostStats.Name)：已记录一次失败；本次验收不会被标为 pass。"; [System.Media.SystemSounds]::Exclamation.Play(); return }
    $statusLabel.ForeColor = [Drawing.Color]::DarkGreen; $statusLabel.Text = Get-PositionRecordedStatus $hostStats $positionName $session.Required
    if (-not $hostStats.CompletionAnnounced -and (Get-CompletedCycles $hostStats) -ge $session.Required) {
        $hostStats.CompletionAnnounced = $true; $statusLabel.Text = "$($hostStats.Name) 已达到 $($session.Required) 个完整首/中/末循环。"
        [System.Media.SystemSounds]::Asterisk.Play(); Write-RecordEvent -EventType 'host_target_reached' -SegmentEvent $event -Foreground $foreground
    }
}

function Undo-LastResult {
    $event = Undo-LastSegmentResult -Session $session
    if ($null -eq $event) { $statusLabel.ForeColor = [Drawing.Color]::DimGray; $statusLabel.Text = '当前记录没有可撤销的计数。'; return }
    Write-RecordEvent -EventType 'undo' -SegmentEvent $event; Update-Display
    $statusLabel.ForeColor = [Drawing.Color]::DimGray; $statusLabel.Text = "已撤销 $($session.Hosts[$event.HostId].Name) 的 $($event.Position) 记录。"
}

function Invoke-HotKey([int]$HotKeyId) {
    try {
        switch ($HotKeyId) {
            { $_ -in 101, 201 } { Record-Position First; break }
            { $_ -in 102, 202 } { Record-Position Middle; break }
            { $_ -in 103, 203 } { Record-Position Final; break }
            { $_ -in 104, 204 } { Record-Position Failure; break }
            { $_ -in 105, 205 } { Undo-LastResult; break }
        }
    } catch {
        $statusLabel.ForeColor = [Drawing.Color]::DarkRed
        $statusLabel.Text = "快捷键处理失败，计数记录已保留：$($_.Exception.Message)"
        $_ | Out-String | Add-Content -LiteralPath (Join-Path $RecordDirectory 'hotkey-errors.log') -Encoding utf8
        [System.Media.SystemSounds]::Hand.Play()
    }
}

function Register-RecorderHotKeys {
    $modifiers = [uint32](0x0001 -bor 0x0002 -bor 0x4000)
    $definitions = @(
        @{ Id = 201; Key = 0x4A; Name = 'Ctrl+Alt+J' }, @{ Id = 202; Key = 0x4B; Name = 'Ctrl+Alt+K' },
        @{ Id = 203; Key = 0x4C; Name = 'Ctrl+Alt+L' }, @{ Id = 204; Key = 0x58; Name = 'Ctrl+Alt+X' }, @{ Id = 205; Key = 0x5A; Name = 'Ctrl+Alt+Z' },
        @{ Id = 101; Key = 0x75; Name = 'Ctrl+Alt+F6' }, @{ Id = 102; Key = 0x76; Name = 'Ctrl+Alt+F7' },
        @{ Id = 103; Key = 0x77; Name = 'Ctrl+Alt+F8' }, @{ Id = 104; Key = 0x78; Name = 'Ctrl+Alt+F9' }, @{ Id = 105; Key = 0x79; Name = 'Ctrl+Alt+F10' }
    )
    foreach ($definition in $definitions) {
        if (-not [YimeThreeHostNative]::RegisterHotKey($form.Handle, $definition.Id, $modifiers, $definition.Key)) { throw "无法注册全局快捷键 $($definition.Name)，可能已被其他程序占用。" }
        [void]$registeredHotKeyIds.Add($definition.Id)
    }
}

$form.add_HotKeyPressed({ param($sender, $eventArgs) Invoke-HotKey $eventArgs.Id })
$newButton.Add_Click({ Start-NewSession }); $undoButton.Add_Click({ Undo-LastResult })
$summaryButton.Add_Click({ [Windows.Forms.Clipboard]::SetText((Get-TestSummary $session)); $statusLabel.ForeColor = [Drawing.Color]::DimGray; $statusLabel.Text = '三宿主统计摘要已复制。' })
$commandButton.Add_Click({
    Write-RecordEvent -EventType 'evidence_snapshot'
    [Windows.Forms.Clipboard]::SetText((Get-CaptureCommand $session))
    $statusLabel.ForeColor = [Drawing.Color]::DimGray
    $statusLabel.Text = '已固化证据快照，并复制直接读取该 JSONL 的命令。'
})
$openButton.Add_Click({ [Diagnostics.Process]::Start($RecordDirectory) | Out-Null }); $topMostCheck.Add_CheckedChanged({ $form.TopMost = $topMostCheck.Checked })
$form.Add_FormClosing({
    if ($null -ne $session) { Write-RecordEvent -EventType 'session_ended' }
    foreach ($id in $registeredHotKeyIds) { [void][YimeThreeHostNative]::UnregisterHotKey($form.Handle, $id) }
})
$form.Add_Shown({
    try {
        Register-RecorderHotKeys
        if ([string]::IsNullOrWhiteSpace($ResumeRecordPath)) {
            Start-NewSession
        } else {
            $script:session = Import-TestSession $ResumeRecordPath
            Write-RecordEvent -EventType 'session_resumed'
            Update-Display
            $statusLabel.ForeColor = [Drawing.Color]::DimGray
            $statusLabel.Text = '已续接原三宿主计数；请回到被测宿主继续。'
        }
    }
    catch {
        $statusLabel.ForeColor = [Drawing.Color]::DarkRed
        $statusLabel.Text = $_.Exception.Message
        $_.Exception.ToString() | Set-Content -LiteralPath (Join-Path $RecordDirectory 'startup-error.txt') -Encoding utf8
    }
})

[void]$form.ShowDialog()
