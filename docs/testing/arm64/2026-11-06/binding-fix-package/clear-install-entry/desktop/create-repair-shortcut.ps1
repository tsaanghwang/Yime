param(
    [Parameter(Mandatory=$true)][string]$LauncherPath,
    [Parameter(Mandatory=$true)][string]$ReportPath
)
$ErrorActionPreference = 'Stop'
$launcher = [IO.Path]::GetFullPath($LauncherPath)
$deliveryRoot = 'C:\dev\Yime-deliveries\18u-binding-636cef68-20261106'
$reportPathFull = [IO.Path]::GetFullPath($ReportPath)
if ([IO.Path]::GetDirectoryName($reportPathFull) -ne $PSScriptRoot -or (Test-Path -LiteralPath $reportPathFull)) {
    throw 'The report must be a new file in this observation directory.'
}
if ([IO.Path]::GetDirectoryName($launcher) -ne $deliveryRoot -or [IO.Path]::GetFileName($launcher) -ne '开始安装18u修复版.cmd' -or -not [IO.File]::Exists($launcher)) {
    throw 'Expected an existing launcher in the verified delivery directory.'
}
$desktop = [Environment]::GetFolderPath('DesktopDirectory')
if (-not $desktop -or -not [IO.Directory]::Exists($desktop)) { throw 'Desktop directory unavailable.' }
$shortcutPath = Join-Path $desktop '安装 18u ARM64 .5 修复包.lnk'
if (Test-Path -LiteralPath $shortcutPath) { throw 'Shortcut already exists; preserve it and inspect before changing.' }
$shell = New-Object -ComObject WScript.Shell
$shortcut = $shell.CreateShortcut($shortcutPath)
$shortcut.TargetPath = Join-Path ([Environment]::GetFolderPath('System')) 'cmd.exe'
$shortcut.Arguments = '/d /c ""' + $launcher + '""'
$shortcut.WorkingDirectory = $deliveryRoot
$shortcut.Description = '先检查旧组件占用，再通过标准安装器安装 18u ARM64 .5。保留安装结果和错误日志。'
$shortcut.WindowStyle = 1
$shortcut.IconLocation = (Join-Path ([Environment]::GetFolderPath('System')) 'msiexec.exe') + ',0'
$shortcut.Save()
$readback = $shell.CreateShortcut($shortcutPath)
if ($readback.TargetPath -ne $shortcut.TargetPath -or $readback.Arguments -ne $shortcut.Arguments -or $readback.WorkingDirectory -ne $deliveryRoot) {
    throw 'Saved shortcut properties did not match.'
}
$report = [ordered]@{
    schema='18u-repair-desktop-shortcut-v1'
    observedUtc=[DateTime]::UtcNow.ToString('o')
    shortcut=$shortcutPath
    target=$readback.TargetPath
    arguments=$readback.Arguments
    workingDirectory=$readback.WorkingDirectory
    shortcutSHA256=(Get-FileHash -LiteralPath $shortcutPath -Algorithm SHA256).Hash.ToLowerInvariant()
    launched=$false
    installed=$false
}
$report | ConvertTo-Json -Depth 5 | Out-File -LiteralPath $reportPathFull -Encoding utf8NoBOM -NoClobber
$report | ConvertTo-Json -Depth 5
