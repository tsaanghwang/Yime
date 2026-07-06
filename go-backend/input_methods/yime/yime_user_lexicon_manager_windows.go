//go:build windows

package yime

import (
	"os"
	"path/filepath"
)

func (ime *IME) startUserLexiconManagerHelper(mode string) error {
	userDir := ime.userDir()
	sharedDir := ime.sharedDir()
	if userDir == "" || sharedDir == "" {
		return os.ErrNotExist
	}
	scriptPath, err := ime.ensureUserLexiconManagerScript()
	if err != nil {
		return err
	}
	return startDetachedUIPowerShell(
		"-NoProfile",
		"-STA",
		"-WindowStyle",
		"Hidden",
		"-ExecutionPolicy",
		"Bypass",
		"-File",
		scriptPath,
		"-SharedDir",
		sharedDir,
		"-UserDir",
		userDir,
		"-Mode",
		mode,
	)
}

func (ime *IME) ensureUserLexiconManagerScript() (string, error) {
	userDir := ime.userDir()
	if userDir == "" {
		return "", os.ErrNotExist
	}
	if err := os.MkdirAll(userDir, 0o755); err != nil {
		return "", err
	}
	scriptPath := filepath.Join(userDir, "pime_yime_lexicon_manager.ps1")
	scriptContent := append([]byte{0xEF, 0xBB, 0xBF}, []byte(userLexiconManagerScript)...)
	if err := os.WriteFile(scriptPath, scriptContent, 0o644); err != nil {
		return "", err
	}
	return scriptPath, nil
}

const userLexiconManagerScript = `param(
  [string]$SharedDir,
  [string]$UserDir,
  [ValidateSet("full", "variable", "shorthand")]
  [string]$Mode = "variable"
)

$ErrorActionPreference = "Stop"
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[System.Windows.Forms.Application]::EnableVisualStyles()

function Show-Error {
  param([string]$Message)
  [System.Windows.Forms.MessageBox]::Show($Message, "词库管理", "OK", "Error") | Out-Null
}

function Show-Info {
  param([string]$Message)
  [System.Windows.Forms.MessageBox]::Show($Message, "词库管理", "OK", "Information") | Out-Null
}

function Normalize-Pinyin {
  param([string]$Value)
  return $Value.Trim().ToLowerInvariant().Replace("u:", "ü").Replace("v", "ü")
}

function Split-CompactNumericPinyinToken {
  param([string]$Token)
  $tokenText = $Token.Trim()
  if ([string]::IsNullOrWhiteSpace($tokenText)) { return @() }

  $parts = New-Object System.Collections.Generic.List[string]
  $start = 0
  $sawToneDigit = $false
  for ($index = 0; $index -lt $tokenText.Length; $index++) {
    $char = $tokenText[$index]
    if ($char -notin @('1', '2', '3', '4', '5')) { continue }
    $sawToneDigit = $true
    if ($index -eq $start) { return @($tokenText) }
    $parts.Add($tokenText.Substring($start, $index - $start + 1))
    $start = $index + 1
  }
  if (-not $sawToneDigit -or $start -ne $tokenText.Length) { return @($tokenText) }
  return $parts.ToArray()
}

function Normalize-PinyinSpacing {
  param([string]$Value)
  $parts = New-Object System.Collections.Generic.List[string]
  foreach ($token in ($Value -split "\s+")) {
    if ([string]::IsNullOrWhiteSpace($token)) { continue }
    foreach ($part in (Split-CompactNumericPinyinToken $token)) {
      $normalized = Normalize-Pinyin $part
      if (-not [string]::IsNullOrWhiteSpace($normalized)) { $parts.Add($normalized) }
    }
  }
  return ($parts.ToArray() -join " ")
}

function Assert-NumericPinyin {
  param([string[]]$Parts)
  foreach ($part in $Parts) {
    if ($part -notmatch '^[a-zü]+[1-5]$') {
      throw "数字标调拼音格式错误：$part。请使用 zhong1 guo2 或 zhong1guo2 这样的格式。"
    }
  }
}

function Load-CodeMap {
  param([string]$Path)
  if (-not (Test-Path -LiteralPath $Path)) { throw "找不到拼音编码表：$Path" }
  $map = @{}
  $lines = Get-Content -LiteralPath $Path -Encoding UTF8
  foreach ($line in $lines | Select-Object -Skip 1) {
    if ([string]::IsNullOrWhiteSpace($line)) { continue }
    $fields = $line -split ([string][char]9)
    if ($fields.Count -ne 4) { continue }
    $key = Normalize-Pinyin $fields[0]
    $record = @{
      full = $fields[1]
      variable = $fields[2]
      shorthand = $fields[3]
    }
    $map[$key] = $record
    if ($key.Contains("ü")) {
      $map[$key.Replace("ü", "v")] = $record
      $map[$key.Replace("ü", "u:")] = $record
    }
  }
  return $map
}

function Convert-PinyinToCode {
  param(
    [hashtable]$CodeMap,
    [string]$Pinyin,
    [string]$Mode
  )
  $normalized = Normalize-PinyinSpacing $Pinyin
  if ([string]::IsNullOrWhiteSpace($normalized)) { throw "数字标调拼音不能为空。" }
  $parts = @($normalized -split "\s+")
  Assert-NumericPinyin $parts

  $builder = New-Object System.Text.StringBuilder
  foreach ($item in $parts) {
    if (-not $CodeMap.ContainsKey($item)) {
      throw "找不到拼音：$item。请检查拼音和声调数字。"
    }
    [void]$builder.Append($CodeMap[$item][$Mode])
  }
  $code = $builder.ToString()
  if ([string]::IsNullOrWhiteSpace($code)) { throw "拼音未生成有效音元编码。" }
  return @{ pinyin = $normalized; code = $code; syllables = $parts.Count }
}

function Ensure-SourceFile {
  param([string]$Path)
  if (Test-Path -LiteralPath $Path) { return }
  Set-Content -LiteralPath $Path -Encoding UTF8 -Value @(
    "# PIME Yime user phrases",
    "# format: phrase<TAB>numeric-tone-pinyin<TAB>weight",
    "# example: 中国" + [char]9 + "zhong1 guo2" + [char]9 + "1000000"
  )
}

function Load-SourceEntries {
  param([string]$Path)
  Ensure-SourceFile $Path
  $entries = New-Object System.Collections.Generic.List[object]
  $lineNumber = 0
  foreach ($line in (Get-Content -LiteralPath $Path -Encoding UTF8)) {
    $lineNumber++
    if ([string]::IsNullOrWhiteSpace($line) -or $line.TrimStart().StartsWith("#")) { continue }
    $fields = $line -split ([string][char]9)
    if ($fields.Count -lt 2) { throw "用户词库第 $lineNumber 行格式应为：词条<TAB>数字标调拼音<TAB>权重。" }
    $phrase = $fields[0].Trim()
    $pinyin = Normalize-PinyinSpacing $fields[1]
    $weight = "1000000"
    if ($fields.Count -ge 3 -and -not [string]::IsNullOrWhiteSpace($fields[2])) { $weight = $fields[2].Trim() }
    if ([string]::IsNullOrWhiteSpace($phrase) -or [string]::IsNullOrWhiteSpace($pinyin)) {
      throw "用户词库第 $lineNumber 行词条和数字标调拼音不能为空。"
    }
    if ($weight -notmatch '^\d+$') { throw "用户词库第 $lineNumber 行权重必须是整数。" }
    $entries.Add([pscustomobject]@{
      Phrase = $phrase
      Pinyin = $pinyin
      Weight = $weight
    })
  }
  return $entries
}

function Write-SourceEntries {
  param(
    [string]$Path,
    [System.Collections.IEnumerable]$Entries
  )
  $output = New-Object System.Collections.Generic.List[string]
  $output.Add("# PIME Yime user phrases")
  $output.Add("# format: phrase<TAB>numeric-tone-pinyin<TAB>weight")
  $output.Add("# example: 中国" + [char]9 + "zhong1 guo2" + [char]9 + "1000000")
  foreach ($entry in $Entries) {
    $output.Add($entry.Phrase + [char]9 + $entry.Pinyin + [char]9 + $entry.Weight)
  }
  Set-Content -LiteralPath $Path -Encoding UTF8 -Value $output.ToArray()
}

function Upsert-SourceEntry {
  param(
    [string]$Path,
    [pscustomobject]$Entry
  )
  $entries = @(Load-SourceEntries $Path)
  $result = New-Object System.Collections.Generic.List[object]
  $replaced = $false
  foreach ($existing in $entries) {
    if ($existing.Phrase -eq $Entry.Phrase) {
      if (-not $replaced) {
        $result.Add($Entry)
        $replaced = $true
      }
      continue
    }
    $result.Add($existing)
  }
  if (-not $replaced) { $result.Add($Entry) }
  Write-SourceEntries $Path $result
  return $(if ($replaced) { "updated" } else { "inserted" })
}

function Remove-SourceEntry {
  param(
    [string]$Path,
    [string]$Phrase
  )
  $entries = @(Load-SourceEntries $Path)
  $result = New-Object System.Collections.Generic.List[object]
  $removed = $false
  foreach ($entry in $entries) {
    if ($entry.Phrase -eq $Phrase) {
      $removed = $true
      continue
    }
    $result.Add($entry)
  }
  if (-not $removed) { return $false }
  Write-SourceEntries $Path $result
  return $true
}

function Validate-EntryForCurrentMode {
  param(
    [hashtable]$CodeMap,
    [pscustomobject]$Entry
  )
  $converted = Convert-PinyinToCode $CodeMap $Entry.Pinyin $Mode
  $textElements = [System.Globalization.StringInfo]::ParseCombiningCharacters($Entry.Phrase).Count
  if ($textElements -ne $converted.syllables) {
    throw "词条字数（$textElements）和拼音音节数（$($converted.syllables)）不一致。"
  }
  return $converted
}

function Rebuild-RimeLexicon {
  param(
    [string]$SourcePath,
    [string]$TargetPath,
    [hashtable]$CodeMap,
    [string]$Mode
  )
  $entries = @(Load-SourceEntries $SourcePath)
  $output = New-Object System.Collections.Generic.List[string]
  $output.Add("# Generated by PIME Yime from yime_user_phrases.txt")
  $output.Add("# format: phrase<TAB>code<TAB>weight")

  foreach ($entry in $entries) {
    $converted = Convert-PinyinToCode $CodeMap $entry.Pinyin $Mode
    $output.Add($entry.Phrase + [char]9 + $converted.code + [char]9 + $entry.Weight)
  }
  Set-Content -LiteralPath $TargetPath -Encoding UTF8 -Value $output.ToArray()
}

function Show-EntryDialog {
  param(
    [string]$Phrase = "",
    [string]$Pinyin = "",
    [string]$Weight = "1000000",
    [string]$DialogTitle = "",
    [string]$OkText = ""
  )

  if ([string]::IsNullOrWhiteSpace($Phrase)) {
    try {
      $Phrase = [System.Windows.Forms.Clipboard]::GetText().Trim()
    } catch {}
  }

  if ([string]::IsNullOrWhiteSpace($DialogTitle)) {
    $DialogTitle = "添加用户词条"
  }
  if ([string]::IsNullOrWhiteSpace($OkText)) {
    $OkText = "保存"
  }

  $dialog = New-Object System.Windows.Forms.Form
  $dialog.Text = "添加用户词条"
  $dialog.StartPosition = "CenterParent"
  $dialog.Width = 460
  $dialog.Height = 302
  $dialog.FormBorderStyle = "FixedDialog"
  $dialog.MaximizeBox = $false
  $dialog.MinimizeBox = $false

  $phraseLabel = New-Object System.Windows.Forms.Label
  $phraseLabel.Text = "词条汉字"
  $phraseLabel.Left = 16
  $phraseLabel.Top = 18
  $phraseLabel.Width = 400
  $dialog.Controls.Add($phraseLabel)

  $phraseBox = New-Object System.Windows.Forms.TextBox
  $phraseBox.Left = 16
  $phraseBox.Top = 40
  $phraseBox.Width = 410
  $phraseBox.Text = $Phrase
  $dialog.Controls.Add($phraseBox)

  $pinyinLabel = New-Object System.Windows.Forms.Label
  $pinyinLabel.Text = "数字标调拼音，例如 zhong1 guo2；也接受 zhong1guo2"
  $pinyinLabel.Left = 16
  $pinyinLabel.Top = 76
  $pinyinLabel.Width = 410
  $dialog.Controls.Add($pinyinLabel)

  $pinyinBox = New-Object System.Windows.Forms.TextBox
  $pinyinBox.Left = 16
  $pinyinBox.Top = 98
  $pinyinBox.Width = 410
  $pinyinBox.Text = $Pinyin
  $dialog.Controls.Add($pinyinBox)

  $weightLabel = New-Object System.Windows.Forms.Label
  $weightLabel.Text = "权重"
  $weightLabel.Left = 16
  $weightLabel.Top = 134
  $weightLabel.Width = 410
  $dialog.Controls.Add($weightLabel)

  $weightBox = New-Object System.Windows.Forms.TextBox
  $weightBox.Left = 16
  $weightBox.Top = 156
  $weightBox.Width = 410
  $weightBox.Text = $Weight
  $dialog.Controls.Add($weightBox)

  $okButton = New-Object System.Windows.Forms.Button
  $okButton.Text = "保存"
  $okButton.Left = 260
  $okButton.Top = 216
  $okButton.Width = 78
  $dialog.Controls.Add($okButton)

  $cancelButton = New-Object System.Windows.Forms.Button
  $cancelButton.Text = "取消"
  $cancelButton.Left = 348
  $cancelButton.Top = 216
  $cancelButton.Width = 78
  $cancelButton.DialogResult = [System.Windows.Forms.DialogResult]::Cancel
  $dialog.Controls.Add($cancelButton)

  $dialog.Text = $DialogTitle
  $okButton.Text = $OkText
  $dialog.CancelButton = $cancelButton

  $okButton.Add_Click({
    $phraseValue = $phraseBox.Text.Trim()
    $pinyinValue = Normalize-PinyinSpacing $pinyinBox.Text
    $weightValue = $(if ([string]::IsNullOrWhiteSpace($weightBox.Text)) { "1000000" } else { $weightBox.Text.Trim() })
    try {
      Assert-EntryFields ([pscustomobject]@{
        Phrase = $phraseValue
        Pinyin = $pinyinValue
        Weight = $weightValue
      })
      $dialog.DialogResult = [System.Windows.Forms.DialogResult]::OK
      $dialog.Close()
    } catch {
      Show-Error $_.Exception.Message
    }
  })

  $dialog.AcceptButton = $okButton

  $result = $dialog.ShowDialog()
  if ($result -ne [System.Windows.Forms.DialogResult]::OK) { return $null }
  return [pscustomobject]@{
    Phrase = $phraseBox.Text.Trim()
    Pinyin = Normalize-PinyinSpacing $pinyinBox.Text
    Weight = $(if ([string]::IsNullOrWhiteSpace($weightBox.Text)) { "1000000" } else { $weightBox.Text.Trim() })
  }
}

function Assert-EntryFields {
  param([pscustomobject]$Entry)

  if ($null -eq $Entry) {
    throw "未收到要保存的词条内容。"
  }
  if ([string]::IsNullOrWhiteSpace($Entry.Phrase)) {
    throw "请输入词条。"
  }
  if ([string]::IsNullOrWhiteSpace($Entry.Pinyin)) {
    throw "请输入数字标调拼音，例如 zhong1 guo2。"
  }
  if ([string]::IsNullOrWhiteSpace($Entry.Weight)) {
    throw "请输入权重。"
  }
  if ($Entry.Phrase -match '[\t\r\n]') {
    throw "词条不能包含制表符或换行。"
  }
  if ($Entry.Weight -notmatch '^\d+$') {
    throw "权重必须是整数。"
  }
}

$sourcePath = Join-Path $UserDir "yime_user_phrases.txt"
$rimeLexiconPath = Join-Path $UserDir "custom_phrase.txt"
$script:codeMap = @{}
$script:lexiconLoaded = $false

$form = New-Object System.Windows.Forms.Form
$form.Text = "词库管理"
$form.StartPosition = "CenterScreen"
$form.Width = 860
$form.Height = 560

$menu = New-Object System.Windows.Forms.MenuStrip
$fileMenu = New-Object System.Windows.Forms.ToolStripMenuItem("文件")
$actionMenu = New-Object System.Windows.Forms.ToolStripMenuItem("操作")
$menu.Items.Add($fileMenu) | Out-Null
$menu.Items.Add($actionMenu) | Out-Null
$form.MainMenuStrip = $menu
$form.Controls.Add($menu)

$toolbar = New-Object System.Windows.Forms.FlowLayoutPanel
$toolbar.Left = 12
$toolbar.Top = 36
$toolbar.Width = 820
$toolbar.Height = 40
$toolbar.WrapContents = $false
$toolbar.AutoScroll = $true
$form.Controls.Add($toolbar)

$modeLabel = New-Object System.Windows.Forms.Label
$modeLabel.Left = 12
$modeLabel.Top = 82
$modeLabel.Width = 820
$modeLabel.Text = "当前编码方案：$Mode"
$form.Controls.Add($modeLabel)

$workflowHintLabel = New-Object System.Windows.Forms.Label
$workflowHintLabel.Left = 12
$workflowHintLabel.Top = 104
$workflowHintLabel.Width = 820
$workflowHintLabel.Height = 28
$workflowHintLabel.Text = "在此管理用户词库：添加、编辑、搜索、导入/导出、应用与撤销。"
$form.Controls.Add($workflowHintLabel)

$searchLabel = New-Object System.Windows.Forms.Label
$searchLabel.Left = 12
$searchLabel.Top = 138
$searchLabel.Width = 96
$searchLabel.Text = "搜索"
$form.Controls.Add($searchLabel)

$searchBox = New-Object System.Windows.Forms.TextBox
$searchBox.Left = 110
$searchBox.Top = 134
$searchBox.Width = 560
$form.Controls.Add($searchBox)

$searchResetButton = New-Object System.Windows.Forms.Button
$searchResetButton.Left = 682
$searchResetButton.Top = 132
$searchResetButton.Width = 72
$searchResetButton.Height = 28
$searchResetButton.Text = "清空"
$form.Controls.Add($searchResetButton)

$sortLabel = New-Object System.Windows.Forms.Label
$sortLabel.Left = 12
$sortLabel.Top = 168
$sortLabel.Width = 72
$sortLabel.Text = "排序"
$form.Controls.Add($sortLabel)

$sortFieldComboBox = New-Object System.Windows.Forms.ComboBox
$sortFieldComboBox.Left = 84
$sortFieldComboBox.Top = 164
$sortFieldComboBox.Width = 150
$sortFieldComboBox.DropDownStyle = [System.Windows.Forms.ComboBoxStyle]::DropDownList
[void]$sortFieldComboBox.Items.Add("词条")
[void]$sortFieldComboBox.Items.Add("拼音")
[void]$sortFieldComboBox.Items.Add("权重")
$sortFieldComboBox.SelectedIndex = 0
$form.Controls.Add($sortFieldComboBox)

$sortDirectionButton = New-Object System.Windows.Forms.Button
$sortDirectionButton.Left = 244
$sortDirectionButton.Top = 162
$sortDirectionButton.Width = 88
$sortDirectionButton.Height = 28
$sortDirectionButton.Text = "升序"
$form.Controls.Add($sortDirectionButton)

$listView = New-Object System.Windows.Forms.ListView
$listView.Left = 12
$listView.Top = 200
$listView.Width = 580
$listView.Height = 264
$listView.View = [System.Windows.Forms.View]::Details
$listView.FullRowSelect = $true
$listView.GridLines = $true
$listView.MultiSelect = $true
$listView.HideSelection = $false
[void]$listView.Columns.Add("词条", 180)
[void]$listView.Columns.Add("数字标调拼音", 430)
[void]$listView.Columns.Add("权重", 120)
$form.Controls.Add($listView)

$statusLabel = New-Object System.Windows.Forms.Label
$statusLabel.Left = 12
$statusLabel.Top = 500
$statusLabel.Width = 820
$statusLabel.Height = 28
$statusLabel.Text = "就绪。"
$form.Controls.Add($statusLabel)

$summaryLabel = New-Object System.Windows.Forms.Label
$summaryLabel.Left = 12
$summaryLabel.Top = 468
$summaryLabel.Width = 820
$summaryLabel.Height = 32
$summaryLabel.Text = ""
$form.Controls.Add($summaryLabel)

$selectionLabel = New-Object System.Windows.Forms.Label
$selectionLabel.Left = 340
$selectionLabel.Top = 168
$selectionLabel.Width = 252
$selectionLabel.Height = 24
$selectionLabel.Text = ""
$form.Controls.Add($selectionLabel)

$historyLabel = New-Object System.Windows.Forms.Label
$historyLabel.Left = 600
$historyLabel.Top = 168
$historyLabel.Width = 232
$historyLabel.Text = "最近操作"
$form.Controls.Add($historyLabel)

$historyListBox = New-Object System.Windows.Forms.ListBox
$historyListBox.Left = 600
$historyListBox.Top = 194
$historyListBox.Width = 232
$historyListBox.Height = 146
$form.Controls.Add($historyListBox)

$copyHistoryButton = New-Object System.Windows.Forms.Button
$copyHistoryButton.Left = 600
$copyHistoryButton.Top = 346
$copyHistoryButton.Width = 108
$copyHistoryButton.Height = 28
$copyHistoryButton.Text = "复制摘要"

$script:isLexiconDirty = $false
$script:sortField = "phrase"
$script:sortDescending = $false
$script:lastUndoEntries = $null
$script:lastUndoLabel = ""
$script:operationHistory = New-Object System.Collections.Generic.List[string]

function Set-Status {
  param([string]$Text)
  $statusLabel.Text = $Text
}

function Set-DirtyState {
  param([bool]$Value)
  $script:isLexiconDirty = $Value
}

function Add-OperationHistory {
  param([string]$Text)
  $timestamp = Get-Date -Format "HH:mm:ss"
  $script:operationHistory.Insert(0, ("[{0}] {1}" -f $timestamp, $Text))
  while ($script:operationHistory.Count -gt 12) {
    $script:operationHistory.RemoveAt($script:operationHistory.Count - 1)
  }
  Refresh-OperationHistory
}

function Refresh-OperationHistory {
  $historyListBox.Items.Clear()
  foreach ($item in $script:operationHistory) {
    [void]$historyListBox.Items.Add($item)
  }
}

function Copy-RecentOperationSummary {
  $lines = New-Object System.Collections.Generic.List[string]
  $lines.Add("# 词库管理摘要")
  $lines.Add(("状态: {0}" -f $statusLabel.Text))
  $lines.Add(("选中: {0}" -f $selectionLabel.Text))
  $lines.Add(("源文件: {0}" -f $sourcePath))
  $lines.Add(("生成文件: {0}" -f $rimeLexiconPath))
  if ($script:operationHistory.Count -gt 0) {
    $lines.Add("")
    $lines.Add("最近操作:")
    foreach ($item in $script:operationHistory) {
      $lines.Add($item)
    }
  }
  [System.Windows.Forms.Clipboard]::SetText([string]::Join([Environment]::NewLine, $lines))
  Set-Status "已复制最近操作摘要。"
}

function Set-SelectionSummary {
  $selectedPhrases = @(Get-SelectedPhrases)
  if ($selectedPhrases.Count -eq 0) {
    $selectionLabel.Text = "未选中词条"
    return
  }
  $preview = @($selectedPhrases | Select-Object -First 3)
  $previewText = [string]::Join("、", $preview)
  if ($selectedPhrases.Count -gt 3) {
    $previewText += " 等"
  }
  $selectionLabel.Text = ("已选中 {0} 条：{1}" -f $selectedPhrases.Count, $previewText)
}

function Save-UndoSnapshot {
  param([string]$Label)
  $script:lastUndoEntries = @(Load-SourceEntries $sourcePath | ForEach-Object {
    [pscustomobject]@{
      Phrase = $_.Phrase
      Pinyin = $_.Pinyin
      Weight = $_.Weight
    }
  })
  $script:lastUndoLabel = $Label
}

function Undo-LastSourceChange {
  if ($null -eq $script:lastUndoEntries) {
    throw "当前没有可撤销的最近一次源词库改动。"
  }
  Write-SourceEntries $sourcePath $script:lastUndoEntries
  Set-DirtyState $true
  Refresh-EntryList
  Set-Status ("已撤销最近一次改动：{0}" -f $script:lastUndoLabel)
  Add-OperationHistory ("撤销最近改动：{0}" -f $script:lastUndoLabel)
  $script:lastUndoEntries = $null
  $script:lastUndoLabel = ""
}

function Get-SortedEntries {
  param([object[]]$Entries)
  switch ($script:sortField) {
    "pinyin" {
      $sorted = @($Entries | Sort-Object Pinyin, Phrase)
    }
    "weight" {
      $sorted = @($Entries | Sort-Object @{ Expression = { [int64]$_.Weight } }, Phrase)
    }
    default {
      $sorted = @($Entries | Sort-Object Phrase, Pinyin)
    }
  }
  if ($script:sortDescending) {
    [array]::Reverse($sorted)
  }
  return $sorted
}

function Set-Summary {
  $pendingText = $(if ($script:isLexiconDirty) { "状态：源词库已修改，尚未应用" } else { "状态：源词库与生成词库已同步" })
  $summaryLabel.Text = ("源词库: {0}" + [Environment]::NewLine + "生成词库: {1}    {2}" -f $sourcePath, $rimeLexiconPath, $pendingText)
}

function Refresh-EntryList {
  $selectedPhrases = @(Get-SelectedPhrases)
  $selectedSet = @{}
  foreach ($selectedPhrase in $selectedPhrases) {
    $selectedSet[$selectedPhrase] = $true
  }
  $keyword = $searchBox.Text.Trim()
  $listView.Items.Clear()
  $allEntries = @(Load-SourceEntries $sourcePath)
  $entries = $allEntries
  if (-not [string]::IsNullOrWhiteSpace($keyword)) {
    $entries = @($entries | Where-Object {
      $_.Phrase -like ("*" + $keyword + "*") -or
      $_.Pinyin -like ("*" + $keyword + "*") -or
      $_.Weight -like ("*" + $keyword + "*")
    })
  }
  $entries = @(Get-SortedEntries $entries)
  foreach ($entry in $entries) {
    $item = New-Object System.Windows.Forms.ListViewItem($entry.Phrase)
    [void]$item.SubItems.Add($entry.Pinyin)
    [void]$item.SubItems.Add($entry.Weight)
    [void]$listView.Items.Add($item)
  }
  foreach ($item in $listView.Items) {
    if ($selectedSet.ContainsKey($item.Text)) {
      $item.Selected = $true
      if ($listView.FocusedItem -eq $null) {
        $item.Focused = $true
      }
    }
  }
  Set-Summary
  Set-SelectionSummary
  $sortLabelText = $sortFieldComboBox.SelectedItem
  $directionText = $(if ($script:sortDescending) { "降序" } else { "升序" })
  $statusText = "当前显示 {0} / {1} 条词条，按{2}{3}。" -f $entries.Count, $allEntries.Count, $sortLabelText, $directionText
  if ($script:isLexiconDirty) {
    $statusText += " 源词库有未应用改动。"
  }
  Set-Status $statusText
}

function Get-SelectedPhrase {
  if ($listView.SelectedItems.Count -eq 0) { return "" }
  return $listView.SelectedItems[0].Text
}

function Get-SelectedPhrases {
  $phrases = New-Object System.Collections.Generic.List[string]
  foreach ($selectedItem in $listView.SelectedItems) {
    $phrases.Add($selectedItem.Text)
  }
  return $phrases.ToArray()
}

function Show-SetWeightDialog {
  param([string]$InitialWeight = "1000000")

  $dialog = New-Object System.Windows.Forms.Form
  $dialog.Text = "设置词条权重"
  $dialog.StartPosition = "CenterParent"
  $dialog.Width = 380
  $dialog.Height = 180
  $dialog.FormBorderStyle = "FixedDialog"
  $dialog.MaximizeBox = $false
  $dialog.MinimizeBox = $false

  $label = New-Object System.Windows.Forms.Label
  $label.Left = 16
  $label.Top = 18
  $label.Width = 320
  $label.Text = "权重"
  $dialog.Controls.Add($label)

  $weightBox = New-Object System.Windows.Forms.TextBox
  $weightBox.Left = 16
  $weightBox.Top = 42
  $weightBox.Width = 330
  $weightBox.Text = $InitialWeight
  $dialog.Controls.Add($weightBox)

  $okButton = New-Object System.Windows.Forms.Button
  $okButton.Left = 180
  $okButton.Top = 88
  $okButton.Width = 78
  $okButton.Text = "确定"
  $okButton.DialogResult = [System.Windows.Forms.DialogResult]::OK
  $dialog.Controls.Add($okButton)

  $cancelButton = New-Object System.Windows.Forms.Button
  $cancelButton.Left = 268
  $cancelButton.Top = 88
  $cancelButton.Width = 78
  $cancelButton.Text = "取消"
  $cancelButton.DialogResult = [System.Windows.Forms.DialogResult]::Cancel
  $dialog.Controls.Add($cancelButton)

  $dialog.AcceptButton = $okButton
  $dialog.CancelButton = $cancelButton
  if ($dialog.ShowDialog() -ne [System.Windows.Forms.DialogResult]::OK) {
    return $null
  }
  return $weightBox.Text.Trim()
}

function Add-Entry {
  # Dialog-level validation already runs before closing; keep a shared guard here too.
  $entry = Show-EntryDialog
  if ($null -eq $entry) { return }
  Assert-EntryFields $entry
  if ([string]::IsNullOrWhiteSpace($entry.Phrase)) { throw "词条汉字不能为空。" }
  if ([string]::IsNullOrWhiteSpace($entry.Pinyin)) { throw "数字标调拼音不能为空。" }
  if ([string]::IsNullOrWhiteSpace($entry.Weight)) { throw "权重不能为空。" }
  if ($entry.Phrase -match '[\t\r\n]') { throw "词条不能包含制表符或换行。" }
  if ($entry.Weight -notmatch '^\d+$') { throw "权重必须是整数。" }
  Validate-EntryForCurrentMode $script:codeMap $entry | Out-Null
  Save-UndoSnapshot "添加/更新词条"
  $action = Upsert-SourceEntry $sourcePath $entry
  Set-DirtyState $true
  Refresh-EntryList
  Add-OperationHistory ($(if ($action -eq "updated") { "更新词条：$($entry.Phrase)" } else { "添加词条：$($entry.Phrase)" }))
  Set-Status ($(if ($action -eq "updated") { "已更新词条，点击应用用户词库使其生效。" } else { "已添加词条，点击应用用户词库使其生效。" }))
}

function Edit-Entry {
  $phrases = @(Get-SelectedPhrases)
  if ($phrases.Count -eq 0) {
    throw "请先在列表中选中要编辑的词条。"
  }
  if ($phrases.Count -gt 1) {
    throw "编辑词条时请只选择一条。"
  }
  $phrase = $phrases[0]

  $existing = @(Load-SourceEntries $sourcePath | Where-Object { $_.Phrase -eq $phrase } | Select-Object -First 1)
  if ($existing.Count -eq 0) {
    throw "在源词库中找不到所选词条。"
  }

  $entry = Show-EntryDialog $existing[0].Phrase $existing[0].Pinyin $existing[0].Weight "编辑用户词条" "保存修改"
  if ($null -eq $entry) { return }
  if ([string]::IsNullOrWhiteSpace($entry.Phrase)) { throw "词条汉字不能为空。" }
  if ([string]::IsNullOrWhiteSpace($entry.Pinyin)) { throw "数字标调拼音不能为空。" }
  if ([string]::IsNullOrWhiteSpace($entry.Weight)) { throw "权重不能为空。" }
  if ($entry.Phrase -match '[\t\r\n]') { throw "词条不能包含制表符或换行。" }
  if ($entry.Weight -notmatch '^\d+$') { throw "权重必须是整数。" }
  Validate-EntryForCurrentMode $script:codeMap $entry | Out-Null
  Save-UndoSnapshot "编辑词条"
  if ($entry.Phrase -ne $phrase) {
    [void](Remove-SourceEntry $sourcePath $phrase)
  }
  [void](Upsert-SourceEntry $sourcePath $entry)
  Set-DirtyState $true
  Refresh-EntryList
  Add-OperationHistory ("编辑词条：{0}" -f $entry.Phrase)
  Set-Status "已编辑词条，点击应用用户词库使其生效。"
}

function Delete-Entry {
  $phrases = @(Get-SelectedPhrases)
  if ($phrases.Count -eq 0) {
    throw "请先在列表中选中要删除的词条。"
  }
  $preview = @($phrases | Select-Object -First 5)
  $previewText = [string]::Join("、", $preview)
  if ($phrases.Count -gt 5) {
    $previewText += " 等"
  }
  $confirmMessage = "确定要删除 $($phrases.Count) 条词条吗？" + [Environment]::NewLine + $previewText
  $confirm = [System.Windows.Forms.MessageBox]::Show(
    $confirmMessage,
    "词库管理",
    "YesNo",
    "Question"
  )
  if ($confirm -ne [System.Windows.Forms.DialogResult]::Yes) { return }
  Save-UndoSnapshot "删除词条"
  foreach ($phrase in $phrases) {
    if (-not (Remove-SourceEntry $sourcePath $phrase)) {
      throw "未找到要删除的词条：$phrase"
    }
  }
  Set-DirtyState $true
  Refresh-EntryList
  Add-OperationHistory "删除词条 $($phrases.Count) 条"
  Set-Status "已从源词库删除 $($phrases.Count) 条词条，点击应用用户词库使其生效。"
}

function Apply-Lexicon {
  Rebuild-RimeLexicon $sourcePath $rimeLexiconPath $script:codeMap $Mode
  Set-DirtyState $false
  Refresh-EntryList
  Add-OperationHistory "应用用户词库并重建 custom_phrase.txt"
  Set-Status "已重建 Rime custom_phrase.txt。"
  Show-Info "用户词库格式校验通过，已重建 Rime custom_phrase.txt。"
}

function Adjust-SelectedWeights {
  param([int]$Delta)
  $phrases = @(Get-SelectedPhrases)
  if ($phrases.Count -eq 0) {
    throw "请先选中要调整权重的词条。"
  }

  $entries = @(Load-SourceEntries $sourcePath)
  $selectedSet = @{}
  foreach ($phrase in $phrases) {
    $selectedSet[$phrase] = $true
  }

  $updatedCount = 0
  foreach ($entry in $entries) {
    if (-not $selectedSet.ContainsKey($entry.Phrase)) {
      continue
    }
    $nextWeight = [int64]$entry.Weight + $Delta
    if ($nextWeight -lt 0) {
      $nextWeight = 0
    }
    $entry.Weight = $nextWeight.ToString()
    $updatedCount++
  }

  Save-UndoSnapshot ("批量调整权重 {0}" -f $(if ($Delta -ge 0) { "+" + $Delta } else { $Delta }))
  Write-SourceEntries $sourcePath $entries
  Set-DirtyState $true
  Refresh-EntryList
  Add-OperationHistory ("批量调整权重 {0} 条（{1}）" -f $updatedCount, $(if ($Delta -ge 0) { "+" + $Delta } else { $Delta }))
  Set-Status ("已调整 {0} 条词条的权重（{1}）。" -f $updatedCount, $(if ($Delta -ge 0) { "+" + $Delta } else { $Delta }))
}

function Set-SelectedWeights {
  $phrases = @(Get-SelectedPhrases)
  if ($phrases.Count -eq 0) {
    throw "请先选中要设置权重的词条。"
  }

  $newWeight = Show-SetWeightDialog
  if ($null -eq $newWeight) { return }
  if ([string]::IsNullOrWhiteSpace($newWeight)) { throw "权重不能为空。" }
  if ($newWeight -notmatch '^\d+$') { throw "权重必须是整数。" }

  $entries = @(Load-SourceEntries $sourcePath)
  $selectedSet = @{}
  foreach ($phrase in $phrases) {
    $selectedSet[$phrase] = $true
  }

  $updatedCount = 0
  foreach ($entry in $entries) {
    if (-not $selectedSet.ContainsKey($entry.Phrase)) {
      continue
    }
    $entry.Weight = $newWeight
    $updatedCount++
  }

  Save-UndoSnapshot ("批量设定权重 {0}" -f $newWeight)
  Write-SourceEntries $sourcePath $entries
  Set-DirtyState $true
  Refresh-EntryList
  Add-OperationHistory ("批量设定权重 {0} 条 -> {1}" -f $updatedCount, $newWeight)
  Set-Status ("已将 {0} 条词条的权重设为 {1}。" -f $updatedCount, $newWeight)
}

function Get-ImportConflictPreview {
  param(
    [object[]]$CurrentEntries,
    [object[]]$ImportEntries
  )
  $currentByPhrase = @{}
  foreach ($entry in $CurrentEntries) {
    $currentByPhrase[$entry.Phrase] = $entry
  }

  $replaceCount = 0
  $sameCount = 0
  $newCount = 0
  $samples = New-Object System.Collections.Generic.List[string]
  $conflicts = New-Object System.Collections.Generic.List[object]
  $newEntries = New-Object System.Collections.Generic.List[object]
  foreach ($entry in $ImportEntries) {
    if (-not $currentByPhrase.ContainsKey($entry.Phrase)) {
      $newCount++
      $newEntries.Add([pscustomobject]@{
        Phrase = $entry.Phrase
        ImportedPinyin = $entry.Pinyin
        ImportedWeight = $entry.Weight
      })
      continue
    }
    $current = $currentByPhrase[$entry.Phrase]
    if ($current.Pinyin -eq $entry.Pinyin -and $current.Weight -eq $entry.Weight) {
      $sameCount++
      continue
    }
    $replaceCount++
    $conflicts.Add([pscustomobject]@{
      Phrase = $entry.Phrase
      CurrentPinyin = $current.Pinyin
      CurrentWeight = $current.Weight
      ImportedPinyin = $entry.Pinyin
      ImportedWeight = $entry.Weight
    })
    if ($samples.Count -lt 5) {
      $samples.Add(("{0}: {1}/{2} -> {3}/{4}" -f $entry.Phrase, $current.Pinyin, $current.Weight, $entry.Pinyin, $entry.Weight))
    }
  }

  return [pscustomobject]@{
    NewCount = $newCount
    ReplaceCount = $replaceCount
    SameCount = $sameCount
    Samples = $samples.ToArray()
    Conflicts = $conflicts.ToArray()
    NewEntries = $newEntries.ToArray()
  }
}

function Show-ImportConflictPreviewDialog {
  param([pscustomobject]$Preview)

  $dialog = New-Object System.Windows.Forms.Form
  $dialog.Text = "导入预览"
  $dialog.StartPosition = "CenterParent"
  $dialog.Width = 760
  $dialog.Height = 470

  $summaryLabel = New-Object System.Windows.Forms.Label
  $summaryLabel.Left = 16
  $summaryLabel.Top = 16
  $summaryLabel.Width = 700
  $summaryLabel.Height = 54
  $summaryLabel.Text = ("新增：{0}    覆盖：{1}    相同：{2}" -f $Preview.NewCount, $Preview.ReplaceCount, $Preview.SameCount)
  $dialog.Controls.Add($summaryLabel)

  $summaryText = ("新增：{0}；覆盖：{1}；相同：{2}" -f $Preview.NewCount, $Preview.ReplaceCount, $Preview.SameCount)

  $tabControl = New-Object System.Windows.Forms.TabControl
  $tabControl.Left = 16
  $tabControl.Top = 78
  $tabControl.Width = 710
  $tabControl.Height = 280
  $dialog.Controls.Add($tabControl)

  $conflictTab = New-Object System.Windows.Forms.TabPage("冲突项")
  $newTab = New-Object System.Windows.Forms.TabPage("新增项")
  [void]$tabControl.TabPages.Add($conflictTab)
  [void]$tabControl.TabPages.Add($newTab)

  $listView = New-Object System.Windows.Forms.ListView
  $listView.Left = 8
  $listView.Top = 8
  $listView.Width = 686
  $listView.Height = 232
  $listView.View = [System.Windows.Forms.View]::Details
  $listView.FullRowSelect = $true
  $listView.GridLines = $true
  $listView.CheckBoxes = $true
  [void]$listView.Columns.Add("词条", 150)
  [void]$listView.Columns.Add("当前", 240)
  [void]$listView.Columns.Add("导入后", 240)
  $conflictTab.Controls.Add($listView)

  foreach ($conflict in $Preview.Conflicts) {
    $item = New-Object System.Windows.Forms.ListViewItem($conflict.Phrase)
    $item.Checked = $true
    [void]$item.SubItems.Add(("{0} / {1}" -f $conflict.CurrentPinyin, $conflict.CurrentWeight))
    [void]$item.SubItems.Add(("{0} / {1}" -f $conflict.ImportedPinyin, $conflict.ImportedWeight))
    [void]$listView.Items.Add($item)
  }

  $newEntriesView = New-Object System.Windows.Forms.ListView
  $newEntriesView.Left = 8
  $newEntriesView.Top = 8
  $newEntriesView.Width = 686
  $newEntriesView.Height = 232
  $newEntriesView.View = [System.Windows.Forms.View]::Details
  $newEntriesView.FullRowSelect = $true
  $newEntriesView.GridLines = $true
  [void]$newEntriesView.Columns.Add("词条", 180)
  [void]$newEntriesView.Columns.Add("拼音", 320)
  [void]$newEntriesView.Columns.Add("权重", 120)
  $newTab.Controls.Add($newEntriesView)

  foreach ($entry in $Preview.NewEntries) {
    $item = New-Object System.Windows.Forms.ListViewItem($entry.Phrase)
    [void]$item.SubItems.Add($entry.ImportedPinyin)
    [void]$item.SubItems.Add($entry.ImportedWeight)
    [void]$newEntriesView.Items.Add($item)
  }

  $tipLabel = New-Object System.Windows.Forms.Label
  $tipLabel.Left = 16
  $tipLabel.Top = 366
  $tipLabel.Width = 500
  $tipLabel.Height = 32
  $tipLabel.Text = "合并导入时，只会覆盖这里勾选的冲突词条；新增词条始终导入。"
  $dialog.Controls.Add($tipLabel)

  $showConflictsButton = New-Object System.Windows.Forms.Button
  $showConflictsButton.Left = 16
  $showConflictsButton.Top = 402
  $showConflictsButton.Width = 88
  $showConflictsButton.Text = "只看冲突"
  $dialog.Controls.Add($showConflictsButton)

  $showNewEntriesButton = New-Object System.Windows.Forms.Button
  $showNewEntriesButton.Left = 112
  $showNewEntriesButton.Top = 402
  $showNewEntriesButton.Width = 88
  $showNewEntriesButton.Text = "只看新增"
  $dialog.Controls.Add($showNewEntriesButton)

  $showAllButton = New-Object System.Windows.Forms.Button
  $showAllButton.Left = 208
  $showAllButton.Top = 402
  $showAllButton.Width = 88
  $showAllButton.Text = "查看全部"
  $dialog.Controls.Add($showAllButton)

  $copyImportSummaryButton = New-Object System.Windows.Forms.Button
  $copyImportSummaryButton.Left = 304
  $copyImportSummaryButton.Top = 402
  $copyImportSummaryButton.Width = 120
  $copyImportSummaryButton.Text = "复制导入摘要"
  $dialog.Controls.Add($copyImportSummaryButton)

  $selectAllButton = New-Object System.Windows.Forms.Button
  $selectAllButton.Left = 516
  $selectAllButton.Top = 364
  $selectAllButton.Width = 88
  $selectAllButton.Text = "全选冲突"
  $dialog.Controls.Add($selectAllButton)

  $clearAllButton = New-Object System.Windows.Forms.Button
  $clearAllButton.Left = 612
  $clearAllButton.Top = 364
  $clearAllButton.Width = 88
  $clearAllButton.Text = "清空冲突"
  $dialog.Controls.Add($clearAllButton)

  $okButton = New-Object System.Windows.Forms.Button
  $okButton.Left = 534
  $okButton.Top = 402
  $okButton.Width = 78
  $okButton.Text = "继续"
  $okButton.DialogResult = [System.Windows.Forms.DialogResult]::OK
  $dialog.Controls.Add($okButton)

  $cancelButton = New-Object System.Windows.Forms.Button
  $cancelButton.Left = 622
  $cancelButton.Top = 402
  $cancelButton.Width = 78
  $cancelButton.Text = "取消"
  $cancelButton.DialogResult = [System.Windows.Forms.DialogResult]::Cancel
  $dialog.Controls.Add($cancelButton)

  $selectAllButton.Add_Click({
    foreach ($item in $listView.Items) {
      $item.Checked = $true
    }
  })

  $clearAllButton.Add_Click({
    foreach ($item in $listView.Items) {
      $item.Checked = $false
    }
  })

  $showConflictsButton.Add_Click({
    $tabControl.SelectedTab = $conflictTab
  })

  $showNewEntriesButton.Add_Click({
    $tabControl.SelectedTab = $newTab
  })

  $showAllButton.Add_Click({
    if ($Preview.Conflicts.Count -gt 0) {
      $tabControl.SelectedTab = $conflictTab
    } else {
      $tabControl.SelectedTab = $newTab
    }
  })

  $copyImportSummaryButton.Add_Click({
    $lines = New-Object System.Collections.Generic.List[string]
    $lines.Add("# 导入预览摘要")
    $lines.Add($summaryText)
    if ($Preview.Conflicts.Count -gt 0) {
      $lines.Add("")
      $lines.Add("冲突项示例:")
      foreach ($conflict in @($Preview.Conflicts | Select-Object -First 8)) {
        $lines.Add(("{0}: {1}/{2} -> {3}/{4}" -f $conflict.Phrase, $conflict.CurrentPinyin, $conflict.CurrentWeight, $conflict.ImportedPinyin, $conflict.ImportedWeight))
      }
    }
    if ($Preview.NewEntries.Count -gt 0) {
      $lines.Add("")
      $lines.Add("新增项示例:")
      foreach ($entry in @($Preview.NewEntries | Select-Object -First 8)) {
        $lines.Add(("{0}: {1}/{2}" -f $entry.Phrase, $entry.ImportedPinyin, $entry.ImportedWeight))
      }
    }
    [System.Windows.Forms.Clipboard]::SetText([string]::Join([Environment]::NewLine, $lines))
  })

  $dialog.AcceptButton = $okButton
  $dialog.CancelButton = $cancelButton
  if ($dialog.ShowDialog() -ne [System.Windows.Forms.DialogResult]::OK) {
    return $null
  }
  $selectedConflictPhrases = New-Object System.Collections.Generic.List[string]
  foreach ($item in $listView.Items) {
    if ($item.Checked) {
      $selectedConflictPhrases.Add($item.Text)
    }
  }
  return [pscustomobject]@{
    SelectedConflictPhrases = $selectedConflictPhrases.ToArray()
  }
}

function Set-SortFromColumn {
  param([int]$ColumnIndex)
  $field = switch ($ColumnIndex) {
    1 { "pinyin" }
    2 { "weight" }
    default { "phrase" }
  }

  if ($script:sortField -eq $field) {
    $script:sortDescending = -not $script:sortDescending
  } else {
    $script:sortField = $field
    $script:sortDescending = $false
  }

  switch ($script:sortField) {
    "pinyin" { $sortFieldComboBox.SelectedItem = "拼音" }
    "weight" { $sortFieldComboBox.SelectedItem = "权重" }
    default { $sortFieldComboBox.SelectedItem = "词条" }
  }
  $sortDirectionButton.Text = $(if ($script:sortDescending) { "降序" } else { "升序" })
}

function Import-Lexicon {
  $dialog = New-Object System.Windows.Forms.OpenFileDialog
  $dialog.Filter = "文本文件 (*.txt;*.tsv)|*.txt;*.tsv|所有文件 (*.*)|*.*"
  $dialog.Title = "导入用户词库"
  if ($dialog.ShowDialog() -ne [System.Windows.Forms.DialogResult]::OK) { return }

  $importEntries = @(Load-SourceEntries $dialog.FileName)
  foreach ($entry in $importEntries) {
    Validate-EntryForCurrentMode $script:codeMap $entry | Out-Null
  }

  $currentEntries = @(Load-SourceEntries $sourcePath)
  $preview = Get-ImportConflictPreview $currentEntries $importEntries
  $previewLines = @(
    ("导入词条数：{0}" -f $importEntries.Count),
    ("新增：{0}" -f $preview.NewCount),
    ("覆盖：{0}" -f $preview.ReplaceCount),
    ("相同：{0}" -f $preview.SameCount)
  )
  if ($preview.Samples.Count -gt 0) {
    $previewLines += "示例："
    $previewLines += $preview.Samples
  }
  $previewSelection = Show-ImportConflictPreviewDialog $preview
  if ($null -eq $previewSelection) { return }

  $choice = [System.Windows.Forms.MessageBox]::Show(
    ([string]::Join([Environment]::NewLine, $previewLines) + [Environment]::NewLine + [Environment]::NewLine +
    "选择导入方式：" + [Environment]::NewLine +
    "是 = 完全替换当前源词库" + [Environment]::NewLine +
    "否 = 按词条合并并覆盖同名项" + [Environment]::NewLine +
    "取消 = 放弃导入"),
    "导入用户词库",
    "YesNoCancel",
    "Question"
  )
  if ($choice -eq [System.Windows.Forms.DialogResult]::Cancel) { return }

  if ($choice -eq [System.Windows.Forms.DialogResult]::Yes) {
    Save-UndoSnapshot "导入词库（替换）"
    Write-SourceEntries $sourcePath $importEntries
    Set-DirtyState $true
    Refresh-EntryList
    Add-OperationHistory ("替换导入词库：{0} 条" -f $importEntries.Count)
    Set-Status "已替换当前源词库，点击应用用户词库使其生效。"
    return
  }

  $selectedConflictSet = @{}
  foreach ($phrase in $previewSelection.SelectedConflictPhrases) {
    $selectedConflictSet[$phrase] = $true
  }
  $filteredImportEntries = New-Object System.Collections.Generic.List[object]
  $currentByPhrase = @{}
  foreach ($current in $currentEntries) {
    $currentByPhrase[$current.Phrase] = $current
  }
  foreach ($entry in $importEntries) {
    if (-not $currentByPhrase.ContainsKey($entry.Phrase)) {
      $filteredImportEntries.Add($entry)
      continue
    }
    $current = $currentByPhrase[$entry.Phrase]
    if ($current.Pinyin -eq $entry.Pinyin -and $current.Weight -eq $entry.Weight) {
      continue
    }
    if ($selectedConflictSet.ContainsKey($entry.Phrase)) {
      $filteredImportEntries.Add($entry)
    }
  }

  Save-UndoSnapshot "导入词库（合并）"
  foreach ($entry in $filteredImportEntries) {
    [void](Upsert-SourceEntry $sourcePath $entry)
  }
  Set-DirtyState $true
  Refresh-EntryList
  Add-OperationHistory ("合并导入词库：新增/覆盖 {0} 条" -f $filteredImportEntries.Count)
  Set-Status "已合并导入到源词库，点击应用用户词库使其生效。"
}

function Export-Lexicon {
  Ensure-SourceFile $sourcePath
  $dialog = New-Object System.Windows.Forms.SaveFileDialog
  $dialog.Filter = "文本文件 (*.txt)|*.txt|TSV 文件 (*.tsv)|*.tsv|所有文件 (*.*)|*.*"
  $dialog.Title = "导出用户词库"
  $dialog.FileName = "yime_user_phrases.txt"
  if ($dialog.ShowDialog() -ne [System.Windows.Forms.DialogResult]::OK) { return }
  Copy-Item -LiteralPath $sourcePath -Destination $dialog.FileName -Force
  Set-Status "已导出用户词库源文件。"
}

function Open-SourceFile {
  Ensure-SourceFile $sourcePath
  Start-Process -FilePath $sourcePath | Out-Null
  Set-Status "已打开用户词库源文件。修改后请点击应用用户词库。"
}

function Open-UserFolder {
  Start-Process -FilePath $UserDir | Out-Null
  Set-Status "已打开用户词库目录。"
}

function Add-ActionButton {
  param([string]$Text, [scriptblock]$Action)
  $button = New-Object System.Windows.Forms.Button
  $actionBlock = $Action.GetNewClosure()
  $button.Text = $Text
  $button.Width = 108
  $button.Height = 28
  $button.Add_Click({
    try {
      & $actionBlock
    } catch {
      Show-Error $_.Exception.Message
    }
  }.GetNewClosure())
  $toolbar.Controls.Add($button)
  return $button
}

function Add-MenuAction {
  param(
    [System.Windows.Forms.ToolStripMenuItem]$Parent,
    [string]$Text,
    [scriptblock]$Action
  )
  $item = New-Object System.Windows.Forms.ToolStripMenuItem($Text)
  $actionBlock = $Action.GetNewClosure()
  $item.Add_Click({
    try {
      & $actionBlock
    } catch {
      Show-Error $_.Exception.Message
    }
  }.GetNewClosure())
  $Parent.DropDownItems.Add($item) | Out-Null
  return $item
}

try {
  [void](Add-ActionButton "添加词条" { Add-Entry })
  [void](Add-ActionButton "删除词条" { Delete-Entry })
  [void](Add-ActionButton "权重+1000" { Adjust-SelectedWeights 1000 })
  [void](Add-ActionButton "权重-1000" { Adjust-SelectedWeights -1000 })
  [void](Add-ActionButton "设权重" { Set-SelectedWeights })
  [void](Add-ActionButton "撤销" { Undo-LastSourceChange })
  [void](Add-ActionButton "复制摘要" { Copy-RecentOperationSummary })
  [void](Add-ActionButton "编辑源文件" { Open-SourceFile })
  [void](Add-ActionButton "打开目录" { Open-UserFolder })
  [void](Add-ActionButton "应用用户词库" { Apply-Lexicon })
  [void](Add-ActionButton "导入" { Import-Lexicon })
  [void](Add-ActionButton "导出" { Export-Lexicon })
  [void](Add-ActionButton "刷新列表" { Refresh-EntryList })

  [void](Add-MenuAction $fileMenu "导入用户词库" { Import-Lexicon })
  [void](Add-MenuAction $fileMenu "导出用户词库" { Export-Lexicon })
  $fileMenu.DropDownItems.Add((New-Object System.Windows.Forms.ToolStripSeparator)) | Out-Null
  [void](Add-MenuAction $fileMenu "打开源文件" { Open-SourceFile })
  [void](Add-MenuAction $fileMenu "打开词库目录" { Open-UserFolder })
  $fileMenu.DropDownItems.Add((New-Object System.Windows.Forms.ToolStripSeparator)) | Out-Null
  [void](Add-MenuAction $fileMenu "关闭" { $form.Close() })

  [void](Add-MenuAction $actionMenu "添加词条" { Add-Entry })
  [void](Add-MenuAction $actionMenu "删除词条" { Delete-Entry })
  [void](Add-MenuAction $actionMenu "权重 +1000" { Adjust-SelectedWeights 1000 })
  [void](Add-MenuAction $actionMenu "权重 -1000" { Adjust-SelectedWeights -1000 })
  [void](Add-MenuAction $actionMenu "设置权重" { Set-SelectedWeights })
  [void](Add-MenuAction $actionMenu "撤销最近改动" { Undo-LastSourceChange })
  [void](Add-MenuAction $actionMenu "复制最近摘要" { Copy-RecentOperationSummary })
  [void](Add-MenuAction $actionMenu "应用用户词库" { Apply-Lexicon })
  [void](Add-MenuAction $actionMenu "刷新列表" { Refresh-EntryList })

  [void](Add-ActionButton "编辑" { Edit-Entry })
  [void](Add-MenuAction $actionMenu "编辑" { Edit-Entry })
} catch {
  Show-Error $_.Exception.Message
  return
}

$sortFieldComboBox.Add_SelectedIndexChanged({
  try {
    switch ($sortFieldComboBox.SelectedItem) {
      "拼音" { $script:sortField = "pinyin" }
      "权重" { $script:sortField = "weight" }
      default { $script:sortField = "phrase" }
    }
    Refresh-EntryList
  } catch {
    Show-Error $_.Exception.Message
  }
})

$sortDirectionButton.Add_Click({
  try {
    $script:sortDescending = -not $script:sortDescending
    $sortDirectionButton.Text = $(if ($script:sortDescending) { "降序" } else { "升序" })
    Refresh-EntryList
  } catch {
    Show-Error $_.Exception.Message
  }
})

$listView.Add_ColumnClick({
  param($sender, $eventArgs)
  try {
    Set-SortFromColumn $eventArgs.Column
    Refresh-EntryList
  } catch {
    Show-Error $_.Exception.Message
  }
})

$listView.Add_ItemSelectionChanged({
  try {
    Set-SelectionSummary
  } catch {
    Show-Error $_.Exception.Message
  }
})

$searchBox.Add_TextChanged({
  try {
    Refresh-EntryList
  } catch {
    Show-Error $_.Exception.Message
  }
})

$searchResetButton.Add_Click({
  try {
    $searchBox.Text = ""
    Refresh-EntryList
  } catch {
    Show-Error $_.Exception.Message
  }
})

$listView.Add_DoubleClick({
  try {
    if ($listView.SelectedItems.Count -gt 0) {
      Edit-Entry
    }
  } catch {
    Show-Error $_.Exception.Message
  }
})

$form.Add_FormClosing({
  param($sender, $eventArgs)
  if (-not $script:isLexiconDirty) {
    return
  }
  $choice = [System.Windows.Forms.MessageBox]::Show(
    "源词库还有未应用改动。" + [Environment]::NewLine +
    "是 = 先应用用户词库再关闭" + [Environment]::NewLine +
    "否 = 直接关闭（保留源词库改动）" + [Environment]::NewLine +
    "取消 = 留在当前窗口",
    "词库管理",
    "YesNoCancel",
    "Warning"
  )
  if ($choice -eq [System.Windows.Forms.DialogResult]::Cancel) {
    $eventArgs.Cancel = $true
    return
  }
  if ($choice -eq [System.Windows.Forms.DialogResult]::Yes) {
    try {
      Apply-Lexicon
    } catch {
      $eventArgs.Cancel = $true
      Show-Error $_.Exception.Message
    }
  }
})

$form.Add_Shown({
  try {
    $screenBounds = [System.Windows.Forms.Screen]::PrimaryScreen.WorkingArea
    $x = $screenBounds.Left + [int](($screenBounds.Width - $form.Width) / 2)
    $y = $screenBounds.Top + [int](($screenBounds.Height - $form.Height) / 2)
    if ($x -lt $screenBounds.Left) { $x = $screenBounds.Left }
    if ($y -lt $screenBounds.Top) { $y = $screenBounds.Top }
    $form.Location = New-Object System.Drawing.Point($x, $y)
    $form.BeginInvoke([System.Windows.Forms.MethodInvoker]{
      try {
        if (-not $script:lexiconLoaded) {
          $script:codeMap = Load-CodeMap (Join-Path $SharedDir "yime_pinyin_codes.tsv")
          Ensure-SourceFile $sourcePath
          $script:lexiconLoaded = $true
        }
        Refresh-OperationHistory
        Set-SelectionSummary
        Refresh-EntryList
      } catch {
        Show-Error $_.Exception.Message
      }
    }) | Out-Null
  } catch {
    Show-Error $_.Exception.Message
  }
})

try {
  [void]$form.ShowDialog()
} catch {
  Show-Error $_.Exception.Message
}
`
