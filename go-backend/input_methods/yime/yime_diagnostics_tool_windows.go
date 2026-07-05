//go:build windows

package yime

func (ime *IME) ensureDiagnosticsToolScript() (string, error) {
	return ime.ensureStandaloneToolScript("pime_yime_diagnostics_tool.ps1", diagnosticsToolScript)
}

const diagnosticsToolScript = `param(
  [string]$UserDir,
  [string]$SharedDir,
  [string]$HelpDir,
  [string]$LogDir
)

$ErrorActionPreference = "Stop"
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName Microsoft.VisualBasic
[System.Windows.Forms.Application]::EnableVisualStyles()

function Show-Error {
  param([string]$Message)
  [System.Windows.Forms.MessageBox]::Show($Message, "Yime Diagnostics", "OK", "Error") | Out-Null
}

function Open-Path {
  param([string]$Path)
  if ([string]::IsNullOrWhiteSpace($Path) -or -not (Test-Path -LiteralPath $Path)) {
    Show-Error ("Missing target: " + $Path)
    return
  }
  Start-Process -FilePath $Path | Out-Null
}

function Format-StatusLine {
  param(
    [string]$Label,
    [string]$State,
    [string]$Detail
  )
  return ($Label + ": " + $State + " | " + $Detail)
}

function Get-PathCheck {
  param([string]$Label, [string]$Path)
  if ([string]::IsNullOrWhiteSpace($Path)) {
    return (Format-StatusLine $Label "missing" "path value is empty")
  }
  if (-not (Test-Path -LiteralPath $Path)) {
    return (Format-StatusLine $Label "missing" $Path)
  }
  return (Format-StatusLine $Label "ok" $Path)
}

function Get-FileCheck {
  param([string]$Label, [string]$Path)
  if ([string]::IsNullOrWhiteSpace($Path)) {
    return (Format-StatusLine $Label "missing" "path value is empty")
  }
  if (-not (Test-Path -LiteralPath $Path)) {
    return (Format-StatusLine $Label "missing" $Path)
  }
  $item = Get-Item -LiteralPath $Path -ErrorAction SilentlyContinue
  if ($null -eq $item) {
    return (Format-StatusLine $Label "missing" $Path)
  }
  return (Format-StatusLine $Label "ok" ($item.FullName + " | modified " + $item.LastWriteTime.ToString("yyyy-MM-dd HH:mm:ss")))
}

function Get-InstallRoot {
  param([string]$RuntimeSharedDir)
  if ([string]::IsNullOrWhiteSpace($RuntimeSharedDir)) {
    return ""
  }
  try {
    return [System.IO.Directory]::GetParent([System.IO.Directory]::GetParent([System.IO.Directory]::GetParent($RuntimeSharedDir).FullName).FullName).FullName
  } catch {
    return ""
  }
}

function Get-ServerBinaryPath {
  param([string]$RuntimeSharedDir)
  if ([string]::IsNullOrWhiteSpace($RuntimeSharedDir)) {
    return ""
  }
  try {
    return (Join-Path ([System.IO.Directory]::GetParent([System.IO.Directory]::GetParent([System.IO.Directory]::GetParent($RuntimeSharedDir).FullName).FullName).FullName) "server.exe")
  } catch {
    return ""
  }
}

function Get-ToolLauncherPath {
  param([string]$RuntimeSharedDir)
  if ([string]::IsNullOrWhiteSpace($RuntimeSharedDir)) {
    return ""
  }
  try {
    return (Join-Path ([System.IO.Directory]::GetParent([System.IO.Directory]::GetParent([System.IO.Directory]::GetParent($RuntimeSharedDir).FullName).FullName).FullName) "tool-launcher.exe")
  } catch {
    return ""
  }
}

function Get-DeployerCandidates {
  param([string]$RuntimeSharedDir)
  $candidates = New-Object System.Collections.Generic.List[string]
  if ([string]::IsNullOrWhiteSpace($RuntimeSharedDir)) {
    return $candidates
  }
  try {
    $goBackendDir = [System.IO.Directory]::GetParent([System.IO.Directory]::GetParent([System.IO.Directory]::GetParent($RuntimeSharedDir).FullName).FullName).FullName
    $candidates.Add((Join-Path $goBackendDir "rime_deployer.exe"))
  } catch {
  }
  $candidates.Add("C:\dev\librime\build\bin\Release\rime_deployer.exe")
  return $candidates
}

function Get-DeployerCheck {
  param([string]$RuntimeSharedDir)
  $candidates = Get-DeployerCandidates $RuntimeSharedDir
  foreach ($candidate in $candidates) {
    if ([string]::IsNullOrWhiteSpace($candidate)) {
      continue
    }
    if (Test-Path -LiteralPath $candidate) {
      $item = Get-Item -LiteralPath $candidate -ErrorAction SilentlyContinue
      return (Format-StatusLine "rime_deployer.exe" "ok" ($item.FullName + " | modified " + $item.LastWriteTime.ToString("yyyy-MM-dd HH:mm:ss")))
    }
  }
  return (Format-StatusLine "rime_deployer.exe" "missing" (($candidates -join "; ")))
}

function Get-InstallFlavorCheck {
  param([string]$InstallRoot)
  if ([string]::IsNullOrWhiteSpace($InstallRoot)) {
    return (Format-StatusLine "Install root" "missing" "could not derive install root from shared data path")
  }
  if ($InstallRoot -like "C:\Program Files (x86)\YIME*") {
    return (Format-StatusLine "Install root" "installed" $InstallRoot)
  }
  return (Format-StatusLine "Install root" "nonstandard" $InstallRoot)
}

function Get-ProcessSummary {
  param([string]$ProcessName)
  $processes = @(Get-Process -Name $ProcessName -ErrorAction SilentlyContinue)
  if ($processes.Count -eq 0) {
    return (Format-StatusLine $ProcessName "stopped" "no running process found")
  }
  $details = foreach ($process in $processes) {
    $path = ""
    try {
      $path = $process.Path
    } catch {
      $path = "<path unavailable>"
    }
    ("PID " + $process.Id + " | " + $path)
  }
  return (Format-StatusLine $ProcessName "running" ($details -join " || "))
}

function Get-LogSummary {
  param([string]$Path)
  if ([string]::IsNullOrWhiteSpace($Path) -or -not (Test-Path -LiteralPath $Path)) {
    return (Format-StatusLine "Logs" "missing" "directory missing")
  }
  $files = @(Get-ChildItem -LiteralPath $Path -File -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending)
  if ($files.Count -eq 0) {
    return (Format-StatusLine "Logs" "empty" "directory exists but no files were found")
  }
  $latest = $files[0]
  $latestLine = ""
  try {
    $latestLine = (Get-Content -LiteralPath $latest.FullName -Tail 1 -ErrorAction SilentlyContinue)
  } catch {
    $latestLine = ""
  }
  if ([string]::IsNullOrWhiteSpace($latestLine)) {
    $latestLine = "<last line unavailable>"
  }
  return (Format-StatusLine "Logs" "ok" ("{0} files | latest {1} @ {2} | tail {3}" -f $files.Count, $latest.Name, $latest.LastWriteTime.ToString("yyyy-MM-dd HH:mm:ss"), $latestLine))
}

function Get-PrimaryLogFile {
  param([string]$Path)
  if ([string]::IsNullOrWhiteSpace($Path) -or -not (Test-Path -LiteralPath $Path)) {
    return ""
  }
  $goBackendLog = Join-Path $Path "go_backend.log"
  if (Test-Path -LiteralPath $goBackendLog) {
    return $goBackendLog
  }
  $logs = @(Get-ChildItem -LiteralPath $Path -File -Filter *.log -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending)
  if ($logs.Count -gt 0) {
    return $logs[0].FullName
  }
  return ""
}

function Get-RecentLogLines {
  param([string]$Path)
  if ([string]::IsNullOrWhiteSpace($Path) -or -not (Test-Path -LiteralPath $Path)) {
    return @()
  }
  try {
    return @(Get-Content -LiteralPath $Path -Tail 200 -ErrorAction SilentlyContinue)
  } catch {
    return @()
  }
}

function Count-Matches {
  param(
    [string[]]$Lines,
    [string]$Pattern
  )
  if ($Lines.Count -eq 0) {
    return 0
  }
  return @($Lines | Where-Object { $_ -match $Pattern }).Count
}

function Get-LastMatchLine {
  param(
    [string[]]$Lines,
    [string]$Pattern
  )
  if ($Lines.Count -eq 0) {
    return ""
  }
  $matches = @($Lines | Where-Object { $_ -match $Pattern })
  if ($matches.Count -eq 0) {
    return ""
  }
  return $matches[-1]
}

function Get-LineTimestamp {
  param([string]$Line)
  if ([string]::IsNullOrWhiteSpace($Line)) {
    return $null
  }
  $match = [regex]::Match($Line, '(\d{4}/\d{2}/\d{2} \d{2}:\d{2}:\d{2})')
  if (-not $match.Success) {
    return $null
  }
  try {
    return [datetime]::ParseExact($match.Groups[1].Value, "yyyy/MM/dd HH:mm:ss", $null)
  } catch {
    return $null
  }
}

function Format-TimeGap {
  param([TimeSpan]$Span)
  $seconds = [Math]::Abs([int][Math]::Round($Span.TotalSeconds))
  if ($seconds -lt 60) {
    return ($seconds.ToString() + "s")
  }
  $minutes = [Math]::Floor($seconds / 60)
  $remaining = $seconds % 60
  if ($minutes -lt 60) {
    return ($minutes.ToString() + "m " + $remaining.ToString() + "s")
  }
  $hours = [Math]::Floor($minutes / 60)
  $remainingMinutes = $minutes % 60
  return ($hours.ToString() + "h " + $remainingMinutes.ToString() + "m")
}

function Get-CommandMeaning {
  param([int]$CommandId)
  switch ($CommandId) {
    10 { return "重新部署" }
    11 { return "同步" }
    12 { return "打开同步目录" }
    13 { return "打开共享目录" }
    14 { return "打开用户目录" }
    16 { return "打开日志目录" }
    20 { return "切换到变长方案" }
    21 { return "切换到等长方案" }
    22 { return "切换到省键方案" }
    36 { return "打开用户词库管理" }
    42 { return "反查显示：隐藏编码" }
    43 { return "反查显示：标准拼音" }
    44 { return "反查显示：音元拼音" }
    45 { return "反查显示：键位序列" }
    60 { return "打开帮助" }
    61 { return "打开试用反馈说明" }
    62 { return "复制试用反馈模板" }
    63 { return "打开工具箱" }
    70 { return "候选项数：5" }
    71 { return "候选项数：6" }
    72 { return "候选项数：7" }
    73 { return "候选项数：8" }
    74 { return "候选项数：9" }
    75 { return "切换候选排列方向" }
    default { return ("未知命令 " + $CommandId) }
  }
}

function Get-CommandIdValues {
  param([string[]]$Lines)
  $values = New-Object System.Collections.Generic.List[int]
  foreach ($line in $Lines) {
    $matches = [regex]::Matches($line, 'commandId=(\d+)')
    foreach ($match in $matches) {
      $parsed = 0
      if ([int]::TryParse($match.Groups[1].Value, [ref]$parsed)) {
        $values.Add($parsed)
      }
    }
  }
  return $values.ToArray()
}

function Get-CommandInterpretation {
  param([string[]]$Lines)
  $commandIds = Get-CommandIdValues $Lines
  if ($commandIds.Count -eq 0) {
    return @(
      (Format-StatusLine "Command interpretation" "unknown" "no recent commandId was found in the backend log")
    )
  }

  $counts = @{}
  foreach ($commandId in $commandIds) {
    $key = [string]$commandId
    if (-not $counts.ContainsKey($key)) {
      $counts[$key] = 0
    }
    $counts[$key]++
  }

  $summary = New-Object System.Collections.Generic.List[string]
  $summary.Add((Format-StatusLine "Recent command ids" "count" ([string]$commandIds.Count)))

  $lastCommandId = $commandIds[-1]
  $summary.Add((Format-StatusLine "Last command id" "seen" ($lastCommandId.ToString() + " | " + (Get-CommandMeaning $lastCommandId))))

  foreach ($entry in ($counts.GetEnumerator() | Sort-Object { [int]$_.Key })) {
    $commandId = [int]$entry.Key
    $summary.Add((Format-StatusLine ("Command " + $commandId) "hits" ($entry.Value.ToString() + " | " + (Get-CommandMeaning $commandId))))
  }

  return $summary.ToArray()
}

function Get-RecommendedActions {
  param(
    [int]$RequestCount,
    [int]$CommandCount,
    [int]$DeployCount,
    [int]$ReloadCount,
    [int]$ErrorCount,
    [nullable[datetime]]$LastCommandTime,
    [nullable[datetime]]$LastDeployTime,
    [nullable[datetime]]$LastErrorTime,
    [string]$LastErrorLine
  )

  $actions = New-Object System.Collections.Generic.List[string]

  if ($RequestCount -eq 0) {
    $actions.Add((Format-StatusLine "Recommended action" "check" "先确认宿主是否真的打到了这套 backend；优先检查安装路径、正在运行的 PIMELauncher/server 路径，以及日志文件是否来自当前安装。"))
  }

  if ($RequestCount -gt 0 -and $CommandCount -eq 0) {
    $actions.Add((Format-StatusLine "Recommended action" "check" "先重现一次语言栏操作，再看是否出现 onCommand 或 commandId；如果还是没有，优先查宿主菜单点击路径和命令映射。"))
  }

  if ($CommandCount -gt 0 -and ($DeployCount + $ReloadCount) -eq 0) {
    $actions.Add((Format-StatusLine "Recommended action" "retry" "命令到了但没看到 deploy/reload；先重试一次重新部署，再刷新这个面板确认日志里是否出现部署信号。"))
  }

  if ($null -ne $LastCommandTime -and $null -ne $LastDeployTime -and $LastDeployTime -lt $LastCommandTime) {
    $actions.Add((Format-StatusLine "Recommended action" "restart" "最后一次部署早于最后一次命令；优先再做一次部署，必要时重启 PIMELauncher 和 server。"))
  }

  if ($ErrorCount -gt 0) {
    $detail = "先看最后一条 error-like line。"
    if (-not [string]::IsNullOrWhiteSpace($LastErrorLine)) {
      $detail = "先看最后一条 error-like line: " + $LastErrorLine
    }
    $actions.Add((Format-StatusLine "Recommended action" "inspect" $detail))
  }

  if ($null -ne $LastCommandTime -and $null -ne $LastErrorTime -and $LastErrorTime -ge $LastCommandTime) {
    $actions.Add((Format-StatusLine "Recommended action" "correlate" "错误出现在最近一次命令之后；优先把最后命中的 commandId 和最后一条错误行一起对照。"))
  }

  if ($RequestCount -gt 0 -and $CommandCount -gt 0 -and $ErrorCount -eq 0 -and ($DeployCount + $ReloadCount) -gt 0) {
    $actions.Add((Format-StatusLine "Recommended action" "next" "日志上看命令、部署和运行链路都在动；下一步优先检查用户目录里的配置内容和实际界面表现是否一致。"))
  }

  if ($actions.Count -eq 0) {
    $actions.Add((Format-StatusLine "Recommended action" "observe" "当前日志信号还不够强；先重现一次问题，再立刻刷新面板。"))
  }

  return $actions.ToArray()
}

function Get-LogInterpretation {
  param([string]$Path)

  $logPath = Get-PrimaryLogFile $Path
  if ([string]::IsNullOrWhiteSpace($logPath)) {
    return @(
      (Format-StatusLine "Primary log" "missing" "could not locate go_backend.log or any .log file"),
      (Format-StatusLine "Interpretation" "unknown" "no log file means command/deploy/reload judgement cannot go further")
    )
  }

  $lines = Get-RecentLogLines $logPath
  if ($lines.Count -eq 0) {
    return @(
      (Format-StatusLine "Primary log" "empty" $logPath),
      (Format-StatusLine "Interpretation" "unknown" "log file exists but recent content could not be read")
    )
  }

  $requestCount = Count-Matches $lines "method="
  $commandCount = Count-Matches $lines "method=onCommand|commandId="
  $activateCount = Count-Matches $lines "method=onActivate"
  $menuCount = Count-Matches $lines "method=onMenu"
  $selectCandidateCount = Count-Matches $lines "method=selectCandidate"
  $deployCount = Count-Matches $lines "deploy|Redeploy|重新部署|部署"
  $reloadCount = Count-Matches $lines "reload|重载|刷新"
  $errorCount = Count-Matches $lines "error|failed|timeout|unknown|错误|失败|hung|panic"

  $lastCommandLine = Get-LastMatchLine $lines "method=onCommand|commandId="
  $lastDeployLine = Get-LastMatchLine $lines "deploy|Redeploy|重新部署|部署"
  $lastErrorLine = Get-LastMatchLine $lines "error|failed|timeout|unknown|错误|失败|hung|panic"
  $lastCommandTime = Get-LineTimestamp $lastCommandLine
  $lastDeployTime = Get-LineTimestamp $lastDeployLine
  $lastErrorTime = Get-LineTimestamp $lastErrorLine

  $summary = New-Object System.Collections.Generic.List[string]
  $summary.Add((Format-StatusLine "Primary log" "ok" $logPath))
  $summary.Add((Format-StatusLine "Recent requests" "count" ([string]$requestCount)))
  $summary.Add((Format-StatusLine "Recent onCommand" "count" ([string]$commandCount)))
  $summary.Add((Format-StatusLine "Recent onActivate" "count" ([string]$activateCount)))
  $summary.Add((Format-StatusLine "Recent onMenu" "count" ([string]$menuCount)))
  $summary.Add((Format-StatusLine "Recent selectCandidate" "count" ([string]$selectCandidateCount)))
  $summary.Add((Format-StatusLine "Recent deploy/reload signals" "count" ([string]($deployCount + $reloadCount))))
  $summary.Add((Format-StatusLine "Recent error-like lines" "count" ([string]$errorCount)))

  if (-not [string]::IsNullOrWhiteSpace($lastCommandLine)) {
    $summary.Add((Format-StatusLine "Last command line" "seen" $lastCommandLine))
  }
  if (-not [string]::IsNullOrWhiteSpace($lastDeployLine)) {
    $summary.Add((Format-StatusLine "Last deploy/reload line" "seen" $lastDeployLine))
  }
  if (-not [string]::IsNullOrWhiteSpace($lastErrorLine)) {
    $summary.Add((Format-StatusLine "Last error-like line" "seen" $lastErrorLine))
  }
  if ($null -ne $lastCommandTime) {
    $summary.Add((Format-StatusLine "Last command time" "seen" $lastCommandTime.ToString("yyyy-MM-dd HH:mm:ss")))
  }
  if ($null -ne $lastDeployTime) {
    $summary.Add((Format-StatusLine "Last deploy/reload time" "seen" $lastDeployTime.ToString("yyyy-MM-dd HH:mm:ss")))
  }
  if ($null -ne $lastErrorTime) {
    $summary.Add((Format-StatusLine "Last error-like time" "seen" $lastErrorTime.ToString("yyyy-MM-dd HH:mm:ss")))
  }

  if ($requestCount -eq 0) {
    $summary.Add((Format-StatusLine "Interpretation" "warning" "the backend log does not show recent requests; the host may not be reaching this backend at all"))
  }
  if ($requestCount -gt 0 -and $commandCount -eq 0) {
    $summary.Add((Format-StatusLine "Interpretation" "warning" "requests are arriving, but no recent onCommand or commandId signal was seen"))
  }
  if ($commandCount -gt 0 -and ($deployCount + $reloadCount) -eq 0) {
    $summary.Add((Format-StatusLine "Interpretation" "warning" "command traffic is visible, but no recent deploy/reload signal was observed"))
  }
  if ($errorCount -gt 0) {
    $summary.Add((Format-StatusLine "Interpretation" "warning" "recent error-like lines exist; check the last error-like line first"))
  }
  if ($requestCount -gt 0 -and $commandCount -gt 0 -and $errorCount -eq 0) {
    $summary.Add((Format-StatusLine "Interpretation" "ok" "the log shows live backend traffic without obvious recent errors"))
  }
  if ($null -ne $lastCommandTime -and $null -eq $lastDeployTime) {
    $summary.Add((Format-StatusLine "Time interpretation" "warning" "a recent command was seen, but no later deploy/reload timestamp was found"))
  }
  if ($null -ne $lastCommandTime -and $null -ne $lastDeployTime) {
    $gap = $lastDeployTime - $lastCommandTime
    if ($lastDeployTime -lt $lastCommandTime) {
      $summary.Add((Format-StatusLine "Time interpretation" "warning" ("the last deploy/reload was " + (Format-TimeGap $gap) + " before the last command; the latest command may not have taken effect yet")))
    } else {
      $summary.Add((Format-StatusLine "Time interpretation" "ok" ("the last deploy/reload followed the last command by " + (Format-TimeGap $gap))))
    }
  }
  if ($null -ne $lastCommandTime -and $null -ne $lastErrorTime) {
    $gap = $lastErrorTime - $lastCommandTime
    if ($lastErrorTime -ge $lastCommandTime) {
      $summary.Add((Format-StatusLine "Time interpretation" "warning" ("an error-like line appeared " + (Format-TimeGap $gap) + " after the last command")))
    } else {
      $summary.Add((Format-StatusLine "Time interpretation" "note" ("the last error-like line was " + (Format-TimeGap $gap) + " before the last command")))
    }
  }
  if ($commandCount -gt 0) {
    foreach ($item in @(Get-CommandInterpretation $lines)) {
      $summary.Add([string]$item)
    }
  }
  foreach ($item in @(Get-RecommendedActions $requestCount $commandCount $deployCount $reloadCount $errorCount $lastCommandTime $lastDeployTime $lastErrorTime $lastErrorLine)) {
    $summary.Add([string]$item)
  }

  return $summary.ToArray()
}

function Get-RimeUserFilesSummary {
  param([string]$RuntimeUserDir)
  if ([string]::IsNullOrWhiteSpace($RuntimeUserDir) -or -not (Test-Path -LiteralPath $RuntimeUserDir)) {
    return @(
      (Format-StatusLine "default.custom.yaml" "missing" "user dir unavailable"),
      (Format-StatusLine "user.yaml" "missing" "user dir unavailable"),
      (Format-StatusLine "yime_settings_state.json" "missing" "user dir unavailable"),
      (Format-StatusLine "custom_phrase.txt" "missing" "user dir unavailable"),
      (Format-StatusLine "yime_user_phrases.txt" "missing" "user dir unavailable")
    )
  }
  return @(
    (Get-FileCheck "default.custom.yaml" (Join-Path $RuntimeUserDir "default.custom.yaml")),
    (Get-FileCheck "user.yaml" (Join-Path $RuntimeUserDir "user.yaml")),
    (Get-FileCheck "yime_settings_state.json" (Join-Path $RuntimeUserDir "yime_settings_state.json")),
    (Get-FileCheck "custom_phrase.txt" (Join-Path $RuntimeUserDir "custom_phrase.txt")),
    (Get-FileCheck "yime_user_phrases.txt" (Join-Path $RuntimeUserDir "yime_user_phrases.txt"))
  )
}

function Read-SettingsFileText {
  param([string]$Path)
  if ([string]::IsNullOrWhiteSpace($Path) -or -not (Test-Path -LiteralPath $Path)) {
    return ""
  }
  try {
    return [System.IO.File]::ReadAllText($Path)
  } catch {
    return ""
  }
}

function Read-SettingsConfiguredSchema {
  param([string]$RuntimeUserDir)
  if ([string]::IsNullOrWhiteSpace($RuntimeUserDir)) {
    return ""
  }
  $userYamlPath = Join-Path $RuntimeUserDir "user.yaml"
  foreach ($line in ((Read-SettingsFileText $userYamlPath) -split "\r?\n")) {
    $trimmed = $line.Trim()
    if ($trimmed.StartsWith("previously_selected_schema:")) {
      return ($trimmed.Substring("previously_selected_schema:".Length)).Trim()
    }
  }

  $defaultCustomPath = Join-Path $RuntimeUserDir "default.custom.yaml"
  foreach ($line in ((Read-SettingsFileText $defaultCustomPath) -split "\r?\n")) {
    $trimmed = $line.Trim()
    if ($trimmed.StartsWith("- schema:")) {
      return ($trimmed.Substring("- schema:".Length)).Trim()
    }
  }
  return ""
}

function Read-SettingsConfiguredPageSize {
  param([string]$RuntimeUserDir)
  if ([string]::IsNullOrWhiteSpace($RuntimeUserDir)) {
    return ""
  }
  $defaultCustomPath = Join-Path $RuntimeUserDir "default.custom.yaml"
  foreach ($line in ((Read-SettingsFileText $defaultCustomPath) -split "\r?\n")) {
    $trimmed = $line.Trim()
    if ($trimmed.StartsWith('"menu/page_size":')) {
      return ($trimmed.Substring('"menu/page_size":'.Length)).Trim()
    }
    if ($trimmed.StartsWith("menu/page_size:")) {
      return ($trimmed.Substring("menu/page_size:".Length)).Trim()
    }
  }
  return ""
}

function Read-StandaloneSettingsSnapshot {
  param([string]$RuntimeUserDir)
  $snapshot = [ordered]@{
    reverse_lookup_display_mode = ""
    candidate_layout            = ""
    parse_status                = "missing"
    parse_detail                = "yime_settings_state.json not found"
  }

  if ([string]::IsNullOrWhiteSpace($RuntimeUserDir)) {
    $snapshot.parse_detail = "user dir unavailable"
    return [pscustomobject]$snapshot
  }

  $statePath = Join-Path $RuntimeUserDir "yime_settings_state.json"
  if (-not (Test-Path -LiteralPath $statePath)) {
    return [pscustomobject]$snapshot
  }

  try {
    $state = Get-Content -LiteralPath $statePath -Raw -Encoding UTF8 | ConvertFrom-Json -ErrorAction Stop
    $snapshot.reverse_lookup_display_mode = [string]$state.reverse_lookup_display_mode
    $snapshot.candidate_layout = [string]$state.candidate_layout
    $snapshot.parse_status = "ok"
    $snapshot.parse_detail = "JSON parsed"
  } catch {
    $snapshot.parse_status = "invalid"
    $snapshot.parse_detail = $_.Exception.Message
  }

  return [pscustomobject]$snapshot
}

function Get-SettingsChainSummary {
  param([string]$RuntimeUserDir)

  if ([string]::IsNullOrWhiteSpace($RuntimeUserDir) -or -not (Test-Path -LiteralPath $RuntimeUserDir)) {
    return @(
      (Format-StatusLine "Settings chain" "missing" "user dir unavailable")
    )
  }

  $defaultCustomPath = Join-Path $RuntimeUserDir "default.custom.yaml"
  $userYamlPath = Join-Path $RuntimeUserDir "user.yaml"
  $statePath = Join-Path $RuntimeUserDir "yime_settings_state.json"
  $schemaID = Read-SettingsConfiguredSchema $RuntimeUserDir
  $pageSize = Read-SettingsConfiguredPageSize $RuntimeUserDir
  $state = Read-StandaloneSettingsSnapshot $RuntimeUserDir

  $summary = New-Object System.Collections.Generic.List[string]
  $summary.Add((Format-StatusLine "default.custom.yaml" $(if (Test-Path -LiteralPath $defaultCustomPath) { "present" } else { "missing" }) $defaultCustomPath))
  $summary.Add((Format-StatusLine "Configured schema" $(if ([string]::IsNullOrWhiteSpace($schemaID)) { "unknown" } else { "seen" }) $(if ([string]::IsNullOrWhiteSpace($schemaID)) { "no schema_list selection found" } else { $schemaID })))
  $summary.Add((Format-StatusLine "Configured page size" $(if ([string]::IsNullOrWhiteSpace($pageSize)) { "unknown" } else { "seen" }) $(if ([string]::IsNullOrWhiteSpace($pageSize)) { "no menu/page_size key found" } else { $pageSize })))
  $summary.Add((Format-StatusLine "user.yaml" $(if (Test-Path -LiteralPath $userYamlPath) { "present" } else { "missing" }) $userYamlPath))
  $summary.Add((Format-StatusLine "previously_selected_schema" $(if ([string]::IsNullOrWhiteSpace($schemaID)) { "unknown" } else { "seen" }) $(if ([string]::IsNullOrWhiteSpace($schemaID)) { "no schema selection found" } else { $schemaID })))
  $summary.Add((Format-StatusLine "yime_settings_state.json" $(if (Test-Path -LiteralPath $statePath) { "present" } else { "missing" }) $statePath))
  $summary.Add((Format-StatusLine "Standalone state parse" $state.parse_status $state.parse_detail))
  $summary.Add((Format-StatusLine "reverse_lookup_display_mode" $(if ([string]::IsNullOrWhiteSpace($state.reverse_lookup_display_mode)) { "unknown" } else { "seen" }) $(if ([string]::IsNullOrWhiteSpace($state.reverse_lookup_display_mode)) { "value missing" } else { $state.reverse_lookup_display_mode })))
  $summary.Add((Format-StatusLine "candidate_layout" $(if ([string]::IsNullOrWhiteSpace($state.candidate_layout)) { "unknown" } else { "seen" }) $(if ([string]::IsNullOrWhiteSpace($state.candidate_layout)) { "value missing" } else { $state.candidate_layout })))
  $summary.Add((Format-StatusLine "Activation sync hint" "observe" "onActivate only restores standalone reverse-lookup and layout preferences; schema and page-size changes still need an explicit rebuild/deploy path."))
  return $summary.ToArray()
}

function Convert-SectionLinesToMarkdown {
  param([string[]]$Lines)
  $reportLines = New-Object System.Collections.Generic.List[string]
  foreach ($line in $Lines) {
    if ([string]::IsNullOrWhiteSpace($line)) {
      $reportLines.Add("")
      continue
    }
    if ($line.StartsWith("== ") -and $line.EndsWith(" ==")) {
      $title = $line.Substring(3, $line.Length - 6)
      $reportLines.Add("## " + $title)
      continue
    }
    $reportLines.Add("- " + $line)
  }
  return $reportLines.ToArray()
}

function Protect-SensitiveText {
  param(
    [string]$Text,
    [bool]$Anonymize = $false,
    [bool]$KeepDriveLetter = $false,
    [ValidateSet("full", "names-only")]
    [string]$AnonymizeMode = "full"
  )

  if (-not $Anonymize -or [string]::IsNullOrWhiteSpace($Text)) {
    return $Text
  }

  $protected = $Text
  $replacementMap = @{}
  $replacementMap[$env:USERNAME] = "<user>"
  $replacementMap[$env:COMPUTERNAME] = "<machine>"
  $replacementMap[$UserDir] = "<user-dir>"
  $replacementMap[$SharedDir] = "<shared-dir>"
  $replacementMap[$HelpDir] = "<help-dir>"
  $replacementMap[$LogDir] = "<log-dir>"

  $serverPath = Get-ServerBinaryPath $SharedDir
  if (-not [string]::IsNullOrWhiteSpace($serverPath)) {
    $replacementMap[$serverPath] = "<server-exe>"
  }

  $installRoot = Get-InstallRoot $SharedDir
  if (-not [string]::IsNullOrWhiteSpace($installRoot)) {
    $replacementMap[$installRoot] = "<install-root>"
  }

  foreach ($key in ($replacementMap.Keys | Sort-Object Length -Descending)) {
    if ([string]::IsNullOrWhiteSpace($key)) {
      continue
    }
    if ($AnonymizeMode -eq "names-only" -and ($key -eq $UserDir -or $key -eq $SharedDir -or $key -eq $HelpDir -or $key -eq $LogDir -or $key -eq $serverPath -or $key -eq $installRoot)) {
      continue
    }
    $protected = $protected.Replace($key, $replacementMap[$key])
  }

  if ($AnonymizeMode -eq "names-only") {
    $protected = [regex]::Replace($protected, '(?i)([A-Z]:\\Users\\)([^\\\s]+)', '$1<user>')
    return $protected
  }

  $protected = [regex]::Replace($protected, '(?i)([A-Z]):\\Users\\[^\\\s]+', {
    param($match)
    if ($KeepDriveLetter) {
      return ($match.Groups[1].Value + ':\\<user-profile>')
    }
    return '<user-profile>'
  })
  $protected = [regex]::Replace($protected, '(?i)([A-Z]):\\[^:]*', {
    param($match)
    $value = $match.Value
    if ($value -like "<*") {
      return $value
    }
    if ($KeepDriveLetter) {
      return ($match.Groups[1].Value + ':\\<path>')
    }
    return "<path>"
  })
  return $protected
}

function Protect-ReportLines {
  param(
    [string[]]$Lines,
    [bool]$Anonymize = $false,
    [bool]$KeepDriveLetter = $false,
    [ValidateSet("full", "names-only")]
    [string]$AnonymizeMode = "full"
  )

  if (-not $Anonymize) {
    return $Lines
  }

  $protected = New-Object System.Collections.Generic.List[string]
  foreach ($line in $Lines) {
    $protected.Add((Protect-SensitiveText $line $true $KeepDriveLetter $AnonymizeMode))
  }
  return $protected.ToArray()
}

function Get-EnvironmentSummaryLines {
  $installRoot = Get-InstallRoot $SharedDir
  $serverPath = Get-ServerBinaryPath $SharedDir
  $toolLauncherPath = Get-ToolLauncherPath $SharedDir
  $launcherRunning = @(Get-Process -Name "PIMELauncher" -ErrorAction SilentlyContinue).Count -gt 0
  $serverRunning = @(Get-Process -Name "server" -ErrorAction SilentlyContinue).Count -gt 0

  return @(
    "== Environment summary ==",
    (Format-StatusLine "Generated at" "time" (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")),
    (Format-StatusLine "Machine" "name" $env:COMPUTERNAME),
    (Format-StatusLine "User" "name" $env:USERNAME),
    (Format-StatusLine "OS" "version" [System.Environment]::OSVersion.VersionString),
    (Format-StatusLine "Install root" "path" $installRoot),
    (Format-StatusLine "server.exe" "path" $serverPath),
    (Format-StatusLine "tool-launcher.exe" "path" $toolLauncherPath),
    (Format-StatusLine "PIMELauncher" ($(if ($launcherRunning) { "running" } else { "stopped" })) "snapshot"),
    (Format-StatusLine "server" ($(if ($serverRunning) { "running" } else { "stopped" })) "snapshot"),
    (Format-StatusLine "UserDir" "path" $UserDir),
    (Format-StatusLine "SharedDir" "path" $SharedDir),
    (Format-StatusLine "LogDir" "path" $LogDir)
  )
}

function Get-LatestRecommendedActionLines {
  $reportLines = Get-LogInterpretation $LogDir
  $actions = @($reportLines | Where-Object { $_ -like "Recommended action:*" })
  if ($actions.Count -eq 0) {
    return @(
      "== Recommended actions ==",
      (Format-StatusLine "Recommended action" "observe" "no action mapping was produced from the current log snapshot")
    )
  }

  $lines = New-Object System.Collections.Generic.List[string]
  $lines.Add("== Recommended actions ==")
  foreach ($action in $actions) {
    $lines.Add($action)
  }
  return $lines.ToArray()
}

function Get-RawLogExcerptLines {
  param(
    [ValidateSet("tail", "errors", "command-window", "error-window")]
    [string]$Mode = "tail",
    [int]$TailCount = 40,
    [int]$ContextWindowRadius = 20
  )

  $logPath = Get-PrimaryLogFile $LogDir
  if ([string]::IsNullOrWhiteSpace($logPath)) {
    return @(
      "== Raw log excerpt ==",
      (Format-StatusLine "Primary log" "missing" "could not locate a log file to excerpt")
    )
  }

  $lines = Get-RecentLogLines $logPath
  if ($lines.Count -eq 0) {
    return @(
      "== Raw log excerpt ==",
      (Format-StatusLine "Primary log" "empty" $logPath)
    )
  }

  $excerpt = @()
  $excerptDetail = ""

  if ($Mode -eq "errors") {
    $excerpt = @($lines | Where-Object { $_ -match "error|failed|timeout|unknown|错误|失败|hung|panic" } | Select-Object -Last $TailCount)
    $excerptDetail = "error-related lines"
    if ($excerpt.Count -eq 0) {
      $excerpt = @("no recent error-like lines matched the current filter")
    }
  } elseif ($Mode -eq "error-window") {
    $lastErrorIndex = -1
    for ($index = $lines.Count - 1; $index -ge 0; $index--) {
      if ($lines[$index] -match "error|failed|timeout|unknown|hung|panic") {
        $lastErrorIndex = $index
        break
      }
    }

    if ($lastErrorIndex -lt 0) {
      $excerpt = @("no recent error-like line was found for an error-centered excerpt")
      $excerptDetail = "error-centered window unavailable"
    } else {
      $windowRadius = [Math]::Max(2, $ContextWindowRadius)
      $start = [Math]::Max(0, $lastErrorIndex - $windowRadius)
      $end = [Math]::Min($lines.Count - 1, $lastErrorIndex + $windowRadius)
      $excerpt = @($lines[$start..$end])
      $excerptDetail = ("window around last error-like line (" + $windowRadius.ToString() + " lines before/after)")
    }
  } elseif ($Mode -eq "command-window") {
    $lastCommandIndex = -1
    for ($index = $lines.Count - 1; $index -ge 0; $index--) {
      if ($lines[$index] -match "method=onCommand|commandId=") {
        $lastCommandIndex = $index
        break
      }
    }

    if ($lastCommandIndex -lt 0) {
      $excerpt = @("no recent commandId or onCommand line was found for a command-centered excerpt")
      $excerptDetail = "command-centered window unavailable"
    } else {
      $windowRadius = [Math]::Max(2, $ContextWindowRadius)
      $start = [Math]::Max(0, $lastCommandIndex - $windowRadius)
      $end = [Math]::Min($lines.Count - 1, $lastCommandIndex + $windowRadius)
      $excerpt = @($lines[$start..$end])
      $excerptDetail = ("window around last command (" + $windowRadius.ToString() + " lines before/after)")
    }
  } else {
    $start = [Math]::Max(0, $lines.Count - $TailCount)
    $excerpt = @($lines[$start..($lines.Count - 1)])
    $excerptDetail = "tail lines"
  }

  $result = New-Object System.Collections.Generic.List[string]
  $result.Add("== Raw log excerpt ==")
  $result.Add((Format-StatusLine "Primary log" "source" $logPath))
  $result.Add((Format-StatusLine "Excerpt mode" "selected" $Mode))
  $result.Add((Format-StatusLine "Excerpt" "detail" $excerptDetail))
  $result.Add((Format-StatusLine "Excerpt" "count" ($excerpt.Count.ToString() + " lines")))
  foreach ($line in $excerpt) {
    if ([string]::IsNullOrWhiteSpace($line)) {
      $result.Add("<blank>")
    } else {
      $result.Add($line)
    }
  }
  return $result.ToArray()
}

function Build-StructuredDiagnosticReport {
  param(
    [bool]$IncludeEnvironmentSummary = $true,
    [bool]$IncludeRecommendedActions = $true,
    [bool]$IncludeRawLogExcerpt = $false,
    [bool]$Anonymize = $false,
    [bool]$KeepDriveLetter = $false,
    [ValidateSet("full", "names-only")]
    [string]$AnonymizeMode = "full",
    [ValidateSet("tail", "errors", "command-window", "error-window")]
    [string]$RawLogExcerptMode = "tail",
    [int]$ContextWindowRadius = 20
  )

  $reportLines = New-Object System.Collections.Generic.List[string]
  $reportLines.Add("# Yime Diagnostics Report")
  $reportLines.Add("")
  $reportLines.Add("Generated: " + (Get-Date).ToString("yyyy-MM-dd HH:mm:ss"))
  $reportLines.Add((Protect-SensitiveText ("UserDir: " + $UserDir) $Anonymize $KeepDriveLetter $AnonymizeMode))
  $reportLines.Add((Protect-SensitiveText ("SharedDir: " + $SharedDir) $Anonymize $KeepDriveLetter $AnonymizeMode))
  $reportLines.Add((Protect-SensitiveText ("HelpDir: " + $HelpDir) $Anonymize $KeepDriveLetter $AnonymizeMode))
  $reportLines.Add((Protect-SensitiveText ("LogDir: " + $LogDir) $Anonymize $KeepDriveLetter $AnonymizeMode))
  $reportLines.Add("Anonymized: " + $(if ($Anonymize) { "yes" } else { "no" }))
  $reportLines.Add("Anonymize mode: " + $AnonymizeMode)
  $reportLines.Add("Keep drive letter: " + $(if ($KeepDriveLetter) { "yes" } else { "no" }))
  $reportLines.Add("")

  if ($IncludeEnvironmentSummary) {
    foreach ($line in (Convert-SectionLinesToMarkdown (Protect-ReportLines (Get-EnvironmentSummaryLines) $Anonymize $KeepDriveLetter $AnonymizeMode))) {
      $reportLines.Add($line)
    }
    $reportLines.Add("")
  }

  foreach ($line in (Convert-SectionLinesToMarkdown (Protect-ReportLines (Build-DiagnosticsReport -split [Environment]::NewLine) $Anonymize $KeepDriveLetter $AnonymizeMode))) {
    $reportLines.Add($line)
  }

  if ($IncludeRecommendedActions) {
    $reportLines.Add("")
    foreach ($line in (Convert-SectionLinesToMarkdown (Protect-ReportLines (Get-LatestRecommendedActionLines) $Anonymize $KeepDriveLetter $AnonymizeMode))) {
      $reportLines.Add($line)
    }
  }

  if ($IncludeRawLogExcerpt) {
    $reportLines.Add("")
    foreach ($line in (Convert-SectionLinesToMarkdown (Protect-ReportLines (Get-RawLogExcerptLines -Mode $RawLogExcerptMode -ContextWindowRadius $ContextWindowRadius) $Anonymize $KeepDriveLetter $AnonymizeMode))) {
      $reportLines.Add($line)
    }
  }

  return ($reportLines -join [Environment]::NewLine)
}

function Get-DiagnosticFindings {
  $findings = New-Object System.Collections.Generic.List[string]
  $installRoot = Get-InstallRoot $SharedDir
  $serverPath = Get-ServerBinaryPath $SharedDir
  $toolLauncherPath = Get-ToolLauncherPath $SharedDir
  $deployerCandidates = Get-DeployerCandidates $SharedDir

  $userDirExists = -not [string]::IsNullOrWhiteSpace($UserDir) -and (Test-Path -LiteralPath $UserDir)
  $sharedDirExists = -not [string]::IsNullOrWhiteSpace($SharedDir) -and (Test-Path -LiteralPath $SharedDir)
  $logDirExists = -not [string]::IsNullOrWhiteSpace($LogDir) -and (Test-Path -LiteralPath $LogDir)
  $serverExists = -not [string]::IsNullOrWhiteSpace($serverPath) -and (Test-Path -LiteralPath $serverPath)
  $toolLauncherExists = -not [string]::IsNullOrWhiteSpace($toolLauncherPath) -and (Test-Path -LiteralPath $toolLauncherPath)

  $deployerExists = $false
  foreach ($candidate in $deployerCandidates) {
    if (-not [string]::IsNullOrWhiteSpace($candidate) -and (Test-Path -LiteralPath $candidate)) {
      $deployerExists = $true
      break
    }
  }

  $launcherRunning = @(Get-Process -Name "PIMELauncher" -ErrorAction SilentlyContinue).Count -gt 0
  $serverRunning = @(Get-Process -Name "server" -ErrorAction SilentlyContinue).Count -gt 0

  $defaultCustomExists = $userDirExists -and (Test-Path -LiteralPath (Join-Path $UserDir "default.custom.yaml"))
  $userYamlExists = $userDirExists -and (Test-Path -LiteralPath (Join-Path $UserDir "user.yaml"))
  $settingsStateExists = $userDirExists -and (Test-Path -LiteralPath (Join-Path $UserDir "yime_settings_state.json"))
  $customPhraseExists = $userDirExists -and (Test-Path -LiteralPath (Join-Path $UserDir "custom_phrase.txt"))
  $userPhraseSourceExists = $userDirExists -and (Test-Path -LiteralPath (Join-Path $UserDir "yime_user_phrases.txt"))
  $configuredSchema = Read-SettingsConfiguredSchema $UserDir
  $configuredPageSize = Read-SettingsConfiguredPageSize $UserDir
  $standaloneState = Read-StandaloneSettingsSnapshot $UserDir

  $logFiles = @()
  if ($logDirExists) {
    $logFiles = @(Get-ChildItem -LiteralPath $LogDir -File -ErrorAction SilentlyContinue)
  }

  if (-not $sharedDirExists) {
    $findings.Add("判定：当前共享运行时路径不存在，像是这套 Yime/PIME 运行时还没装好，或者现在打开的不是预期安装。")
  }

  if ($sharedDirExists -and -not $serverExists) {
    $findings.Add("判定：共享数据目录存在，但安装里的 server.exe 不见了，像是安装不完整，或者运行时目录和主程序版本没有对齐。")
  }

  if ($sharedDirExists -and -not $toolLauncherExists) {
    $findings.Add("判定：共享数据目录存在，但安装里的 tool-launcher.exe 不见了，独立 settings/diagnostics 工具可能根本起不来。")
  }

  if ($serverExists -and -not $deployerExists) {
    $findings.Add("判定：server.exe 在，但 rime_deployer.exe 没找到。配置写到了磁盘也可能不会真正部署生效。")
  }

  if (-not $userDirExists) {
    $findings.Add("判定：用户 Rime 目录不存在，像是还没完成第一次用户侧初始化或首次运行部署。")
  }

  if ($userDirExists -and -not $defaultCustomExists -and -not $customPhraseExists -and -not $userPhraseSourceExists) {
    $findings.Add("判定：用户目录有了，但关键 Yime/Rime 文件几乎都没出现，像是首次部署还没跑通。")
  }

  if ($userDirExists -and $defaultCustomExists -and -not $userYamlExists) {
    $findings.Add("判定：default.custom.yaml 已经有了，但 user.yaml 缺失。schema/page-size 可能写到了盘上，但当前 schema 选择来源不完整。")
  }

  if ($userDirExists -and ($defaultCustomExists -or $userYamlExists) -and -not $settingsStateExists) {
    $findings.Add("判定：Rime 配置文件已经存在，但 yime_settings_state.json 缺失。reverse lookup 和 candidate layout 这条 standalone 设置链路还没有落盘。")
  }

  if ($userDirExists -and $settingsStateExists -and $standaloneState.parse_status -ne "ok") {
    $findings.Add("判定：yime_settings_state.json 存在，但当前内容无法正常解析。standalone UI 偏好可能写坏了，onActivate 也就没法稳定回放。")
  }

  if ($userDirExists -and $defaultCustomExists -and [string]::IsNullOrWhiteSpace($configuredPageSize)) {
    $findings.Add("判定：default.custom.yaml 在，但没有读到 menu/page_size。候选项数看起来改了却不生效时，先检查这里到底有没有写到 quoted 或 unquoted key。")
  }

  if ($userDirExists -and ($defaultCustomExists -or $userYamlExists) -and [string]::IsNullOrWhiteSpace($configuredSchema)) {
    $findings.Add("判定：配置文件在，但没有读到 schema 选择。若 settings 工具里切过方案却没生效，先回看 schema_list 和 previously_selected_schema。")
  }

  if (($serverRunning -or $launcherRunning) -and (-not $logDirExists -or $logFiles.Count -eq 0)) {
    $findings.Add("判定：进程已经在跑，但日志目录不存在或没有日志，值得先查安装路径、权限，或确认现在跑的真是这套二进制。")
  }

  if ($serverExists -and -not $serverRunning -and $launcherRunning) {
    $findings.Add("判定：PIMELauncher 在跑，但 server.exe 没在跑，像是前端起来了、后端还没被真正拉起，或拉起后很快退出。")
  }

  if ($serverExists -and -not $launcherRunning -and -not $serverRunning) {
    $findings.Add("判定：安装里的二进制在，但 PIMELauncher 和 server 都没在跑。若你刚更新过源码，这很像还没重启相关进程。")
  }

  if ($serverExists -and $serverRunning) {
    $runningServer = Get-Process -Name "server" -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($null -ne $runningServer) {
      try {
        if ($runningServer.Path -and ($runningServer.Path -ne $serverPath)) {
          $findings.Add("判定：当前运行中的 server.exe 路径和这次检查到的安装路径不一致，像是机器上还有旧进程或另一套安装在生效。")
        }
      } catch {
      }
    }
  }

  if ($findings.Count -eq 0) {
    $findings.Add("判定：目前路径、安装、进程、用户文件和日志层面都没有明显硬故障。若行为仍不对，更像是配置内容、部署结果或运行中状态没有按预期刷新。")
  }

  return $findings.ToArray()
}

function Build-DiagnosticsReport {
  $installRoot = Get-InstallRoot $SharedDir
  $serverPath = Get-ServerBinaryPath $SharedDir
  $toolLauncherPath = Get-ToolLauncherPath $SharedDir

  $sections = @()
  $sections += "== Findings =="
  $sections += (Get-DiagnosticFindings)
  $sections += ""
  $sections += "== Paths =="
  $sections += (Get-PathCheck "User data" $UserDir)
  $sections += (Get-PathCheck "Shared data" $SharedDir)
  $sections += (Get-PathCheck "Help docs" $HelpDir)
  $sections += (Get-PathCheck "Log dir" $LogDir)
  $sections += ""
  $sections += "== Installed runtime =="
  $sections += (Get-InstallFlavorCheck $installRoot)
  $sections += (Get-FileCheck "server.exe" $serverPath)
  $sections += (Get-FileCheck "tool-launcher.exe" $toolLauncherPath)
  $sections += (Get-DeployerCheck $SharedDir)
  $sections += ""
  $sections += "== Running processes =="
  $sections += (Get-ProcessSummary "PIMELauncher")
  $sections += (Get-ProcessSummary "server")
  $sections += ""
  $sections += "== Settings chain =="
  $sections += (Get-SettingsChainSummary $UserDir)
  $sections += ""
  $sections += "== User Rime files =="
  $sections += (Get-RimeUserFilesSummary $UserDir)
  $sections += ""
  $sections += "== Logs =="
  $sections += (Get-LogSummary $LogDir)
  $sections += ""
  $sections += "== Log interpretation =="
  $sections += (Get-LogInterpretation $LogDir)
  return ($sections -join [Environment]::NewLine)
}

$form = New-Object System.Windows.Forms.Form
$form.Text = "Yime Diagnostics"
$form.StartPosition = "CenterScreen"
$form.Size = New-Object System.Drawing.Size(900, 620)
$form.MinimumSize = New-Object System.Drawing.Size(900, 620)
$form.MaximizeBox = $false

$title = New-Object System.Windows.Forms.Label
$title.Left = 16
$title.Top = 16
$title.Width = 860
$title.Height = 24
$title.Font = New-Object System.Drawing.Font("Microsoft YaHei UI", 12, [System.Drawing.FontStyle]::Bold)
$title.Text = "Yime diagnostics panel"
$form.Controls.Add($title)

$summary = New-Object System.Windows.Forms.Label
$summary.Left = 16
$summary.Top = 48
$summary.Width = 860
$summary.Height = 36
$summary.Text = "This panel checks the concrete layers that usually make source fixes look ineffective: paths, installed binaries, running processes, user Rime files, and current logs."
$form.Controls.Add($summary)

$statusBox = New-Object System.Windows.Forms.TextBox
$statusBox.Left = 16
$statusBox.Top = 96
$statusBox.Width = 860
$statusBox.Height = 372
$statusBox.Multiline = $true
$statusBox.ScrollBars = "Vertical"
$statusBox.ReadOnly = $true
$statusBox.Font = New-Object System.Drawing.Font("Consolas", 10)
$form.Controls.Add($statusBox)

function Refresh-Status {
  $statusBox.Text = Build-DiagnosticsReport
}

$updatingPresetSelection = $false
$savedReportPresets = @()

function Get-ReportPresetStorePath {
  if ([string]::IsNullOrWhiteSpace($UserDir)) {
    return ""
  }
  return (Join-Path $UserDir "diagnostics_report_presets.json")
}

function Get-ExportedReportPresetPath {
  param([string]$Name)

  if ([string]::IsNullOrWhiteSpace($UserDir) -or [string]::IsNullOrWhiteSpace($Name)) {
    return ""
  }
  return (Join-Path $UserDir ($Name + ".diagnostics_preset.json"))
}

function Get-ImportedReportPresetCandidates {
  if ([string]::IsNullOrWhiteSpace($UserDir) -or -not (Test-Path -LiteralPath $UserDir)) {
    return @()
  }
  try {
    return @(Get-ChildItem -LiteralPath $UserDir -Filter *.diagnostics_preset.json -File -ErrorAction Stop | Sort-Object Name)
  } catch {
    Show-Error ("Failed to list exported preset files: " + $_.Exception.Message)
    return @()
  }
}

function Show-ImportPresetPicker {
  param(
    [object[]]$Candidates,
    [string]$DefaultFileName = ""
  )

  if ($null -eq $Candidates -or $Candidates.Count -eq 0) {
    return ""
  }

  $dialog = New-Object System.Windows.Forms.Form
  $dialog.Text = "Import diagnostics preset"
  $dialog.StartPosition = "CenterParent"
  $dialog.Size = New-Object System.Drawing.Size(560, 420)
  $dialog.MinimumSize = New-Object System.Drawing.Size(560, 420)
  $dialog.MaximizeBox = $false
  $dialog.MinimizeBox = $false

  $title = New-Object System.Windows.Forms.Label
  $title.Left = 16
  $title.Top = 16
  $title.Width = 510
  $title.Height = 24
  $title.Font = New-Object System.Drawing.Font("Microsoft YaHei UI", 10, [System.Drawing.FontStyle]::Bold)
  $title.Text = "Choose an exported preset file to import"
  $dialog.Controls.Add($title)

  $hint = New-Object System.Windows.Forms.Label
  $hint.Left = 16
  $hint.Top = 44
  $hint.Width = 510
  $hint.Height = 32
  $hint.Text = "Files are listed from the current user data directory. Importing will add or replace a saved preset by name."
  $dialog.Controls.Add($hint)

  $listBox = New-Object System.Windows.Forms.ListBox
  $listBox.Left = 16
  $listBox.Top = 88
  $listBox.Width = 510
  $listBox.Height = 240
  $listBox.HorizontalScrollbar = $true
  foreach ($candidate in $Candidates) {
    [void]$listBox.Items.Add($candidate.Name)
  }
  if (-not [string]::IsNullOrWhiteSpace($DefaultFileName)) {
    $defaultIndex = $listBox.Items.IndexOf($DefaultFileName)
    if ($defaultIndex -ge 0) {
      $listBox.SelectedIndex = $defaultIndex
    }
  }
  if ($listBox.SelectedIndex -lt 0 -and $listBox.Items.Count -gt 0) {
    $listBox.SelectedIndex = 0
  }
  $dialog.Controls.Add($listBox)

  $pathLabel = New-Object System.Windows.Forms.Label
  $pathLabel.Left = 16
  $pathLabel.Top = 336
  $pathLabel.Width = 510
  $pathLabel.Height = 32
  $pathLabel.Text = ""
  $dialog.Controls.Add($pathLabel)

  $selectedFileName = ""
  $updatePath = {
    if ($listBox.SelectedIndex -ge 0) {
      $pathLabel.Text = [string]$Candidates[$listBox.SelectedIndex].FullName
    } else {
      $pathLabel.Text = ""
    }
  }
  & $updatePath
  $listBox.Add_SelectedIndexChanged($updatePath)

  $importButton = New-Object System.Windows.Forms.Button
  $importButton.Left = 350
  $importButton.Top = 368
  $importButton.Width = 84
  $importButton.Height = 28
  $importButton.Text = "Import"
  $importButton.Add_Click({
    if ($listBox.SelectedIndex -lt 0) {
      return
    }
    $script:selectedFileName = $listBox.SelectedItem.ToString()
    $dialog.DialogResult = [System.Windows.Forms.DialogResult]::OK
    $dialog.Close()
  })
  $dialog.Controls.Add($importButton)

  $cancelButton = New-Object System.Windows.Forms.Button
  $cancelButton.Left = 442
  $cancelButton.Top = 368
  $cancelButton.Width = 84
  $cancelButton.Height = 28
  $cancelButton.Text = "Cancel"
  $cancelButton.Add_Click({
    $dialog.DialogResult = [System.Windows.Forms.DialogResult]::Cancel
    $dialog.Close()
  })
  $dialog.Controls.Add($cancelButton)

  $listBox.Add_DoubleClick({
    if ($listBox.SelectedIndex -lt 0) {
      return
    }
    $script:selectedFileName = $listBox.SelectedItem.ToString()
    $dialog.DialogResult = [System.Windows.Forms.DialogResult]::OK
    $dialog.Close()
  })

  $script:selectedFileName = ""
  $result = $dialog.ShowDialog()
  if ($result -eq [System.Windows.Forms.DialogResult]::OK) {
    return $script:selectedFileName
  }
  return ""
}

function Get-CurrentReportOptions {
  $anonymizeMode = "full"
  if ($anonymizeModeComboBox.SelectedIndex -eq 1) {
    $anonymizeMode = "names-only"
  }

  $rawLogExcerptMode = "tail"
  if ($excerptModeComboBox.SelectedIndex -eq 1) {
    $rawLogExcerptMode = "errors"
  } elseif ($excerptModeComboBox.SelectedIndex -eq 2) {
    $rawLogExcerptMode = "command-window"
  } elseif ($excerptModeComboBox.SelectedIndex -eq 3) {
    $rawLogExcerptMode = "error-window"
  }

  $contextWindowRadius = 20
  if ($windowSizeComboBox.SelectedIndex -eq 0) {
    $contextWindowRadius = 10
  } elseif ($windowSizeComboBox.SelectedIndex -eq 2) {
    $contextWindowRadius = 40
  }

  return [ordered]@{
    includeEnvironmentSummary = $environmentCheckBox.Checked
    includeActions            = $actionsCheckBox.Checked
    includeRawLogExcerpt      = $rawLogCheckBox.Checked
    anonymize                 = $anonymizeCheckBox.Checked
    keepDriveLetter           = $keepDriveLetterCheckBox.Checked
    anonymizeMode             = $anonymizeMode
    rawLogExcerptMode         = $rawLogExcerptMode
    contextWindowRadius       = $contextWindowRadius
  }
}

function Apply-ReportOptions {
  param($Options)

  if ($null -eq $Options) {
    return
  }

  $script:updatingPresetSelection = $true
  $environmentCheckBox.Checked = [bool]$Options.includeEnvironmentSummary
  $actionsCheckBox.Checked = [bool]$Options.includeActions
  $rawLogCheckBox.Checked = [bool]$Options.includeRawLogExcerpt
  $anonymizeCheckBox.Checked = [bool]$Options.anonymize
  $keepDriveLetterCheckBox.Checked = [bool]$Options.keepDriveLetter
  $anonymizeModeComboBox.SelectedIndex = $(if ($Options.anonymizeMode -eq "names-only") { 1 } else { 0 })
  switch ($Options.rawLogExcerptMode) {
    "errors" { $excerptModeComboBox.SelectedIndex = 1 }
    "command-window" { $excerptModeComboBox.SelectedIndex = 2 }
    "error-window" { $excerptModeComboBox.SelectedIndex = 3 }
    default { $excerptModeComboBox.SelectedIndex = 0 }
  }
  switch ([int]$Options.contextWindowRadius) {
    10 { $windowSizeComboBox.SelectedIndex = 0 }
    40 { $windowSizeComboBox.SelectedIndex = 2 }
    default { $windowSizeComboBox.SelectedIndex = 1 }
  }
  $script:updatingPresetSelection = $false
}

function Load-SavedReportPresets {
  $path = Get-ReportPresetStorePath
  if ([string]::IsNullOrWhiteSpace($path) -or -not (Test-Path -LiteralPath $path)) {
    return @()
  }
  try {
    $loaded = Get-Content -LiteralPath $path -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
    if ($loaded -is [System.Array]) {
      return @($loaded)
    }
    if ($null -ne $loaded) {
      return @($loaded)
    }
  } catch {
    Show-Error ("Failed to load saved report presets: " + $_.Exception.Message)
  }
  return @()
}

function Save-SavedReportPresets {
  $path = Get-ReportPresetStorePath
  if ([string]::IsNullOrWhiteSpace($path)) {
    Show-Error "UserDir is unavailable; cannot save report presets."
    return $false
  }
  try {
    $dir = Split-Path -Parent $path
    if (-not (Test-Path -LiteralPath $dir)) {
      New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }
    ($script:savedReportPresets | ConvertTo-Json -Depth 6) | Set-Content -LiteralPath $path -Encoding UTF8
    return $true
  } catch {
    Show-Error ("Failed to save report presets: " + $_.Exception.Message)
    return $false
  }
}

function Refresh-PresetComboBoxItems {
  $currentSelection = $presetComboBox.SelectedItem
  $script:updatingPresetSelection = $true
  $presetComboBox.Items.Clear()
  foreach ($item in @("Issue-ready", "Local debugging", "Minimal share")) {
    [void]$presetComboBox.Items.Add(("[Built-in] " + $item))
  }
  foreach ($preset in $script:savedReportPresets) {
    if ($null -ne $preset.name -and -not [string]::IsNullOrWhiteSpace([string]$preset.name)) {
      [void]$presetComboBox.Items.Add(("[Saved] " + [string]$preset.name))
    }
  }
  [void]$presetComboBox.Items.Add("Custom")
  if ($null -ne $currentSelection -and $presetComboBox.Items.Contains($currentSelection)) {
    $presetComboBox.SelectedItem = $currentSelection
  } else {
    $presetComboBox.SelectedItem = "Issue-ready"
  }
  $script:updatingPresetSelection = $false
}

function Get-SelectedSavedPresetName {
  if ($null -eq $presetComboBox.SelectedItem) {
    return ""
  }
  $selected = $presetComboBox.SelectedItem.ToString()
  if ($selected -like "[[]Saved[]] *") {
    return $selected.Substring(8)
  }
  return ""
}

function Get-SavedPresetIndexByName {
  param([string]$Name)

  if ([string]::IsNullOrWhiteSpace($Name)) {
    return -1
  }
  for ($index = 0; $index -lt $script:savedReportPresets.Count; $index++) {
    if ([string]$script:savedReportPresets[$index].name -eq $Name) {
      return $index
    }
  }
  return -1
}

function Apply-ReportPreset {
  param([string]$Preset)

  switch ($Preset) {
    "Issue-ready" {
      Apply-ReportOptions @{
        includeEnvironmentSummary = $true
        includeActions            = $true
        includeRawLogExcerpt      = $true
        anonymize                 = $true
        keepDriveLetter           = $false
        anonymizeMode             = "full"
        rawLogExcerptMode         = "error-window"
        contextWindowRadius       = 20
      }
    }
    "Local debugging" {
      Apply-ReportOptions @{
        includeEnvironmentSummary = $true
        includeActions            = $true
        includeRawLogExcerpt      = $true
        anonymize                 = $false
        keepDriveLetter           = $true
        anonymizeMode             = "full"
        rawLogExcerptMode         = "command-window"
        contextWindowRadius       = 40
      }
    }
    "Minimal share" {
      Apply-ReportOptions @{
        includeEnvironmentSummary = $false
        includeActions            = $true
        includeRawLogExcerpt      = $false
        anonymize                 = $true
        keepDriveLetter           = $false
        anonymizeMode             = "names-only"
        rawLogExcerptMode         = "tail"
        contextWindowRadius       = 10
      }
    }
  }
}

function Sync-ReportPresetSelection {
  if ($script:updatingPresetSelection) {
    return
  }

  $matchedPreset = "Custom"
  $options = Get-CurrentReportOptions
  if ($options.includeEnvironmentSummary -and $options.includeActions -and $options.includeRawLogExcerpt -and $options.anonymize -and -not $options.keepDriveLetter -and $options.anonymizeMode -eq "full" -and $options.rawLogExcerptMode -eq "error-window" -and $options.contextWindowRadius -eq 20) {
    $matchedPreset = "Issue-ready"
  } elseif ($options.includeEnvironmentSummary -and $options.includeActions -and $options.includeRawLogExcerpt -and -not $options.anonymize -and $options.keepDriveLetter -and $options.anonymizeMode -eq "full" -and $options.rawLogExcerptMode -eq "command-window" -and $options.contextWindowRadius -eq 40) {
    $matchedPreset = "Local debugging"
  } elseif (-not $options.includeEnvironmentSummary -and $options.includeActions -and -not $options.includeRawLogExcerpt -and $options.anonymize -and -not $options.keepDriveLetter -and $options.anonymizeMode -eq "names-only" -and $options.rawLogExcerptMode -eq "tail" -and $options.contextWindowRadius -eq 10) {
    $matchedPreset = "Minimal share"
  } else {
    foreach ($preset in $script:savedReportPresets) {
      if ($null -eq $preset.options) {
        continue
      }
      $saved = $preset.options
      if ([bool]$saved.includeEnvironmentSummary -eq $options.includeEnvironmentSummary -and [bool]$saved.includeActions -eq $options.includeActions -and [bool]$saved.includeRawLogExcerpt -eq $options.includeRawLogExcerpt -and [bool]$saved.anonymize -eq $options.anonymize -and [bool]$saved.keepDriveLetter -eq $options.keepDriveLetter -and [string]$saved.anonymizeMode -eq $options.anonymizeMode -and [string]$saved.rawLogExcerptMode -eq $options.rawLogExcerptMode -and [int]$saved.contextWindowRadius -eq $options.contextWindowRadius) {
        $matchedPreset = ("[Saved] " + [string]$preset.name)
        break
      }
    }
  }

  $script:updatingPresetSelection = $true
  $presetComboBox.SelectedItem = $matchedPreset
  $script:updatingPresetSelection = $false
}

$reportOptionsLabel = New-Object System.Windows.Forms.Label
$reportOptionsLabel.Left = 16
$reportOptionsLabel.Top = 478
$reportOptionsLabel.Width = 160
$reportOptionsLabel.Height = 20
$reportOptionsLabel.Text = "Structured report options:"
$form.Controls.Add($reportOptionsLabel)

$presetLabel = New-Object System.Windows.Forms.Label
$presetLabel.Left = 186
$presetLabel.Top = 478
$presetLabel.Width = 50
$presetLabel.Height = 20
$presetLabel.Text = "Preset:"
$form.Controls.Add($presetLabel)

$presetComboBox = New-Object System.Windows.Forms.ComboBox
$presetComboBox.Left = 238
$presetComboBox.Top = 474
$presetComboBox.Width = 120
$presetComboBox.Height = 24
$presetComboBox.DropDownStyle = [System.Windows.Forms.ComboBoxStyle]::DropDownList
[void]$presetComboBox.Items.Add("Issue-ready")
$presetComboBox.SelectedIndex = 0
$form.Controls.Add($presetComboBox)

$savePresetButton = New-Object System.Windows.Forms.Button
$savePresetButton.Left = 366
$savePresetButton.Top = 474
$savePresetButton.Width = 56
$savePresetButton.Height = 24
$savePresetButton.Text = "Save"
$form.Controls.Add($savePresetButton)

$renamePresetButton = New-Object System.Windows.Forms.Button
$renamePresetButton.Left = 428
$renamePresetButton.Top = 474
$renamePresetButton.Width = 62
$renamePresetButton.Height = 24
$renamePresetButton.Text = "Rename"
$form.Controls.Add($renamePresetButton)

$deletePresetButton = New-Object System.Windows.Forms.Button
$deletePresetButton.Left = 496
$deletePresetButton.Top = 474
$deletePresetButton.Width = 56
$deletePresetButton.Height = 24
$deletePresetButton.Text = "Delete"
$form.Controls.Add($deletePresetButton)

$exportPresetButton = New-Object System.Windows.Forms.Button
$exportPresetButton.Left = 558
$exportPresetButton.Top = 474
$exportPresetButton.Width = 56
$exportPresetButton.Height = 24
$exportPresetButton.Text = "Export"
$form.Controls.Add($exportPresetButton)

$importPresetButton = New-Object System.Windows.Forms.Button
$importPresetButton.Left = 620
$importPresetButton.Top = 474
$importPresetButton.Width = 56
$importPresetButton.Height = 24
$importPresetButton.Text = "Import"
$form.Controls.Add($importPresetButton)

$environmentCheckBox = New-Object System.Windows.Forms.CheckBox
$environmentCheckBox.Left = 16
$environmentCheckBox.Top = 500
$environmentCheckBox.Width = 170
$environmentCheckBox.Height = 24
$environmentCheckBox.Text = "Include env summary"
$environmentCheckBox.Checked = $true
$form.Controls.Add($environmentCheckBox)

$actionsCheckBox = New-Object System.Windows.Forms.CheckBox
$actionsCheckBox.Left = 196
$actionsCheckBox.Top = 500
$actionsCheckBox.Width = 190
$actionsCheckBox.Height = 24
$actionsCheckBox.Text = "Include actions"
$actionsCheckBox.Checked = $true
$form.Controls.Add($actionsCheckBox)

$rawLogCheckBox = New-Object System.Windows.Forms.CheckBox
$rawLogCheckBox.Left = 396
$rawLogCheckBox.Top = 500
$rawLogCheckBox.Width = 220
$rawLogCheckBox.Height = 24
$rawLogCheckBox.Text = "Include raw log excerpt"
$rawLogCheckBox.Checked = $false
$form.Controls.Add($rawLogCheckBox)

$anonymizeCheckBox = New-Object System.Windows.Forms.CheckBox
$anonymizeCheckBox.Left = 626
$anonymizeCheckBox.Top = 500
$anonymizeCheckBox.Width = 150
$anonymizeCheckBox.Height = 24
$anonymizeCheckBox.Text = "Anonymize report"
$anonymizeCheckBox.Checked = $true
$form.Controls.Add($anonymizeCheckBox)

$keepDriveLetterCheckBox = New-Object System.Windows.Forms.CheckBox
$keepDriveLetterCheckBox.Left = 776
$keepDriveLetterCheckBox.Top = 500
$keepDriveLetterCheckBox.Width = 110
$keepDriveLetterCheckBox.Height = 24
$keepDriveLetterCheckBox.Text = "Keep drive"
$keepDriveLetterCheckBox.Checked = $false
$form.Controls.Add($keepDriveLetterCheckBox)

$anonymizeModeLabel = New-Object System.Windows.Forms.Label
$anonymizeModeLabel.Left = 706
$anonymizeModeLabel.Top = 526
$anonymizeModeLabel.Width = 110
$anonymizeModeLabel.Height = 20
$anonymizeModeLabel.Text = "Anonymize mode:"
$form.Controls.Add($anonymizeModeLabel)

$anonymizeModeComboBox = New-Object System.Windows.Forms.ComboBox
$anonymizeModeComboBox.Left = 814
$anonymizeModeComboBox.Top = 522
$anonymizeModeComboBox.Width = 72
$anonymizeModeComboBox.Height = 24
$anonymizeModeComboBox.DropDownStyle = [System.Windows.Forms.ComboBoxStyle]::DropDownList
[void]$anonymizeModeComboBox.Items.Add("Full")
[void]$anonymizeModeComboBox.Items.Add("Names only")
$anonymizeModeComboBox.SelectedIndex = 0
$form.Controls.Add($anonymizeModeComboBox)

$excerptModeLabel = New-Object System.Windows.Forms.Label
$excerptModeLabel.Left = 16
$excerptModeLabel.Top = 526
$excerptModeLabel.Width = 150
$excerptModeLabel.Height = 20
$excerptModeLabel.Text = "Raw log excerpt mode:"
$form.Controls.Add($excerptModeLabel)

$excerptModeComboBox = New-Object System.Windows.Forms.ComboBox
$excerptModeComboBox.Left = 172
$excerptModeComboBox.Top = 522
$excerptModeComboBox.Width = 220
$excerptModeComboBox.Height = 24
$excerptModeComboBox.DropDownStyle = [System.Windows.Forms.ComboBoxStyle]::DropDownList
[void]$excerptModeComboBox.Items.Add("Tail excerpt")
[void]$excerptModeComboBox.Items.Add("Error lines only")
[void]$excerptModeComboBox.Items.Add("Last command window")
[void]$excerptModeComboBox.Items.Add("Last error window")
$excerptModeComboBox.SelectedIndex = 0
$form.Controls.Add($excerptModeComboBox)

$windowSizeLabel = New-Object System.Windows.Forms.Label
$windowSizeLabel.Left = 406
$windowSizeLabel.Top = 526
$windowSizeLabel.Width = 150
$windowSizeLabel.Height = 20
$windowSizeLabel.Text = "Context window radius:"
$form.Controls.Add($windowSizeLabel)

$windowSizeComboBox = New-Object System.Windows.Forms.ComboBox
$windowSizeComboBox.Left = 582
$windowSizeComboBox.Top = 522
$windowSizeComboBox.Width = 120
$windowSizeComboBox.Height = 24
$windowSizeComboBox.DropDownStyle = [System.Windows.Forms.ComboBoxStyle]::DropDownList
[void]$windowSizeComboBox.Items.Add("10 lines")
[void]$windowSizeComboBox.Items.Add("20 lines")
[void]$windowSizeComboBox.Items.Add("40 lines")
$windowSizeComboBox.SelectedIndex = 1
$form.Controls.Add($windowSizeComboBox)

$script:savedReportPresets = Load-SavedReportPresets
Refresh-PresetComboBoxItems

$presetComboBox.Add_SelectedIndexChanged({
  if ($script:updatingPresetSelection) {
    return
  }
  if ($presetComboBox.SelectedItem) {
    $preset = $presetComboBox.SelectedItem.ToString()
    if ($preset -like "[[]Saved[]] *") {
      $presetName = $preset.Substring(8)
      $savedPreset = $script:savedReportPresets | Where-Object { [string]$_.name -eq $presetName } | Select-Object -First 1
      if ($null -ne $savedPreset) {
        Apply-ReportOptions $savedPreset.options
      }
    } elseif ($preset -like "[[]Built-in[]] *") {
      Apply-ReportPreset $preset.Substring(11)
    }
  }
})

$savePresetButton.Add_Click({
  $presetName = Get-SelectedSavedPresetName
  if ([string]::IsNullOrWhiteSpace($presetName)) {
    $presetName = [Microsoft.VisualBasic.Interaction]::InputBox("Name this report preset:", "Save diagnostics preset", "diagnostics preset")
    if ([string]::IsNullOrWhiteSpace($presetName)) {
      return
    }
  }

  $existingIndex = Get-SavedPresetIndexByName $presetName

  $presetRecord = [ordered]@{
    name    = $presetName
    options = (Get-CurrentReportOptions)
  }

  if ($existingIndex -ge 0) {
    $script:savedReportPresets[$existingIndex] = $presetRecord
  } else {
    $script:savedReportPresets += $presetRecord
  }

  if (Save-SavedReportPresets) {
    Refresh-PresetComboBoxItems
    $presetComboBox.SelectedItem = ("[Saved] " + $presetName)
  }
})

$renamePresetButton.Add_Click({
  $selectedSavedName = Get-SelectedSavedPresetName
  if ([string]::IsNullOrWhiteSpace($selectedSavedName)) {
    Show-Error "Select a saved preset before renaming it."
    return
  }

  $newName = [Microsoft.VisualBasic.Interaction]::InputBox("Rename this saved preset:", "Rename diagnostics preset", $selectedSavedName)
  if ([string]::IsNullOrWhiteSpace($newName) -or $newName -eq $selectedSavedName) {
    return
  }

  $existingIndex = Get-SavedPresetIndexByName $newName
  if ($existingIndex -ge 0) {
    Show-Error ("A saved preset named '" + $newName + "' already exists.")
    return
  }

  $selectedIndex = Get-SavedPresetIndexByName $selectedSavedName
  if ($selectedIndex -lt 0) {
    Show-Error "The selected saved preset could not be found."
    return
  }

  $script:savedReportPresets[$selectedIndex].name = $newName
  if (Save-SavedReportPresets) {
    Refresh-PresetComboBoxItems
    $presetComboBox.SelectedItem = ("[Saved] " + $newName)
  }
})

$deletePresetButton.Add_Click({
  $selectedSavedName = Get-SelectedSavedPresetName
  if ([string]::IsNullOrWhiteSpace($selectedSavedName)) {
    Show-Error "Select a saved preset before deleting it."
    return
  }

  $confirm = [System.Windows.Forms.MessageBox]::Show(
    ("Delete saved preset '" + $selectedSavedName + "'?"),
    "Delete diagnostics preset",
    [System.Windows.Forms.MessageBoxButtons]::OKCancel,
    [System.Windows.Forms.MessageBoxIcon]::Question
  )
  if ($confirm -ne [System.Windows.Forms.DialogResult]::OK) {
    return
  }

  $selectedIndex = Get-SavedPresetIndexByName $selectedSavedName
  if ($selectedIndex -lt 0) {
    Show-Error "The selected saved preset could not be found."
    return
  }

  $remaining = New-Object System.Collections.Generic.List[object]
  for ($index = 0; $index -lt $script:savedReportPresets.Count; $index++) {
    if ($index -ne $selectedIndex) {
      $remaining.Add($script:savedReportPresets[$index])
    }
  }
  $script:savedReportPresets = $remaining.ToArray()

  if (Save-SavedReportPresets) {
    Refresh-PresetComboBoxItems
    Sync-ReportPresetSelection
  }
})

$exportPresetButton.Add_Click({
  $defaultName = "exported_diagnostics_preset"
  $selectedSavedName = Get-SelectedSavedPresetName
  if (-not [string]::IsNullOrWhiteSpace($selectedSavedName)) {
    $defaultName = $selectedSavedName
  }

  $exportName = [Microsoft.VisualBasic.Interaction]::InputBox("Export current report options to a user-side file named:", "Export diagnostics preset", $defaultName)
  if ([string]::IsNullOrWhiteSpace($exportName)) {
    return
  }

  $exportPath = Get-ExportedReportPresetPath $exportName
  if ([string]::IsNullOrWhiteSpace($exportPath)) {
    Show-Error "UserDir is unavailable; cannot export the current preset."
    return
  }

  $exportRecord = [ordered]@{
    name       = $exportName
    exportedAt = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
    options    = (Get-CurrentReportOptions)
  }

  try {
    ($exportRecord | ConvertTo-Json -Depth 6) | Set-Content -LiteralPath $exportPath -Encoding UTF8
    [System.Windows.Forms.MessageBox]::Show(("Exported current preset to " + $exportPath), "Export diagnostics preset", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Information) | Out-Null
  } catch {
    Show-Error ("Failed to export current preset: " + $_.Exception.Message)
  }
})

$importPresetButton.Add_Click({
  $candidates = Get-ImportedReportPresetCandidates
  if ($candidates.Count -eq 0) {
    Show-Error "No exported preset files were found in the user data directory."
    return
  }

  $defaultFile = $candidates[0].Name
  $selectedSavedName = Get-SelectedSavedPresetName
  if (-not [string]::IsNullOrWhiteSpace($selectedSavedName)) {
    $preferredName = $selectedSavedName + ".diagnostics_preset.json"
    $preferred = $candidates | Where-Object { $_.Name -eq $preferredName } | Select-Object -First 1
    if ($null -ne $preferred) {
      $defaultFile = $preferred.Name
    }
  }

  $selectedFileName = Show-ImportPresetPicker -Candidates $candidates -DefaultFileName $defaultFile
  if ([string]::IsNullOrWhiteSpace($selectedFileName)) {
    return
  }

  $selectedFile = $candidates | Where-Object { $_.Name -eq $selectedFileName } | Select-Object -First 1
  if ($null -eq $selectedFile) {
    Show-Error ("Could not find exported preset file '" + $selectedFileName + "'.")
    return
  }

  try {
    $imported = Get-Content -LiteralPath $selectedFile.FullName -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
  } catch {
    Show-Error ("Failed to import preset file: " + $_.Exception.Message)
    return
  }

  if ($null -eq $imported -or $null -eq $imported.options) {
    Show-Error "The selected preset file does not contain an options payload."
    return
  }

  $importedName = [string]$imported.name
  if ([string]::IsNullOrWhiteSpace($importedName)) {
    $importedName = [System.IO.Path]::GetFileNameWithoutExtension([System.IO.Path]::GetFileNameWithoutExtension($selectedFile.Name))
  }

  $existingIndex = Get-SavedPresetIndexByName $importedName
  $presetRecord = [ordered]@{
    name    = $importedName
    options = $imported.options
  }

  if ($existingIndex -ge 0) {
    $script:savedReportPresets[$existingIndex] = $presetRecord
  } else {
    $script:savedReportPresets += $presetRecord
  }

  if (Save-SavedReportPresets) {
    Refresh-PresetComboBoxItems
    $presetComboBox.SelectedItem = ("[Saved] " + $importedName)
    Apply-ReportOptions $imported.options
    Sync-ReportPresetSelection
  }
})

foreach ($control in @($environmentCheckBox, $actionsCheckBox, $rawLogCheckBox, $anonymizeCheckBox, $keepDriveLetterCheckBox)) {
  $control.Add_CheckedChanged({ Sync-ReportPresetSelection })
}

foreach ($control in @($anonymizeModeComboBox, $excerptModeComboBox, $windowSizeComboBox)) {
  $control.Add_SelectedIndexChanged({ Sync-ReportPresetSelection })
}

$refreshButton = New-Object System.Windows.Forms.Button
$refreshButton.Left = 16
$refreshButton.Top = 552
$refreshButton.Width = 100
$refreshButton.Height = 32
$refreshButton.Text = "Refresh"
$refreshButton.Add_Click({ Refresh-Status })
$form.Controls.Add($refreshButton)

$copyButton = New-Object System.Windows.Forms.Button
$copyButton.Left = 132
$copyButton.Top = 552
$copyButton.Width = 170
$copyButton.Height = 32
$copyButton.Text = "Copy structured report"
$copyButton.Add_Click({
  $rawLogExcerptMode = "tail"
  if ($excerptModeComboBox.SelectedIndex -eq 1) {
    $rawLogExcerptMode = "errors"
  } elseif ($excerptModeComboBox.SelectedIndex -eq 2) {
    $rawLogExcerptMode = "command-window"
  } elseif ($excerptModeComboBox.SelectedIndex -eq 3) {
    $rawLogExcerptMode = "error-window"
  }

  $contextWindowRadius = 20
  if ($windowSizeComboBox.SelectedIndex -eq 0) {
    $contextWindowRadius = 10
  } elseif ($windowSizeComboBox.SelectedIndex -eq 2) {
    $contextWindowRadius = 40
  }

  $anonymizeMode = "full"
  if ($anonymizeModeComboBox.SelectedIndex -eq 1) {
    $anonymizeMode = "names-only"
  }

  $structuredReport = Build-StructuredDiagnosticReport -IncludeEnvironmentSummary $environmentCheckBox.Checked -IncludeRecommendedActions $actionsCheckBox.Checked -IncludeRawLogExcerpt $rawLogCheckBox.Checked -Anonymize $anonymizeCheckBox.Checked -KeepDriveLetter $keepDriveLetterCheckBox.Checked -AnonymizeMode $anonymizeMode -RawLogExcerptMode $rawLogExcerptMode -ContextWindowRadius $contextWindowRadius
  Set-Clipboard -Value $structuredReport
})
$form.Controls.Add($copyButton)

$logsButton = New-Object System.Windows.Forms.Button
$logsButton.Left = 318
$logsButton.Top = 552
$logsButton.Width = 100
$logsButton.Height = 32
$logsButton.Text = "Open logs"
$logsButton.Add_Click({ Open-Path $LogDir })
$form.Controls.Add($logsButton)

$userButton = New-Object System.Windows.Forms.Button
$userButton.Left = 434
$userButton.Top = 552
$userButton.Width = 120
$userButton.Height = 32
$userButton.Text = "Open user data"
$userButton.Add_Click({ Open-Path $UserDir })
$form.Controls.Add($userButton)

$sharedButton = New-Object System.Windows.Forms.Button
$sharedButton.Left = 570
$sharedButton.Top = 552
$sharedButton.Width = 130
$sharedButton.Height = 32
$sharedButton.Text = "Open shared data"
$sharedButton.Add_Click({ Open-Path $SharedDir })
$form.Controls.Add($sharedButton)

$guideButton = New-Object System.Windows.Forms.Button
$guideButton.Left = 716
$guideButton.Top = 552
$guideButton.Width = 160
$guideButton.Height = 32
$guideButton.Text = "Open diagnostics guide"
$guideButton.Add_Click({ Open-Path (Join-Path $HelpDir "diagnostics.html") })
$form.Controls.Add($guideButton)

Refresh-Status
Apply-ReportPreset "Issue-ready"

try {
  [void]$form.ShowDialog()
} catch {
  Show-Error $_.Exception.Message
}
`
