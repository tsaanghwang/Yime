//go:build windows

package yime

import (
	"encoding/json"
	"os"
	"path/filepath"
)

func (ime *IME) openToolHub() error {
	scriptPath, err := ime.ensureToolHubScript()
	if err != nil {
		return err
	}
	manifestPath, err := ime.ensureToolHubManifest()
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
		"-ManifestPath",
		manifestPath,
	)
}

func (ime *IME) ensureToolHubManifest() (string, error) {
	userDir := ime.userDir()
	sharedDir := ime.sharedDir()
	helpDir := ime.helpDir()
	if userDir == "" || sharedDir == "" || helpDir == "" {
		return "", os.ErrNotExist
	}
	lexiconManagerScript, err := ime.ensureUserLexiconManagerScript()
	if err != nil {
		return "", err
	}
	settingsToolScript, err := ime.ensureSettingsToolScript()
	if err != nil {
		return "", err
	}
	diagnosticsToolScript, err := ime.ensureDiagnosticsToolScript()
	if err != nil {
		return "", err
	}
	manifest := buildToolHubManifest(
		sharedDir,
		userDir,
		helpDir,
		filepath.Join(os.Getenv("LOCALAPPDATA"), "PIME", "Logs"),
		lexiconManagerScript,
		settingsToolScript,
		diagnosticsToolScript,
		ime.currentYimeMode(),
	)
	if err := validateToolHubManifest(manifest); err != nil {
		return "", err
	}
	if err := os.MkdirAll(userDir, 0o755); err != nil {
		return "", err
	}
	manifestPath := filepath.Join(userDir, "pime_yime_tool_hub.json")
	payload, err := json.MarshalIndent(manifest, "", "  ")
	if err != nil {
		return "", err
	}
	if err := os.WriteFile(manifestPath, payload, 0o644); err != nil {
		return "", err
	}
	return manifestPath, nil
}

func (ime *IME) ensureToolHubScript() (string, error) {
	userDir := ime.userDir()
	if userDir == "" {
		return "", os.ErrNotExist
	}
	if err := os.MkdirAll(userDir, 0o755); err != nil {
		return "", err
	}
	scriptPath := filepath.Join(userDir, "pime_yime_tool_hub.ps1")
	scriptContent := append([]byte{0xEF, 0xBB, 0xBF}, []byte(toolHubScript)...)
	if err := os.WriteFile(scriptPath, scriptContent, 0o644); err != nil {
		return "", err
	}
	return scriptPath, nil
}

const toolHubScript = `param(
  [string]$ManifestPath
)

$ErrorActionPreference = "Stop"
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[System.Windows.Forms.Application]::EnableVisualStyles()

function Show-Error {
  param([string]$Message)
  [System.Windows.Forms.MessageBox]::Show($Message, "Yime Tool Hub", "OK", "Error") | Out-Null
}

function Quote-ProcessArgument {
  param([string]$Value)
  if ($null -eq $Value) {
    return '""'
  }
  return ('"{0}"' -f $Value.Replace('"', '\"'))
}

function Get-SystemPowerShellPath {
  $systemRoot = $env:SystemRoot
  if (-not [string]::IsNullOrWhiteSpace($systemRoot)) {
    $candidate = Join-Path $systemRoot "System32\WindowsPowerShell\v1.0\powershell.exe"
    if (Test-Path -LiteralPath $candidate) {
      return $candidate
    }
  }
  return "powershell.exe"
}

function Start-ShellExecuteProcess {
  param(
    [string]$FilePath,
    [string[]]$Arguments = @(),
    [System.Diagnostics.ProcessWindowStyle]$WindowStyle = [System.Diagnostics.ProcessWindowStyle]::Normal
  )

  $startInfo = New-Object System.Diagnostics.ProcessStartInfo
  $startInfo.UseShellExecute = $true
  $startInfo.Verb = "open"
  $startInfo.FileName = $FilePath
  $startInfo.WindowStyle = $WindowStyle
  if ($Arguments -and $Arguments.Count -gt 0) {
    $startInfo.Arguments = ($Arguments | ForEach-Object { Quote-ProcessArgument ([string]$_) }) -join " "
  }
  [System.Diagnostics.Process]::Start($startInfo) | Out-Null
}

function Invoke-Tool {
  param($Tool)

  $shouldClose = [bool]$Tool.close_after_launch

  if ([string]::IsNullOrWhiteSpace($Tool.target_path)) {
    Show-Error ("Tool target path is empty: " + $Tool.id)
    return
  }

  switch ($Tool.action_type) {
    "open_path" {
      if (-not (Test-Path -LiteralPath $Tool.target_path)) {
        Show-Error ("Missing target: " + $Tool.target_path)
        return
      }
      Start-Process -FilePath $Tool.target_path | Out-Null
      return
    }
    "run_powershell" {
      if (-not (Test-Path -LiteralPath $Tool.target_path)) {
        Show-Error ("Missing script: " + $Tool.target_path)
        return
      }
      $arguments = @(
        "-NoProfile",
        "-STA",
        "-WindowStyle",
        "Hidden",
        "-ExecutionPolicy",
        "Bypass",
        "-File",
        $Tool.target_path
      )
      if ($Tool.arguments) {
        foreach ($argument in $Tool.arguments) {
          $arguments += [string]$argument
        }
      }
      Start-ShellExecuteProcess -FilePath (Get-SystemPowerShellPath) -Arguments $arguments -WindowStyle Hidden
      return $shouldClose
    }
    "run_executable" {
      if (-not (Test-Path -LiteralPath $Tool.target_path)) {
        Show-Error ("Missing executable: " + $Tool.target_path)
        return
      }
      $argumentLine = ""
      if ($Tool.arguments) {
        $argumentLine = ($Tool.arguments | ForEach-Object { Quote-ProcessArgument ([string]$_) }) -join " "
      }
      if ([string]::IsNullOrWhiteSpace($argumentLine)) {
        Start-Process -FilePath $Tool.target_path | Out-Null
      } else {
        Start-Process -FilePath $Tool.target_path -ArgumentList $argumentLine | Out-Null
      }
      return $shouldClose
    }
    default {
      Show-Error ("Unknown tool action: " + $Tool.action_type)
      return
    }
  }
}

if ([string]::IsNullOrWhiteSpace($ManifestPath) -or -not (Test-Path -LiteralPath $ManifestPath)) {
  Show-Error "Tool manifest is missing."
  exit 1
}

$manifest = Get-Content -LiteralPath $ManifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
if (-not $manifest.tools -or $manifest.tools.Count -eq 0) {
  Show-Error "Tool manifest did not contain any tools."
  exit 1
}

$toolCount = [int]$manifest.tools.Count
$columnCount = 2
$rowCount = [Math]::Ceiling($toolCount / [double]$columnCount)
$rowHeight = 52
$baseHeight = 176
$formHeight = $baseHeight + ($rowCount * $rowHeight)
if ($formHeight -lt 360) {
  $formHeight = 360
}

$form = New-Object System.Windows.Forms.Form
$form.Text = [string]$manifest.title
$form.StartPosition = "CenterScreen"
$form.Size = New-Object System.Drawing.Size(620, $formHeight)
$form.MinimumSize = New-Object System.Drawing.Size(620, 360)
$form.MaximizeBox = $false
$form.WindowState = [System.Windows.Forms.FormWindowState]::Normal
$closeTimer = New-Object System.Windows.Forms.Timer
$closeTimer.Interval = 800
$closeTimer.Add_Tick({
  $closeTimer.Stop()
  $form.Hide()
  $form.Close()
})
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
$title.Width = 560
$title.Height = 26
$title.Font = New-Object System.Drawing.Font("Microsoft YaHei UI", 12, [System.Drawing.FontStyle]::Bold)
$title.Text = [string]$manifest.title
$form.Controls.Add($title)

$summary = New-Object System.Windows.Forms.Label
$summary.Left = 16
$summary.Top = 48
$summary.Width = 580
$summary.Height = 44
$summary.Text = [string]$manifest.summary
$form.Controls.Add($summary)

$layout = New-Object System.Windows.Forms.TableLayoutPanel
$layout.Left = 16
$layout.Top = 104
$layout.Width = 580
$layout.Height = $rowCount * $rowHeight
$layout.ColumnCount = $columnCount
$layout.RowCount = $rowCount
for ($column = 0; $column -lt $columnCount; $column++) {
  $layout.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Percent, 50)))
}
for ($row = 0; $row -lt $rowCount; $row++) {
  $layout.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Absolute, $rowHeight)))
}
$form.Controls.Add($layout)

$toolTip = New-Object System.Windows.Forms.ToolTip

foreach ($tool in $manifest.tools) {
  $button = New-Object System.Windows.Forms.Button
  $button.Text = [string]$tool.label
  $button.Dock = "Fill"
  $button.Margin = New-Object System.Windows.Forms.Padding(6)
  if ($tool.description) {
    $toolTip.SetToolTip($button, [string]$tool.description)
  }
  $button.Add_Click({
    param($sender, $eventArgs)
    $closeHub = Invoke-Tool $sender.Tag
    if ($closeHub) {
      $closeTimer.Start()
    }
  })
  $button.Tag = $tool
  $layout.Controls.Add($button) | Out-Null
}

$note = New-Object System.Windows.Forms.Label
$note.Left = 16
$note.Top = 120 + ($rowCount * $rowHeight)
$note.Width = 580
$note.Height = 42
$note.Text = [string]$manifest.note
$form.Controls.Add($note)

try {
  [void]$form.ShowDialog()
} catch {
  Show-Error $_.Exception.Message
}
`
