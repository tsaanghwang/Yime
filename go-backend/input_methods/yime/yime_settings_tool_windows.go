//go:build windows

package yime

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

$form = New-Object System.Windows.Forms.Form
$form.Text = "Yime Settings"
$form.StartPosition = "CenterScreen"
$form.Size = New-Object System.Drawing.Size(680, 420)
$form.MinimumSize = New-Object System.Drawing.Size(680, 420)
$form.MaximizeBox = $false

$title = New-Object System.Windows.Forms.Label
$title.Left = 16
$title.Top = 16
$title.Width = 620
$title.Height = 24
$title.Font = New-Object System.Drawing.Font("Microsoft YaHei UI", 12, [System.Drawing.FontStyle]::Bold)
$title.Text = "Settings-side standalone tool shell"
$form.Controls.Add($title)

$summary = New-Object System.Windows.Forms.Label
$summary.Left = 16
$summary.Top = 48
$summary.Width = 640
$summary.Height = 40
$summary.Text = "This tool keeps settings-oriented navigation out of the TSF callback path. It is the place to grow future user-facing settings without moving complexity back into the language bar."
$form.Controls.Add($summary)

$paths = @(
  @{ Label = "User data"; Value = $UserDir; Top = 112 },
  @{ Label = "Shared data"; Value = $SharedDir; Top = 156 },
  @{ Label = "Help docs"; Value = $HelpDir; Top = 200 },
  @{ Label = "Log dir"; Value = $LogDir; Top = 244 }
)

foreach ($pathInfo in $paths) {
  $label = New-Object System.Windows.Forms.Label
  $label.Left = 16
  $label.Top = [int]$pathInfo.Top
  $label.Width = 100
  $label.Height = 24
  $label.Text = [string]$pathInfo.Label
  $form.Controls.Add($label)

  $textbox = New-Object System.Windows.Forms.TextBox
  $textbox.Left = 124
  $textbox.Top = [int]$pathInfo.Top - 2
  $textbox.Width = 430
  $textbox.ReadOnly = $true
  $textbox.Text = [string]$pathInfo.Value
  $form.Controls.Add($textbox)

  $button = New-Object System.Windows.Forms.Button
  $button.Left = 566
  $button.Top = [int]$pathInfo.Top - 3
  $button.Width = 76
  $button.Height = 28
  $button.Text = "Open"
  $button.Tag = [string]$pathInfo.Value
  $button.Add_Click({ param($sender, $eventArgs) Open-Path $sender.Tag })
  $form.Controls.Add($button)
}

$guideButton = New-Object System.Windows.Forms.Button
$guideButton.Left = 16
$guideButton.Top = 304
$guideButton.Width = 180
$guideButton.Height = 32
$guideButton.Text = "Open settings guide"
$guideButton.Add_Click({ Open-Path (Join-Path $HelpDir "settings-and-data.md") })
$form.Controls.Add($guideButton)

$helpButton = New-Object System.Windows.Forms.Button
$helpButton.Left = 212
$helpButton.Top = 304
$helpButton.Width = 180
$helpButton.Height = 32
$helpButton.Text = "Open main help"
$helpButton.Add_Click({ Open-Path (Join-Path $HelpDir "README.md") })
$form.Controls.Add($helpButton)

$note = New-Object System.Windows.Forms.Label
$note.Left = 16
$note.Top = 352
$note.Width = 640
$note.Height = 36
$note.Text = "Next steps can add actual editable settings here while keeping the launcher contract stable."
$form.Controls.Add($note)

try {
  [void]$form.ShowDialog()
} catch {
  Show-Error $_.Exception.Message
}
`
