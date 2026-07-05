//go:build windows

package yime

import (
	"os"
	"path/filepath"
)

func (ime *IME) startSettingsToolHelper() error {
	userDir := ime.userDir()
	sharedDir := ime.sharedDir()
	helpDir := ime.helpDir()
	if userDir == "" || sharedDir == "" || helpDir == "" {
		return os.ErrNotExist
	}
	scriptPath, err := ime.ensureSettingsToolScript()
	if err != nil {
		return err
	}
	return startDetachedExecutable(
		ime.toolLauncherPath(),
		"powershell-script",
		scriptPath,
		"-UserDir", userDir,
		"-SharedDir", sharedDir,
		"-HelpDir", helpDir,
		"-LogDir", filepath.Join(os.Getenv("LOCALAPPDATA"), "PIME", "Logs"),
	)
}

func (ime *IME) ensureSettingsToolScript() (string, error) {
	return ime.ensureStandaloneToolScript("pime_yime_settings_tool.ps1", settingsToolScript)
}

const settingsToolScript = `param(
  [string]$UserDir,
  [string]$SharedDir,
  [string]$HelpDir,
  [string]$LogDir
)

$ErrorActionPreference = "Stop"
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[System.Windows.Forms.Application]::EnableVisualStyles()
$newline = [Environment]::NewLine

function Show-Error {
  param([string]$Message)
  [System.Windows.Forms.MessageBox]::Show($Message, "Yime Settings", "OK", "Error") | Out-Null
}

function Open-Path {
  param([string]$Path)
  if ([string]::IsNullOrWhiteSpace($Path) -or -not (Test-Path -LiteralPath $Path)) {
    Show-Error ("Missing target: " + $Path)
    return
  }
  Start-Process -FilePath $Path | Out-Null
}

function Read-FileText {
  param([string]$Path)
  if ([string]::IsNullOrWhiteSpace($Path) -or -not (Test-Path -LiteralPath $Path)) {
    return ""
  }
  return [System.IO.File]::ReadAllText($Path)
}

function Write-Utf8NoBom {
  param([string]$Path, [string]$Text)
  $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
  [System.IO.File]::WriteAllText($Path, $Text, $utf8NoBom)
}

function Get-DefaultCustomPath {
  return (Join-Path $UserDir "default.custom.yaml")
}

function Get-UserYamlPath {
  return (Join-Path $UserDir "user.yaml")
}

function Get-StandaloneSettingsStatePath {
  return (Join-Path $UserDir "yime_settings_state.json")
}

function Get-SyncDir {
  return (Join-Path $UserDir "sync")
}

function Get-DeployerPath {
  $candidates = @(
    (Join-Path (Split-Path $SharedDir -Parent) "rime_deployer.exe"),
    (Join-Path $SharedDir "rime_deployer.exe"),
    "C:\dev\librime\build\bin\Release\rime_deployer.exe"
  )
  foreach ($candidate in $candidates) {
    if (-not [string]::IsNullOrWhiteSpace($candidate) -and (Test-Path -LiteralPath $candidate)) {
      return $candidate
    }
  }
  return ""
}

function Get-AvailableSchemaOptions {
  $options = @(
    [pscustomobject]@{ Id = "yime_variable"; Label = "鍙橀暱"; Enabled = $true },
    [pscustomobject]@{ Id = "yime_full"; Label = "绛夐暱"; Enabled = $true },
    [pscustomobject]@{ Id = "yime_shorthand"; Label = "鐪侀敭"; Enabled = (Test-Path -LiteralPath (Join-Path $SharedDir "yime_shorthand.schema.yaml")) }
  )
  return $options
}

function Normalize-SchemaId {
  param([string]$SchemaId)
  switch (($SchemaId | ForEach-Object { $_.Trim() })) {
    "yime_variable" { return "yime_variable" }
    "yime_full" { return "yime_full" }
    "yime_shorthand" { return "yime_shorthand" }
    default { return "yime_variable" }
  }
}

function Normalize-ReverseLookupMode {
  param([string]$Mode)
  switch (($Mode | ForEach-Object { $_.Trim() })) {
    "hidden" { return "hidden" }
    "standard_pinyin" { return "standard_pinyin" }
    "yime_pinyin" { return "yime_pinyin" }
    "key_sequence" { return "key_sequence" }
    default { return "key_sequence" }
  }
}

function Normalize-CandidateLayout {
  param([string]$Layout)
  switch (($Layout | ForEach-Object { $_.Trim() })) {
    "horizontal" { return "horizontal" }
    "vertical" { return "vertical" }
    default { return "vertical" }
  }
}

function Normalize-PageSize {
  param([string]$Value)
  $number = 5
  if ([int]::TryParse(([string]$Value), [ref]$number)) {
    if ($number -lt 5) { $number = 5 }
    if ($number -gt 9) { $number = 9 }
    return $number
  }
  return 5
}

function Read-PreviouslySelectedSchema {
  $path = Get-UserYamlPath
  foreach ($line in ((Read-FileText $path) -split "\r?\n")) {
    $trimmed = $line.Trim()
    if ($trimmed.StartsWith("previously_selected_schema:")) {
      return (Normalize-SchemaId ($trimmed.Substring("previously_selected_schema:".Length)).Trim())
    }
  }
  return ""
}

function Read-SchemaListSelection {
  $path = Get-DefaultCustomPath
  foreach ($line in ((Read-FileText $path) -split "\r?\n")) {
    $trimmed = $line.Trim()
    if ($trimmed.StartsWith("- schema:")) {
      return (Normalize-SchemaId ($trimmed.Substring("- schema:".Length)).Trim())
    }
  }
  return ""
}

function Read-ConfiguredSchema {
  $selected = Read-PreviouslySelectedSchema
  if (-not [string]::IsNullOrWhiteSpace($selected)) {
    return $selected
  }
  $selected = Read-SchemaListSelection
  if (-not [string]::IsNullOrWhiteSpace($selected)) {
    return $selected
  }
  return "yime_variable"
}

function Parse-MenuPageSizeValue {
  param([string]$Line)
  $trimmed = $Line.Trim()
  if ($trimmed.StartsWith('"menu/page_size":')) {
    return ($trimmed.Substring('"menu/page_size":'.Length)).Trim()
  }
  if ($trimmed.StartsWith("menu/page_size:")) {
    return ($trimmed.Substring("menu/page_size:".Length)).Trim()
  }
  return ""
}

function Read-ConfiguredPageSize {
  $path = Get-DefaultCustomPath
  foreach ($line in ((Read-FileText $path) -split "\r?\n")) {
    $value = Parse-MenuPageSizeValue $line
    if (-not [string]::IsNullOrWhiteSpace($value)) {
      return (Normalize-PageSize $value)
    }
  }
  return 5
}

function Update-DefaultCustomSchemaAndPageSize {
  param(
    [string]$Content,
    [string]$SchemaId,
    [int]$PageSize
  )

  $SchemaId = Normalize-SchemaId $SchemaId
  $PageSize = Normalize-PageSize $PageSize
  $schemaLine = "    - schema: $SchemaId"
  $pageLine = '  "menu/page_size": ' + $PageSize

  if ([string]::IsNullOrWhiteSpace($Content)) {
    return ("patch:" + $newline + "  schema_list:" + $newline + $schemaLine + $newline + $pageLine + $newline)
  }

  $lines = [System.Collections.Generic.List[string]]::new()
  foreach ($line in ($Content -split "\r?\n")) {
    $lines.Add($line)
  }

  $foundPatch = $false
  $foundSchemaList = $false
  $schemaLineIndex = -1
  $pageLineIndex = -1

  for ($index = 0; $index -lt $lines.Count; $index++) {
    $trimmed = $lines[$index].Trim()
    if ($trimmed -eq "patch:") {
      $foundPatch = $true
    }
    if ($trimmed -eq "schema_list:") {
      $foundSchemaList = $true
    }
    if ($trimmed.StartsWith("- schema:")) {
      $schemaLineIndex = $index
    }
    if (-not [string]::IsNullOrWhiteSpace((Parse-MenuPageSizeValue $lines[$index]))) {
      $pageLineIndex = $index
    }
  }

  if ($pageLineIndex -ge 0) {
    $indent = ($lines[$pageLineIndex] -replace '^(\\s*).*$', '$1')
    $lines[$pageLineIndex] = ($indent + '"menu/page_size": ' + $PageSize)
  } else {
    if (-not $foundPatch) {
      if ($lines.Count -gt 0 -and -not [string]::IsNullOrWhiteSpace($lines[$lines.Count - 1])) {
        $lines.Add("")
      }
      $lines.Add("patch:")
      $foundPatch = $true
    }
    if (-not $foundSchemaList) {
      $insertAt = $lines.IndexOf("patch:") + 1
      if ($insertAt -lt 0) { $insertAt = $lines.Count }
      $lines.Insert($insertAt, $pageLine)
      $lines.Insert($insertAt, "  schema_list:")
      $lines.Insert($insertAt + 1, $schemaLine)
      return (([string]::Join($newline, $lines)).TrimEnd() + $newline)
    }
    $insertAt = $lines.IndexOf("patch:") + 1
    if ($schemaLineIndex -ge 0) {
      $insertAt = $schemaLineIndex + 1
    }
    if ($insertAt -lt 0) { $insertAt = $lines.Count }
    $lines.Insert($insertAt, $pageLine)
  }

  if ($schemaLineIndex -ge 0) {
    $indent = ($lines[$schemaLineIndex] -replace '^(\\s*).*$', '$1')
    $lines[$schemaLineIndex] = ($indent + "- schema: " + $SchemaId)
  } else {
    if (-not $foundPatch) {
      if ($lines.Count -gt 0 -and -not [string]::IsNullOrWhiteSpace($lines[$lines.Count - 1])) {
        $lines.Add("")
      }
      $lines.Add("patch:")
      $foundPatch = $true
    }
    $schemaListIndex = -1
    for ($index = 0; $index -lt $lines.Count; $index++) {
      if ($lines[$index].Trim() -eq "schema_list:") {
        $schemaListIndex = $index
        break
      }
    }
    if ($schemaListIndex -ge 0) {
      $lines.Insert($schemaListIndex + 1, $schemaLine)
    } else {
      $patchIndex = $lines.IndexOf("patch:")
      $insertAt = $patchIndex + 1
      if ($insertAt -lt 0) { $insertAt = $lines.Count }
      $lines.Insert($insertAt, "  schema_list:")
      $lines.Insert($insertAt + 1, $schemaLine)
    }
  }

  return (([string]::Join($newline, $lines)).TrimEnd() + $newline)
}

function Update-UserYamlSelectedSchema {
  param(
    [string]$Content,
    [string]$SchemaId
  )

  $SchemaId = Normalize-SchemaId $SchemaId
  if ([string]::IsNullOrWhiteSpace($Content)) {
    return ("var:" + $newline + "  previously_selected_schema: " + $SchemaId + $newline)
  }

  $lines = [System.Collections.Generic.List[string]]::new()
  foreach ($line in ($Content -split "\r?\n")) {
    $lines.Add($line)
  }
  $foundVar = $false
  $updated = $false
  for ($index = 0; $index -lt $lines.Count; $index++) {
    $trimmed = $lines[$index].Trim()
    if ($trimmed -eq "var:") {
      $foundVar = $true
    }
    if ($trimmed.StartsWith("previously_selected_schema:")) {
      $indent = ($lines[$index] -replace '^(\\s*).*$', '$1')
      $lines[$index] = ($indent + "previously_selected_schema: " + $SchemaId)
      $updated = $true
    }
  }
  if (-not $updated) {
    if (-not $foundVar) {
      if ($lines.Count -gt 0 -and -not [string]::IsNullOrWhiteSpace($lines[$lines.Count - 1])) {
        $lines.Add("")
      }
      $lines.Add("var:")
    }
    $varIndex = $lines.IndexOf("var:")
    $insertAt = $varIndex + 1
    if ($insertAt -lt 0) { $insertAt = $lines.Count }
    $lines.Insert($insertAt, "  previously_selected_schema: " + $SchemaId)
  }
  return (([string]::Join($newline, $lines)).TrimEnd() + $newline)
}

function Read-StandaloneSettingsState {
  $path = Get-StandaloneSettingsStatePath
  if (-not (Test-Path -LiteralPath $path)) {
    return [pscustomobject]@{
      reverse_lookup_display_mode = "key_sequence"
      candidate_layout = "vertical"
    }
  }
  try {
    $state = Get-Content -LiteralPath $path -Raw -Encoding UTF8 | ConvertFrom-Json
  } catch {
    return [pscustomobject]@{
      reverse_lookup_display_mode = "key_sequence"
      candidate_layout = "vertical"
    }
  }
  return [pscustomobject]@{
    reverse_lookup_display_mode = (Normalize-ReverseLookupMode $state.reverse_lookup_display_mode)
    candidate_layout = (Normalize-CandidateLayout $state.candidate_layout)
  }
}

function Write-StandaloneSettingsState {
  param(
    [string]$ReverseLookupMode,
    [string]$CandidateLayout
  )

  $payload = [ordered]@{
    reverse_lookup_display_mode = (Normalize-ReverseLookupMode $ReverseLookupMode)
    candidate_layout = (Normalize-CandidateLayout $CandidateLayout)
  }
  $json = $payload | ConvertTo-Json
  Write-Utf8NoBom -Path (Get-StandaloneSettingsStatePath) -Text $json
}

function Get-CurrentSettings {
  $state = Read-StandaloneSettingsState
  return [pscustomobject]@{
    SchemaId = (Read-ConfiguredSchema)
    PageSize = (Read-ConfiguredPageSize)
    ReverseLookupMode = $state.reverse_lookup_display_mode
    CandidateLayout = $state.candidate_layout
    DeployerPath = (Get-DeployerPath)
  }
}

function Build-SettingsSummary {
  param($Settings)
  $schemaLabel = switch ($Settings.SchemaId) {
    "yime_full" { "绛夐暱" }
    "yime_shorthand" { "鐪侀敭" }
    default { "鍙橀暱" }
  }
  $reverseLookupLabel = switch ($Settings.ReverseLookupMode) {
    "hidden" { "闅愯棌缂栫爜" }
    "standard_pinyin" { "鏍囧噯鎷奸煶" }
    "yime_pinyin" { "闊冲厓鎷奸煶" }
    default { "閿綅搴忓垪" }
  }
  $layoutLabel = switch ($Settings.CandidateLayout) {
    "horizontal" { "妯帓" }
    default { "绔栨帓" }
  }
  return ("褰撳墠璁剧疆锛氭柟妗?{0}锛屽€欓€夐」鏁?{1}锛屽弽鏌ユ樉绀?{2}锛屽€欓€夋帓鍒?{3}" -f $schemaLabel, $Settings.PageSize, $reverseLookupLabel, $layoutLabel)
}

function Invoke-RimeBuild {
  $deployer = Get-DeployerPath
  if ([string]::IsNullOrWhiteSpace($deployer)) {
    throw "No rime_deployer.exe was found for this runtime."
  }
  $buildDir = Join-Path $UserDir "build"
  $argumentList = @("--build", $UserDir, $SharedDir, $buildDir)
  $process = Start-Process -FilePath $deployer -ArgumentList $argumentList -Wait -PassThru -WindowStyle Hidden
  if ($process.ExitCode -ne 0) {
    throw ("rime_deployer.exe exited with code " + $process.ExitCode)
  }
}

function Apply-Settings {
  param([bool]$RunBuildAfterApply)

  if ([string]::IsNullOrWhiteSpace($UserDir) -or [string]::IsNullOrWhiteSpace($SharedDir)) {
    throw "UserDir or SharedDir is empty."
  }
  [void](New-Item -ItemType Directory -Path $UserDir -Force)

  $selectedSchemaId = Normalize-SchemaId ([string]$schemaComboBox.SelectedValue)
  if ($selectedSchemaId -eq "yime_shorthand" -and -not (Test-Path -LiteralPath (Join-Path $SharedDir "yime_shorthand.schema.yaml"))) {
    throw "The shorthand schema is not bundled in the current shared data."
  }
  $selectedPageSize = Normalize-PageSize ([string]$pageSizeComboBox.SelectedItem)
  $selectedReverseLookupMode = Normalize-ReverseLookupMode ([string]$reverseLookupComboBox.SelectedValue)
  $selectedCandidateLayout = Normalize-CandidateLayout ([string]$candidateLayoutComboBox.SelectedValue)

  $defaultCustomPath = Get-DefaultCustomPath
  $userYamlPath = Get-UserYamlPath
  $updatedDefaultCustom = Update-DefaultCustomSchemaAndPageSize (Read-FileText $defaultCustomPath) $selectedSchemaId $selectedPageSize
  $updatedUserYaml = Update-UserYamlSelectedSchema (Read-FileText $userYamlPath) $selectedSchemaId

  Write-Utf8NoBom -Path $defaultCustomPath -Text $updatedDefaultCustom
  Write-Utf8NoBom -Path $userYamlPath -Text $updatedUserYaml
  Write-StandaloneSettingsState -ReverseLookupMode $selectedReverseLookupMode -CandidateLayout $selectedCandidateLayout

  if ($RunBuildAfterApply) {
    Invoke-RimeBuild
  }

  $settings = Get-CurrentSettings
  $summaryLabel.Text = Build-SettingsSummary $settings
  $statusLabel.Text = $(if ($RunBuildAfterApply) {
    "宸插啓鍏ヨ缃苟鎵ц鏋勫缓銆傚垏鍥為煶鍏冩嫾闊冲悗浼氬湪閲嶆柊婵€娲绘椂鍚屾銆?
  } else {
    "宸插啓鍏ヨ缃€傚垏鍥為煶鍏冩嫾闊冲悗浼氬湪閲嶆柊婵€娲绘椂鍚屾锛涘闇€绔嬪嵆閲嶇紪璇戝彲鍐嶇偣 \"Apply and rebuild\"銆?
  })
}

$form = New-Object System.Windows.Forms.Form
$form.Text = "Yime Settings"
$form.StartPosition = "CenterScreen"
$form.Size = New-Object System.Drawing.Size(820, 680)
$form.MinimumSize = New-Object System.Drawing.Size(820, 680)
$form.MaximizeBox = $false
$form.WindowState = [System.Windows.Forms.FormWindowState]::Normal
$form.Add_Shown({
  $form.WindowState = [System.Windows.Forms.FormWindowState]::Normal
  $screenBounds = [System.Windows.Forms.Screen]::PrimaryScreen.WorkingArea
  $x = $screenBounds.Left + [int](($screenBounds.Width - $form.Width) / 2)
  $y = $screenBounds.Top + [int](($screenBounds.Height - $form.Height) / 2)
  if ($x -lt $screenBounds.Left) { $x = $screenBounds.Left }
  if ($y -lt $screenBounds.Top) { $y = $screenBounds.Top }
  $form.Location = New-Object System.Drawing.Point($x, $y)
})

$title = New-Object System.Windows.Forms.Label
$title.Left = 16
$title.Top = 16
$title.Width = 760
$title.Height = 26
$title.Font = New-Object System.Drawing.Font("Microsoft YaHei UI", 12, [System.Drawing.FontStyle]::Bold)
$title.Text = "Yime settings panel"
$form.Controls.Add($title)

$summary = New-Object System.Windows.Forms.Label
$summary.Left = 16
$summary.Top = 48
$summary.Width = 770
$summary.Height = 44
$summary.Text = "This panel keeps settings-oriented work out of the TSF callback path. It writes the same runtime files Yime already uses, and standalone-only UI preferences are applied when you switch back to Yime."
$form.Controls.Add($summary)

$settingsGroup = New-Object System.Windows.Forms.GroupBox
$settingsGroup.Left = 16
$settingsGroup.Top = 104
$settingsGroup.Width = 770
$settingsGroup.Height = 224
$settingsGroup.Text = "Active settings"
$form.Controls.Add($settingsGroup)

$schemaLabel = New-Object System.Windows.Forms.Label
$schemaLabel.Left = 20
$schemaLabel.Top = 34
$schemaLabel.Width = 120
$schemaLabel.Text = "Schema"
$settingsGroup.Controls.Add($schemaLabel)

$schemaComboBox = New-Object System.Windows.Forms.ComboBox
$schemaComboBox.Left = 144
$schemaComboBox.Top = 30
$schemaComboBox.Width = 180
$schemaComboBox.DropDownStyle = [System.Windows.Forms.ComboBoxStyle]::DropDownList
$schemaComboBox.DisplayMember = "Label"
$schemaComboBox.ValueMember = "Id"
foreach ($option in (Get-AvailableSchemaOptions)) {
  [void]$schemaComboBox.Items.Add($option)
}
$settingsGroup.Controls.Add($schemaComboBox)

$schemaHintLabel = New-Object System.Windows.Forms.Label
$schemaHintLabel.Left = 346
$schemaHintLabel.Top = 34
$schemaHintLabel.Width = 390
$schemaHintLabel.Height = 40
$schemaHintLabel.Text = "Shorthand remains unavailable unless its schema file is bundled in the installed shared data."
$settingsGroup.Controls.Add($schemaHintLabel)

$pageSizeLabel = New-Object System.Windows.Forms.Label
$pageSizeLabel.Left = 20
$pageSizeLabel.Top = 84
$pageSizeLabel.Width = 120
$pageSizeLabel.Text = "Candidates / page"
$settingsGroup.Controls.Add($pageSizeLabel)

$pageSizeComboBox = New-Object System.Windows.Forms.ComboBox
$pageSizeComboBox.Left = 144
$pageSizeComboBox.Top = 80
$pageSizeComboBox.Width = 180
$pageSizeComboBox.DropDownStyle = [System.Windows.Forms.ComboBoxStyle]::DropDownList
foreach ($size in 5..9) {
  [void]$pageSizeComboBox.Items.Add([string]$size)
}
$settingsGroup.Controls.Add($pageSizeComboBox)

$pageSizeHintLabel = New-Object System.Windows.Forms.Label
$pageSizeHintLabel.Left = 346
$pageSizeHintLabel.Top = 84
$pageSizeHintLabel.Width = 390
$pageSizeHintLabel.Height = 36
$pageSizeHintLabel.Text = "This writes %APPDATA%\PIME\Rime\default.custom.yaml. Use Apply and rebuild when you want schema and page-size changes compiled into the next runtime session."
$settingsGroup.Controls.Add($pageSizeHintLabel)

$reverseLookupLabel = New-Object System.Windows.Forms.Label
$reverseLookupLabel.Left = 20
$reverseLookupLabel.Top = 132
$reverseLookupLabel.Width = 120
$reverseLookupLabel.Text = "Reverse lookup"
$settingsGroup.Controls.Add($reverseLookupLabel)

$reverseLookupComboBox = New-Object System.Windows.Forms.ComboBox
$reverseLookupComboBox.Left = 144
$reverseLookupComboBox.Top = 128
$reverseLookupComboBox.Width = 180
$reverseLookupComboBox.DropDownStyle = [System.Windows.Forms.ComboBoxStyle]::DropDownList
[void]$reverseLookupComboBox.Items.Add([pscustomobject]@{ Label = "闅愯棌缂栫爜"; Value = "hidden" })
[void]$reverseLookupComboBox.Items.Add([pscustomobject]@{ Label = "鏍囧噯鎷奸煶"; Value = "standard_pinyin" })
[void]$reverseLookupComboBox.Items.Add([pscustomobject]@{ Label = "闊冲厓鎷奸煶"; Value = "yime_pinyin" })
[void]$reverseLookupComboBox.Items.Add([pscustomobject]@{ Label = "閿綅搴忓垪"; Value = "key_sequence" })
$reverseLookupComboBox.DisplayMember = "Label"
$reverseLookupComboBox.ValueMember = "Value"
$settingsGroup.Controls.Add($reverseLookupComboBox)

$reverseLookupHintLabel = New-Object System.Windows.Forms.Label
$reverseLookupHintLabel.Left = 346
$reverseLookupHintLabel.Top = 132
$reverseLookupHintLabel.Width = 390
$reverseLookupHintLabel.Height = 36
$reverseLookupHintLabel.Text = "This is persisted in yime_settings_state.json so Yime can apply it again when the IME is reactivated."
$settingsGroup.Controls.Add($reverseLookupHintLabel)

$candidateLayoutLabel = New-Object System.Windows.Forms.Label
$candidateLayoutLabel.Left = 20
$candidateLayoutLabel.Top = 180
$candidateLayoutLabel.Width = 120
$candidateLayoutLabel.Text = "Candidate layout"
$settingsGroup.Controls.Add($candidateLayoutLabel)

$candidateLayoutComboBox = New-Object System.Windows.Forms.ComboBox
$candidateLayoutComboBox.Left = 144
$candidateLayoutComboBox.Top = 176
$candidateLayoutComboBox.Width = 180
$candidateLayoutComboBox.DropDownStyle = [System.Windows.Forms.ComboBoxStyle]::DropDownList
[void]$candidateLayoutComboBox.Items.Add([pscustomobject]@{ Label = "绔栨帓"; Value = "vertical" })
[void]$candidateLayoutComboBox.Items.Add([pscustomobject]@{ Label = "妯帓"; Value = "horizontal" })
$candidateLayoutComboBox.DisplayMember = "Label"
$candidateLayoutComboBox.ValueMember = "Value"
$settingsGroup.Controls.Add($candidateLayoutComboBox)

$candidateLayoutHintLabel = New-Object System.Windows.Forms.Label
$candidateLayoutHintLabel.Left = 346
$candidateLayoutHintLabel.Top = 180
$candidateLayoutHintLabel.Width = 390
$candidateLayoutHintLabel.Height = 36
$candidateLayoutHintLabel.Text = "Layout preference is stored separately from Rime config so Yime can restore it without adding more menu work back into TSF."
$settingsGroup.Controls.Add($candidateLayoutHintLabel)

$actionsGroup = New-Object System.Windows.Forms.GroupBox
$actionsGroup.Left = 16
$actionsGroup.Top = 342
$actionsGroup.Width = 770
$actionsGroup.Height = 132
$actionsGroup.Text = "Apply and maintenance"
$form.Controls.Add($actionsGroup)

$applyButton = New-Object System.Windows.Forms.Button
$applyButton.Left = 20
$applyButton.Top = 28
$applyButton.Width = 160
$applyButton.Height = 34
$applyButton.Text = "Apply settings"
$actionsGroup.Controls.Add($applyButton)

$applyAndRebuildButton = New-Object System.Windows.Forms.Button
$applyAndRebuildButton.Left = 194
$applyAndRebuildButton.Top = 28
$applyAndRebuildButton.Width = 180
$applyAndRebuildButton.Height = 34
$applyAndRebuildButton.Text = "Apply and rebuild"
$actionsGroup.Controls.Add($applyAndRebuildButton)

$rebuildOnlyButton = New-Object System.Windows.Forms.Button
$rebuildOnlyButton.Left = 388
$rebuildOnlyButton.Top = 28
$rebuildOnlyButton.Width = 132
$rebuildOnlyButton.Height = 34
$rebuildOnlyButton.Text = "Rebuild now"
$actionsGroup.Controls.Add($rebuildOnlyButton)

$refreshButton = New-Object System.Windows.Forms.Button
$refreshButton.Left = 534
$refreshButton.Top = 28
$refreshButton.Width = 100
$refreshButton.Height = 34
$refreshButton.Text = "Refresh"
$actionsGroup.Controls.Add($refreshButton)

$copySummaryButton = New-Object System.Windows.Forms.Button
$copySummaryButton.Left = 648
$copySummaryButton.Top = 28
$copySummaryButton.Width = 100
$copySummaryButton.Height = 34
$copySummaryButton.Text = "Copy summary"
$actionsGroup.Controls.Add($copySummaryButton)

$applyHintLabel = New-Object System.Windows.Forms.Label
$applyHintLabel.Left = 20
$applyHintLabel.Top = 76
$applyHintLabel.Width = 720
$applyHintLabel.Height = 42
$applyHintLabel.Text = "Apply writes default.custom.yaml, user.yaml, and yime_settings_state.json. Switching back to Yime restores reverse-lookup and layout preferences on activation; use Apply and rebuild for schema or page-size changes."
$actionsGroup.Controls.Add($applyHintLabel)

$pathsGroup = New-Object System.Windows.Forms.GroupBox
$pathsGroup.Left = 16
$pathsGroup.Top = 488
$pathsGroup.Width = 770
$pathsGroup.Height = 132
$pathsGroup.Text = "Data and docs"
$form.Controls.Add($pathsGroup)

$pathButtons = @(
  @{ Left = 20; Text = "User data"; Target = $UserDir },
  @{ Left = 142; Text = "Shared data"; Target = $SharedDir },
  @{ Left = 264; Text = "Log dir"; Target = $LogDir },
  @{ Left = 386; Text = "Sync dir"; Target = (Get-SyncDir) },
  @{ Left = 508; Text = "Settings guide"; Target = (Join-Path $HelpDir "settings-and-data.html") },
  @{ Left = 630; Text = "Main help"; Target = (Join-Path $HelpDir "README.html") }
)

foreach ($pathButtonInfo in $pathButtons) {
  $button = New-Object System.Windows.Forms.Button
  $button.Left = [int]$pathButtonInfo.Left
  $button.Top = 28
  $button.Width = 108
  $button.Height = 34
  $button.Text = [string]$pathButtonInfo.Text
  $button.Tag = [string]$pathButtonInfo.Target
  $button.Add_Click({ param($sender, $eventArgs) Open-Path $sender.Tag })
  $pathsGroup.Controls.Add($button)
}

$configFilesButton = New-Object System.Windows.Forms.Button
$configFilesButton.Left = 20
$configFilesButton.Top = 76
$configFilesButton.Width = 160
$configFilesButton.Height = 30
$configFilesButton.Text = "Open current config file"
$pathsGroup.Controls.Add($configFilesButton)

$configFilesHintLabel = New-Object System.Windows.Forms.Label
$configFilesHintLabel.Left = 194
$configFilesHintLabel.Top = 82
$configFilesHintLabel.Width = 550
$configFilesHintLabel.Height = 24
$configFilesHintLabel.Text = "Opens default.custom.yaml when it exists, otherwise opens the user data directory."
$pathsGroup.Controls.Add($configFilesHintLabel)

$summaryLabel = New-Object System.Windows.Forms.Label
$summaryLabel.Left = 16
$summaryLabel.Top = 630
$summaryLabel.Width = 770
$summaryLabel.Height = 22
$summaryLabel.Text = ""
$form.Controls.Add($summaryLabel)

$statusLabel = New-Object System.Windows.Forms.Label
$statusLabel.Left = 16
$statusLabel.Top = 652
$statusLabel.Width = 770
$statusLabel.Height = 22
$statusLabel.Text = "Ready."
$form.Controls.Add($statusLabel)

function Refresh-SettingsView {
  $settings = Get-CurrentSettings
  foreach ($option in $schemaComboBox.Items) {
    if ($option.Id -eq $settings.SchemaId) {
      $schemaComboBox.SelectedItem = $option
      break
    }
  }
  $pageSizeComboBox.SelectedItem = [string]$settings.PageSize
  foreach ($option in $reverseLookupComboBox.Items) {
    if ($option.Value -eq $settings.ReverseLookupMode) {
      $reverseLookupComboBox.SelectedItem = $option
      break
    }
  }
  foreach ($option in $candidateLayoutComboBox.Items) {
    if ($option.Value -eq $settings.CandidateLayout) {
      $candidateLayoutComboBox.SelectedItem = $option
      break
    }
  }
  $summaryLabel.Text = Build-SettingsSummary $settings
  if ([string]::IsNullOrWhiteSpace($settings.DeployerPath)) {
    $applyAndRebuildButton.Enabled = $false
    $rebuildOnlyButton.Enabled = $false
    $statusLabel.Text = "Ready. No rime_deployer.exe was found; Apply settings still writes the files."
  } else {
    $applyAndRebuildButton.Enabled = $true
    $rebuildOnlyButton.Enabled = $true
    $statusLabel.Text = "Ready. Apply writes files; Apply and rebuild also runs rime_deployer.exe."
  }
}

$applyButton.Add_Click({
  try {
    Apply-Settings $false
  } catch {
    Show-Error $_.Exception.Message
  }
})

$applyAndRebuildButton.Add_Click({
  try {
    Apply-Settings $true
  } catch {
    Show-Error $_.Exception.Message
  }
})

$rebuildOnlyButton.Add_Click({
  try {
    Invoke-RimeBuild
    $statusLabel.Text = "宸叉墽琛?rime_deployer 鏋勫缓銆傚垏鍥為煶鍏冩嫾闊冲悗濡備粛涓嶄竴鑷达紝鍐嶉噸寮€ PIMELauncher銆?
  } catch {
    Show-Error $_.Exception.Message
  }
})

$refreshButton.Add_Click({
  try {
    Refresh-SettingsView
  } catch {
    Show-Error $_.Exception.Message
  }
})

$copySummaryButton.Add_Click({
  try {
    [System.Windows.Forms.Clipboard]::SetText(($summaryLabel.Text + [Environment]::NewLine + $statusLabel.Text))
    $statusLabel.Text = "宸插鍒惰缃憳瑕併€?
  } catch {
    Show-Error $_.Exception.Message
  }
})

$configFilesButton.Add_Click({
  try {
    $defaultCustomPath = Get-DefaultCustomPath
    if (Test-Path -LiteralPath $defaultCustomPath) {
      Open-Path $defaultCustomPath
    } else {
      Open-Path $UserDir
    }
  } catch {
    Show-Error $_.Exception.Message
  }
})

try {
  Refresh-SettingsView
  [void]$form.ShowDialog()
} catch {
  Show-Error $_.Exception.Message
}
`
