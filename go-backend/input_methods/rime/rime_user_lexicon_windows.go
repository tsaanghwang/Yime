//go:build windows

package rime

import (
	"os/exec"
	"strings"
)

type userLexiconEntry struct {
	Phrase string
	Pinyin string
}

func (ime *IME) promptUserLexiconEntry() (userLexiconEntry, bool, error) {
	script := `
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[System.Windows.Forms.Application]::EnableVisualStyles()

$clipboardText = ""
try { $clipboardText = [System.Windows.Forms.Clipboard]::GetText() } catch {}

$form = New-Object System.Windows.Forms.Form
$form.Text = "添加用户词条"
$form.StartPosition = "CenterScreen"
$form.TopMost = $true
$form.Width = 420
$form.Height = 210
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

$okButton = New-Object System.Windows.Forms.Button
$okButton.Text = "加入"
$okButton.Left = 220
$okButton.Top = 132
$okButton.Width = 78
$okButton.DialogResult = [System.Windows.Forms.DialogResult]::OK
$form.Controls.Add($okButton)

$cancelButton = New-Object System.Windows.Forms.Button
$cancelButton.Text = "取消"
$cancelButton.Left = 308
$cancelButton.Top = 132
$cancelButton.Width = 78
$cancelButton.DialogResult = [System.Windows.Forms.DialogResult]::Cancel
$form.Controls.Add($cancelButton)

$form.AcceptButton = $okButton
$form.CancelButton = $cancelButton

if ($phraseBox.Text.Trim().Length -gt 0) {
  $pinyinBox.Focus() | Out-Null
} else {
  $phraseBox.Focus() | Out-Null
}

$result = $form.ShowDialog()
if ($result -eq [System.Windows.Forms.DialogResult]::OK) {
  $phrase = $phraseBox.Text.Trim() -replace '[\t\r\n]', ' '
  $pinyin = $pinyinBox.Text.Trim() -replace '[\t\r\n]', ' '
  if ($phrase.Length -gt 0 -and $pinyin.Length -gt 0) {
    [Console]::Output.Write($phrase + [char]9 + $pinyin)
  }
}
`
	cmd := exec.Command("powershell.exe", "-NoProfile", "-STA", "-ExecutionPolicy", "Bypass", "-Command", script)
	output, err := cmd.Output()
	if err != nil {
		return userLexiconEntry{}, false, err
	}
	text := strings.TrimSpace(string(output))
	if text == "" {
		return userLexiconEntry{}, false, nil
	}
	parts := strings.SplitN(text, "\t", 2)
	if len(parts) != 2 {
		return userLexiconEntry{}, false, nil
	}
	return userLexiconEntry{
		Phrase: strings.TrimSpace(parts[0]),
		Pinyin: strings.TrimSpace(parts[1]),
	}, true, nil
}
