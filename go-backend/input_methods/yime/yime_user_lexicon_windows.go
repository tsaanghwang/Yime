//go:build windows

package yime

import (
	"os"
	"os/exec"
	"path/filepath"
	"syscall"
)

func (ime *IME) startUserLexiconAddHelper(mode string) error {
	userDir := ime.userDir()
	sharedDir := ime.sharedDir()
	if userDir == "" || sharedDir == "" {
		return os.ErrNotExist
	}
	if err := os.MkdirAll(userDir, 0o755); err != nil {
		return err
	}
	scriptPath := filepath.Join(userDir, "pime_yime_add_phrase.ps1")
	scriptContent := append([]byte{0xEF, 0xBB, 0xBF}, []byte(userLexiconAddScript)...)
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

const userLexiconAddScript = `param(
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
  [System.Windows.Forms.MessageBox]::Show($Message, "添加用户词条", "OK", "Error") | Out-Null
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

function Upsert-SourceEntry {
  param(
    [string]$Path,
    [string]$Phrase,
    [string]$Pinyin,
    [string]$Weight
  )
  Ensure-SourceFile $Path
  $lines = @(Get-Content -LiteralPath $Path -Encoding UTF8)
  $updated = New-Object System.Collections.Generic.List[string]
  $entryLine = $Phrase + [char]9 + $Pinyin + [char]9 + $Weight
  $replaced = $false
  foreach ($line in $lines) {
    if ([string]::IsNullOrWhiteSpace($line) -or $line.TrimStart().StartsWith("#")) {
      $updated.Add($line)
      continue
    }
    $fields = $line -split ([string][char]9)
    if ($fields.Count -ge 1 -and $fields[0].Trim() -eq $Phrase) {
      if (-not $replaced) {
        $updated.Add($entryLine)
        $replaced = $true
      }
      continue
    }
    $updated.Add($line)
  }
  if (-not $replaced) { $updated.Add($entryLine) }
  Set-Content -LiteralPath $Path -Encoding UTF8 -Value $updated.ToArray()
  return $(if ($replaced) { "updated" } else { "inserted" })
}

function Rebuild-RimeLexicon {
  param(
    [string]$SourcePath,
    [string]$TargetPath,
    [hashtable]$CodeMap,
    [string]$Mode
  )
  $output = New-Object System.Collections.Generic.List[string]
  $output.Add("# Generated by PIME Yime from yime_user_phrases.txt")
  $output.Add("# format: phrase<TAB>code<TAB>weight")

  $lineNumber = 0
  foreach ($line in (Get-Content -LiteralPath $SourcePath -Encoding UTF8)) {
    $lineNumber++
    if ([string]::IsNullOrWhiteSpace($line) -or $line.TrimStart().StartsWith("#")) { continue }
    $fields = $line -split ([string][char]9)
    if ($fields.Count -lt 2) { throw "用户词库第 $lineNumber 行格式应为：词条<TAB>数字标调拼音<TAB>权重。" }
    $phrase = $fields[0].Trim()
    $pinyin = $fields[1].Trim()
    $weight = "1000000"
    if ($fields.Count -ge 3 -and -not [string]::IsNullOrWhiteSpace($fields[2])) { $weight = $fields[2].Trim() }
    if ([string]::IsNullOrWhiteSpace($phrase) -or [string]::IsNullOrWhiteSpace($pinyin)) {
      throw "用户词库第 $lineNumber 行词条和数字标调拼音不能为空。"
    }
    if ($weight -notmatch '^\d+$') { throw "用户词库第 $lineNumber 行权重必须是整数。" }
    $converted = Convert-PinyinToCode $CodeMap $pinyin $Mode
    $output.Add($phrase + [char]9 + $converted.code + [char]9 + $weight)
  }
  Set-Content -LiteralPath $TargetPath -Encoding UTF8 -Value $output.ToArray()
}

$clipboardText = ""
try { $clipboardText = [System.Windows.Forms.Clipboard]::GetText() } catch {}

$form = New-Object System.Windows.Forms.Form
$form.Text = "添加用户词条"
$form.StartPosition = "CenterScreen"
$form.TopMost = $true
$form.Width = 460
$form.Height = 250
$form.FormBorderStyle = "FixedDialog"
$form.MaximizeBox = $false
$form.MinimizeBox = $false

$phraseLabel = New-Object System.Windows.Forms.Label
$phraseLabel.Text = "词条汉字"
$phraseLabel.Left = 16
$phraseLabel.Top = 18
$phraseLabel.Width = 400
$form.Controls.Add($phraseLabel)

$phraseBox = New-Object System.Windows.Forms.TextBox
$phraseBox.Left = 16
$phraseBox.Top = 40
$phraseBox.Width = 410
$phraseBox.Text = $clipboardText.Trim()
$form.Controls.Add($phraseBox)

$pinyinLabel = New-Object System.Windows.Forms.Label
$pinyinLabel.Text = "数字标调拼音，例如 zhong1 guo2；也接受 zhong1guo2"
$pinyinLabel.Left = 16
$pinyinLabel.Top = 76
$pinyinLabel.Width = 410
$form.Controls.Add($pinyinLabel)

$pinyinBox = New-Object System.Windows.Forms.TextBox
$pinyinBox.Left = 16
$pinyinBox.Top = 98
$pinyinBox.Width = 410
$form.Controls.Add($pinyinBox)

$hintLabel = New-Object System.Windows.Forms.Label
$hintLabel.Text = "加入后会更新用户词库文件并重建 Rime custom_phrase.txt。"
$hintLabel.Left = 16
$hintLabel.Top = 128
$hintLabel.Width = 410
$hintLabel.Height = 20
$form.Controls.Add($hintLabel)

$okButton = New-Object System.Windows.Forms.Button
$okButton.Text = "加入"
$okButton.Left = 260
$okButton.Top = 164
$okButton.Width = 78
$okButton.DialogResult = [System.Windows.Forms.DialogResult]::OK
$form.Controls.Add($okButton)

$cancelButton = New-Object System.Windows.Forms.Button
$cancelButton.Text = "取消"
$cancelButton.Left = 348
$cancelButton.Top = 164
$cancelButton.Width = 78
$cancelButton.DialogResult = [System.Windows.Forms.DialogResult]::Cancel
$form.Controls.Add($cancelButton)

$form.AcceptButton = $okButton
$form.CancelButton = $cancelButton
$form.Add_Shown({
  $form.Activate() | Out-Null
  $form.BringToFront()
  if ($phraseBox.Text.Trim().Length -gt 0) { $pinyinBox.Focus() | Out-Null } else { $phraseBox.Focus() | Out-Null }
})

$result = $form.ShowDialog()
if ($result -ne [System.Windows.Forms.DialogResult]::OK) { exit 0 }

try {
  $phrase = $phraseBox.Text.Trim()
  $rawPinyin = $pinyinBox.Text.Trim()
  if ([string]::IsNullOrWhiteSpace($phrase)) { throw "词条汉字不能为空。" }
  if ([string]::IsNullOrWhiteSpace($rawPinyin)) { throw "数字标调拼音不能为空。" }
  if ($phrase -match '[\t\r\n]') { throw "词条不能包含制表符或换行。" }
  if ($rawPinyin -match '[\t\r\n]') { throw "数字标调拼音不能包含制表符或换行。" }

  $codeMap = Load-CodeMap (Join-Path $SharedDir "yime_pinyin_codes.tsv")
  $converted = Convert-PinyinToCode $codeMap $rawPinyin $Mode
  $textElements = [System.Globalization.StringInfo]::ParseCombiningCharacters($phrase).Count
  if ($textElements -ne $converted.syllables) {
    throw "词条字数（$textElements）和拼音音节数（$($converted.syllables)）不一致。"
  }

  New-Item -ItemType Directory -Path $UserDir -Force | Out-Null
  $sourcePath = Join-Path $UserDir "yime_user_phrases.txt"
  $action = Upsert-SourceEntry $sourcePath $phrase $converted.pinyin "1000000"
  $rimeLexiconPath = Join-Path $UserDir "custom_phrase.txt"
  Rebuild-RimeLexicon $sourcePath $rimeLexiconPath $codeMap $Mode

  $verb = $(if ($action -eq "updated") { "已更新用户词条" } else { "已加入用户词条" })
  [System.Windows.Forms.MessageBox]::Show($verb + "：" + $phrase + [Environment]::NewLine + "拼音：" + $converted.pinyin + [Environment]::NewLine + "编码：" + $converted.code + [Environment]::NewLine + "如未立即出现，请点击 用户词库 / 应用用户词库 或重新切换方案。", "添加用户词条", "OK", "Information") | Out-Null
} catch {
  Show-Error $_.Exception.Message
  exit 1
}
`
