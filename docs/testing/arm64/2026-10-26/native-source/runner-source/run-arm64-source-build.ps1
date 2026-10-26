[CmdletBinding()]
param()
$ErrorActionPreference='Stop'
$repo=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$goBin=Join-Path $repo '.generated/arm64-toolchain/go1.25.14/go/bin'
$gitBin='C:\Users\tsaan\.cache\codex-runtimes\codex-primary-runtime\dependencies\native\git\cmd'
$cmakeBin='C:\Program Files\Microsoft Visual Studio\2022\BuildTools\Common7\IDE\CommonExtensions\Microsoft\CMake\CMake\bin'
if(-not(Test-Path -LiteralPath (Join-Path $cmakeBin 'cmake.exe'))){throw 'Wait for the completed Build Tools installation.'}
$installReceipt=Get-Content -LiteralPath (Join-Path $repo 'docs/testing/arm64/2026-10-26/native-build-toolchain-install.json') -Raw -Encoding utf8|ConvertFrom-Json
if($installReceipt.exit_code -ne 0 -or $installReceipt.restart_required){throw 'Toolchain installation must complete without a pending reboot before this run.'}
$env:PATH=$goBin+';'+$gitBin+';'+$cmakeBin+';'+$env:PATH
$env:GOTOOLCHAIN='local';$env:GOWORK='off'
$env:GOCACHE=Join-Path $repo '.tmp/arm64-go-native-20261026/gocache'
$env:GOMODCACHE=Join-Path $repo '.tmp/arm64-go-native-20261026/gomodcache'
$env:GOTMPDIR=Join-Path $repo '.tmp/arm64-go-native-20261026/gotmpdir'
$out=Join-Path $repo ('.tmp/yimecore-platform-experiments/arm64-'+(Get-Date -Format 'yyyyMMdd-HHmmss')+'-'+[guid]::NewGuid().ToString('N').Substring(0,8))
$receipt=Join-Path $repo '.generated/arm64-toolchain/native-build-location.json'
if(Test-Path -LiteralPath $receipt){throw 'Preserve previous native build pointer.'}
[ordered]@{build_root=$out;go_version=((& go version)-join ' ');cmake_version=((& cmake --version)-join ' ')}|ConvertTo-Json|Set-Content -LiteralPath $receipt -Encoding utf8
& (Join-Path $repo 'tools/yimecore/run-platform-experiment.ps1') -Target arm64 -Action Build -NativeGenerator 'Visual Studio 17 2022' -OutputRoot $out
