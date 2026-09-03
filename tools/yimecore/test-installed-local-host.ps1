[CmdletBinding()]
param([Parameter(Mandatory)][string]$OutputRoot)
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'development-scope.ps1')
$scope=Get-YimeCoreDevelopmentScope
if(Get-Process WINWORD -ErrorAction SilentlyContinue){throw 'Close Word before synthetic registered-host tests.'}
$repo=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..'))
$out=[IO.Path]::GetFullPath($OutputRoot)
if(-not $out.StartsWith((Join-Path $repo '.tmp\yimecore-experiment\'),[StringComparison]::OrdinalIgnoreCase) -or (Test-Path -LiteralPath $out)){throw 'Output must be a new experiment child.'}
$config=Get-Content (Join-Path $env:LOCALAPPDATA 'YimeCore Experimental Trial\runtime-config.json') -Raw|ConvertFrom-Json
$root=[string]$config.install_root
$dll=Join-Path $root 'x64\YimeTextServiceExperiment.dll'
$descriptor=Get-Content (Join-Path $root 'local-product.json') -Raw -Encoding UTF8|ConvertFrom-Json
$registered=(Get-ItemProperty ("Registry::HKEY_LOCAL_MACHINE\SOFTWARE\Classes\CLSID\"+[string]$descriptor.identity.clsid+'\InprocServer32')).'(default)'
if($registered -ne $dll){throw 'Registered x64 DLL differs from current installed package.'}
New-Item -ItemType Directory -Path $out|Out-Null
$originalLocal=$env:LOCALAPPDATA
$results=@()
try {
    foreach($mode in @('full','variable','shorthand')) {
        $isolated=Join-Path $out $mode
        New-Item -ItemType Directory -Path $isolated|Out-Null
        $env:LOCALAPPDATA=$isolated
        $pipe="\\.\pipe\YimeBroker-local-acceptance-$PID-$mode"
        $index=Join-Path $root "indexes\$mode.yidx"
        if(-not (Test-Path -LiteralPath $index)){throw "Missing installed index: $index"}
        $broker=Start-Process -FilePath (Join-Path $root 'bin\YimeBroker.exe') -ArgumentList ('-index "{0}" -mode {1} -named-pipe "{2}"' -f $index,$mode,$pipe) -WindowStyle Hidden -PassThru -RedirectStandardError (Join-Path $isolated 'broker-error.txt')
        try {
            Start-Sleep -Milliseconds 300
            if($broker.HasExited){throw 'Isolated Broker exited before host test; inspect broker-error.txt.'}
            $text=(& (Join-Path $root 'x64\YimeRegisteredHostTests.exe') $pipe 2>&1)|Out-String
            $code=$LASTEXITCODE
            $text|Set-Content -LiteralPath (Join-Path $isolated 'host.txt') -Encoding utf8
            if($code -ne 0){throw "Registered x64 $mode host failed: $text"}
            foreach($required in @('registered_candidate_commit=true','registered_default_candidate_keys_verified=true','delayed_async_edit_completion_verified=true','failed_async_edit_recovery_verified=true','retained_language_bar_after_deactivation_verified=true','registered_english_shift_passthrough_verified=true')) {
                if(-not $text.Contains($required)){throw "Missing $required"}
            }
            $results+=@{architecture='x64';mode=$mode;exit_code=$code;passed=$true}
        } finally {if($broker -and -not $broker.HasExited){Stop-Process -Id $broker.Id; $broker.WaitForExit()}}
    }
} finally {$env:LOCALAPPDATA=$originalLocal}
[ordered]@{schema_version='yimecore-installed-local-host-v1';development_scope=$scope;generated_at=(Get-Date).ToUniversalTime().ToString('o');
    package_root=$root;manifest_sha256=(Get-FileHash (Join-Path $root 'package-manifest.json')).Hash;
    dll_sha256=(Get-FileHash $dll).Hash;isolated_settings_and_broker=$true;registration_changed_by_runner=$false;
    results=$results;passed=($results.Count -eq 3)}|ConvertTo-Json -Depth 8|Set-Content -LiteralPath (Join-Path $out 'summary.json') -Encoding utf8
Write-Host 'Installed x64 registered-host tests passed in three modes.'
