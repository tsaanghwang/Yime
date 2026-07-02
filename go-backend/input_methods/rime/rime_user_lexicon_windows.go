//go:build windows

package rime

import (
	"os"
	"os/exec"
	"path/filepath"
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
	if err := os.WriteFile(scriptPath, []byte(userLexiconAddScript), 0o644); err != nil {
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
	return cmd.Start()
}

const userLexiconAddScript = `
param(
  [string]$SharedDir,
  [string]$UserDir,
  [ValidateSet("full", "variable", "shorthand")]
  [string]$Mode = "variable"
)

$ErrorActionPreference = "Stop"
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[System.Windows.Forms.Application]::EnableVisualStyles()

function Normalize-Pinyin {
  param([string]$Value)
  return $Value.Trim().ToLowerInvariant().Replace("u:", "ü").Replace("v", "ü")
}

function Load-CodeMap {
  param([string]$Path)
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

$clipboardText = ""
try { $clipboardText = [System.Windows.Forms.Clipboard]::GetText() } catch {}

$form = New-Object System.Windows.Forms.Form
$form.Text = "添加用户词条"
$form.StartPosition = "CenterScreen"
$form.TopMost = $true
$form.Width = 420
$form.Height = 230
$form.FormBorderStyle = "FixedDialog"
$form.MaximizeBox = $false
$form.MinimizeBox = $false

$phraseLabel = New-Object System.Windows.Forms.Label
$phraseLabel.Text = "词条"
$phraseLabel.Left = 16
$phraseLabel.Top = 18
$phraseLabel.Width = 360
$form.Controls.Add($phraseLabel)

$phraseBox = New-Object System.Windows.Forms.TextBox
$phraseBox.Left = 16
$phraseBox.Top = 40
$phraseBox.Width = 370
$phraseBox.Text = $clipboardText.Trim()
$form.Controls.Add($phraseBox)

$pinyinLabel = New-Object System.Windows.Forms.Label
$pinyinLabel.Text = "数字标调拼音，例如 zhong1 guo2"
$pinyinLabel.Left = 16
$pinyinLabel.Top = 74
$pinyinLabel.Width = 360
$form.Controls.Add($pinyinLabel)

$pinyinBox = New-Object System.Windows.Forms.TextBox
$pinyinBox.Left = 16
$pinyinBox.Top = 96
$pinyinBox.Width = 370
$form.Controls.Add($pinyinBox)

$hintLabel = New-Object System.Windows.Forms.Label
$hintLabel.Text = "加入后请点 用户词库 / 应用用户词库 使其生效。"
$hintLabel.Left = 16
$hintLabel.Top = 126
$hintLabel.Width = 370
$hintLabel.Height = 20
$form.Controls.Add($hintLabel)

$okButton = New-Object System.Windows.Forms.Button
$okButton.Text = "加入"
$okButton.Left = 220
$okButton.Top = 154
$okButton.Width = 78
$okButton.DialogResult = [System.Windows.Forms.DialogResult]::OK
$form.Controls.Add($okButton)

$cancelButton = New-Object System.Windows.Forms.Button
$cancelButton.Text = "取消"
$cancelButton.Left = 308
$cancelButton.Top = 154
$cancelButton.Width = 78
$cancelButton.DialogResult = [System.Windows.Forms.DialogResult]::Cancel
$form.Controls.Add($cancelButton)

$form.AcceptButton = $okButton
$form.CancelButton = $cancelButton

$form.Add_Shown({
  if ($phraseBox.Text.Trim().Length -gt 0) {
    $pinyinBox.Focus() | Out-Null
  } else {
    $phraseBox.Focus() | Out-Null
  }
})

$result = $form.ShowDialog()
if ($result -ne [System.Windows.Forms.DialogResult]::OK) { exit 0 }

$phrase = $phraseBox.Text.Trim() -replace '[\t\r\n]', ' '
$pinyin = $pinyinBox.Text.Trim()
if ($phrase.Length -eq 0 -or $pinyin.Length -eq 0) { exit 0 }

try {
  $codeMap = Load-CodeMap (Join-Path $SharedDir "yime_pinyin_codes.tsv")
  $codeBuilder = New-Object System.Text.StringBuilder
  foreach ($item in ($pinyin -split "\s+")) {
    if ([string]::IsNullOrWhiteSpace($item)) { continue }
    $key = Normalize-Pinyin $item
    if (-not $codeMap.ContainsKey($key)) {
      [System.Windows.Forms.MessageBox]::Show("找不到拼音：" + $item, "添加用户词条", "OK", "Warning") | Out-Null
      exit 1
    }
    [void]$codeBuilder.Append($codeMap[$key][$Mode])
  }
  $code = $codeBuilder.ToString()
  if ($code.Length -eq 0) { exit 0 }

  New-Item -ItemType Directory -Path $UserDir -Force | Out-Null
  $lexiconPath = Join-Path $UserDir "custom_phrase.txt"
  if (-not (Test-Path -LiteralPath $lexiconPath)) {
    Set-Content -LiteralPath $lexiconPath -Encoding UTF8 -Value ("# PIME Yime user phrases" + [Environment]::NewLine + "# format: phrase<TAB>code<TAB>weight")
  }
  Add-Content -LiteralPath $lexiconPath -Encoding UTF8 -Value ($phrase + [char]9 + $code + [char]9 + "1000000")
  [System.Windows.Forms.MessageBox]::Show("已加入用户词库：" + $phrase + [Environment]::NewLine + "请点击 用户词库 / 应用用户词库 使其生效。", "添加用户词条", "OK", "Information") | Out-Null
} catch {
  [System.Windows.Forms.MessageBox]::Show($_.Exception.Message, "添加用户词条失败", "OK", "Error") | Out-Null
  exit 1
}
`
