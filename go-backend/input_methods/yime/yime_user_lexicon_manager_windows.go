//go:build windows

package yime

import (
	"os"
	"os/exec"
	"path/filepath"
	"syscall"
)

func (ime *IME) startUserLexiconManagerHelper(mode string) error {
	userDir := ime.userDir()
	sharedDir := ime.sharedDir()
	if userDir == "" || sharedDir == "" {
		return os.ErrNotExist
	}
	if err := os.MkdirAll(userDir, 0o755); err != nil {
		return err
	}
	scriptPath := filepath.Join(userDir, "pime_yime_lexicon_manager.ps1")
	scriptContent := append([]byte{0xEF, 0xBB, 0xBF}, []byte(userLexiconManagerScript)...)
	if err := os.WriteFile(scriptPath, scriptContent, 0o644); err != nil {
		return err
	}
	cmd := exec.Command(
		"powershell.exe",
		"-NoProfile",
		"-STA",
		"-ExecutionPolicy",
		"Bypass",
		"-WindowStyle",
		"Hidden",
		"-File",
		scriptPath,
		"-SharedDir",
		sharedDir,
		"-UserDir",
		userDir,
		"-Mode",
		mode,
	)
	cmd.SysProcAttr = &syscall.SysProcAttr{HideWindow: true}
	return cmd.Start()
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
  param([string]$Phrase = "", [string]$Pinyin = "")

  if ([string]::IsNullOrWhiteSpace($Phrase)) {
    try {
      $Phrase = [System.Windows.Forms.Clipboard]::GetText().Trim()
    } catch {}
  }

  $dialog = New-Object System.Windows.Forms.Form
  $dialog.Text = "添加用户词条"
  $dialog.StartPosition = "CenterParent"
  $dialog.TopMost = $true
  $dialog.Width = 460
  $dialog.Height = 250
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

  $okButton = New-Object System.Windows.Forms.Button
  $okButton.Text = "保存"
  $okButton.Left = 260
  $okButton.Top = 164
  $okButton.Width = 78
  $okButton.DialogResult = [System.Windows.Forms.DialogResult]::OK
  $dialog.Controls.Add($okButton)

  $cancelButton = New-Object System.Windows.Forms.Button
  $cancelButton.Text = "取消"
  $cancelButton.Left = 348
  $cancelButton.Top = 164
  $cancelButton.Width = 78
  $cancelButton.DialogResult = [System.Windows.Forms.DialogResult]::Cancel
  $dialog.Controls.Add($cancelButton)

  $dialog.AcceptButton = $okButton
  $dialog.CancelButton = $cancelButton

  $result = $dialog.ShowDialog()
  if ($result -ne [System.Windows.Forms.DialogResult]::OK) { return $null }
  return [pscustomobject]@{
    Phrase = $phraseBox.Text.Trim()
    Pinyin = Normalize-PinyinSpacing $pinyinBox.Text
    Weight = "1000000"
  }
}

$sourcePath = Join-Path $UserDir "yime_user_phrases.txt"
$rimeLexiconPath = Join-Path $UserDir "custom_phrase.txt"
$codeMap = Load-CodeMap (Join-Path $SharedDir "yime_pinyin_codes.tsv")
Ensure-SourceFile $sourcePath

$form = New-Object System.Windows.Forms.Form
$form.Text = "词库管理"
$form.StartPosition = "CenterScreen"
$form.TopMost = $true
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

$listView = New-Object System.Windows.Forms.ListView
$listView.Left = 12
$listView.Top = 108
$listView.Width = 820
$listView.Height = 370
$listView.View = [System.Windows.Forms.View]::Details
$listView.FullRowSelect = $true
$listView.GridLines = $true
$listView.MultiSelect = $false
$listView.HideSelection = $false
[void]$listView.Columns.Add("词条", 180)
[void]$listView.Columns.Add("数字标调拼音", 430)
[void]$listView.Columns.Add("权重", 120)
$form.Controls.Add($listView)

$statusLabel = New-Object System.Windows.Forms.Label
$statusLabel.Left = 12
$statusLabel.Top = 488
$statusLabel.Width = 820
$statusLabel.Height = 28
$statusLabel.Text = "就绪。"
$form.Controls.Add($statusLabel)

function Set-Status {
  param([string]$Text)
  $statusLabel.Text = $Text
}

function Refresh-EntryList {
  $listView.Items.Clear()
  $entries = @(Load-SourceEntries $sourcePath)
  foreach ($entry in $entries) {
    $item = New-Object System.Windows.Forms.ListViewItem($entry.Phrase)
    [void]$item.SubItems.Add($entry.Pinyin)
    [void]$item.SubItems.Add($entry.Weight)
    [void]$listView.Items.Add($item)
  }
  Set-Status ("当前共有 {0} 条词条。" -f $entries.Count)
}

function Get-SelectedPhrase {
  if ($listView.SelectedItems.Count -eq 0) { return "" }
  return $listView.SelectedItems[0].Text
}

function Add-Entry {
  $entry = Show-EntryDialog
  if ($null -eq $entry) { return }
  if ([string]::IsNullOrWhiteSpace($entry.Phrase)) { throw "词条汉字不能为空。" }
  if ([string]::IsNullOrWhiteSpace($entry.Pinyin)) { throw "数字标调拼音不能为空。" }
  if ($entry.Phrase -match '[\t\r\n]') { throw "词条不能包含制表符或换行。" }
  Validate-EntryForCurrentMode $codeMap $entry | Out-Null
  $action = Upsert-SourceEntry $sourcePath $entry
  Refresh-EntryList
  Set-Status ($(if ($action -eq "updated") { "已更新词条，点击“应用用户词库”使其生效。" } else { "已添加词条，点击“应用用户词库”使其生效。" }))
}

function Delete-Entry {
  $phrase = Get-SelectedPhrase
  if ([string]::IsNullOrWhiteSpace($phrase)) {
    throw "请先在列表中选中要删除的词条。"
  }
  $confirm = [System.Windows.Forms.MessageBox]::Show("确定要删除词条“$phrase”吗？", "词库管理", "YesNo", "Question")
  if ($confirm -ne [System.Windows.Forms.DialogResult]::Yes) { return }
  if (-not (Remove-SourceEntry $sourcePath $phrase)) {
    throw "未找到要删除的词条：$phrase"
  }
  Refresh-EntryList
  Set-Status "已从源词库删除词条，点击“应用用户词库”使其生效。"
}

function Apply-Lexicon {
  Rebuild-RimeLexicon $sourcePath $rimeLexiconPath $codeMap $Mode
  Set-Status "已重建 Rime custom_phrase.txt。"
  Show-Info "用户词库格式校验通过，已重建 Rime custom_phrase.txt。"
}

function Import-Lexicon {
  $dialog = New-Object System.Windows.Forms.OpenFileDialog
  $dialog.Filter = "文本文件 (*.txt;*.tsv)|*.txt;*.tsv|所有文件 (*.*)|*.*"
  $dialog.Title = "导入用户词库"
  if ($dialog.ShowDialog() -ne [System.Windows.Forms.DialogResult]::OK) { return }

  $importEntries = @(Load-SourceEntries $dialog.FileName)
  foreach ($entry in $importEntries) {
    Validate-EntryForCurrentMode $codeMap $entry | Out-Null
  }

  $choice = [System.Windows.Forms.MessageBox]::Show(
    "选择导入方式：" + [Environment]::NewLine +
    "是 = 完全替换当前源词库" + [Environment]::NewLine +
    "否 = 按词条合并并覆盖同名项" + [Environment]::NewLine +
    "取消 = 放弃导入",
    "导入用户词库",
    "YesNoCancel",
    "Question"
  )
  if ($choice -eq [System.Windows.Forms.DialogResult]::Cancel) { return }

  if ($choice -eq [System.Windows.Forms.DialogResult]::Yes) {
    Write-SourceEntries $sourcePath $importEntries
    Refresh-EntryList
    Set-Status "已替换当前源词库，点击“应用用户词库”使其生效。"
    return
  }

  foreach ($entry in $importEntries) {
    [void](Upsert-SourceEntry $sourcePath $entry)
  }
  Refresh-EntryList
  Set-Status "已合并导入到源词库，点击“应用用户词库”使其生效。"
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
  Set-Status "已打开用户词库源文件。修改后请点击“应用用户词库”。"
}

function Open-UserFolder {
  Start-Process -FilePath $UserDir | Out-Null
  Set-Status "已打开用户词库目录。"
}

function Add-ActionButton {
  param([string]$Text, [scriptblock]$Action)
  $button = New-Object System.Windows.Forms.Button
  $button.Text = $Text
  $button.Width = 108
  $button.Height = 28
  $button.Add_Click({
    try {
      & $Action
    } catch {
      Show-Error $_.Exception.Message
    }
  })
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
  $item.Add_Click({
    try {
      & $Action
    } catch {
      Show-Error $_.Exception.Message
    }
  })
  $Parent.DropDownItems.Add($item) | Out-Null
  return $item
}

[void](Add-ActionButton "添加词条" { Add-Entry })
[void](Add-ActionButton "删除词条" { Delete-Entry })
[void](Add-ActionButton "编辑源文件" { Open-SourceFile })
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
[void](Add-MenuAction $actionMenu "应用用户词库" { Apply-Lexicon })
[void](Add-MenuAction $actionMenu "刷新列表" { Refresh-EntryList })

$form.Add_Shown({
  try {
    Refresh-EntryList
  } catch {
    Show-Error $_.Exception.Message
  }
})

[void]$form.ShowDialog()
`
