[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'
$repo = 'C:\dev\Yime'
$temporary = Join-Path $repo '.tmp\current-readiness-delivery-20260927\rime'
$delivery = 'C:\dev\Yime-deliveries\current-readiness-20260927-0ab86312'
$evidence = Join-Path $delivery 'rime-evidence'
$output = Join-Path $delivery 'rime-build'
if (Test-Path -LiteralPath $output) { throw 'Rime output already exists; refusing overwrite' }
$null = [IO.Directory]::CreateDirectory($evidence)
Start-Transcript -LiteralPath (Join-Path $evidence 'build-transcript.log') -NoClobber
$commands = [Collections.Generic.List[object]]::new()
function Invoke-Native {
    param([string]$FilePath, [string[]]$ArgumentList)
    Write-Host ('COMMAND: '+$FilePath+' '+($ArgumentList -join ' '))
    $start = [DateTime]::UtcNow.ToString('o')
    & $FilePath @ArgumentList | Out-Host
    $code = $LASTEXITCODE
    $commands.Add([ordered]@{executable=$FilePath;arguments=$ArgumentList;workingDirectory=(Get-Location).Path;startedUtc=$start;endedUtc=[DateTime]::UtcNow.ToString('o');exitCode=$code})
    [IO.File]::WriteAllText((Join-Path $evidence 'commands.json'),($commands|ConvertTo-Json -Depth 8),[Text.UTF8Encoding]::new($false))
    if ($code -ne 0) { throw "Command failed ($code): $FilePath" }
}
function Remove-OutputTree {
    param([string]$Path)
    $full=[IO.Path]::GetFullPath($Path)
    if (-not $full.StartsWith($repo+'\',[StringComparison]::OrdinalIgnoreCase)) { throw 'Removal outside workspace' }
    if (-not ($full.StartsWith($repo+'\go-backend\build\',[StringComparison]::OrdinalIgnoreCase) -or $full.StartsWith($temporary+'\',[StringComparison]::OrdinalIgnoreCase))) { throw 'Removal outside intended output' }
    if (Test-Path -LiteralPath $full) {
        $item=Get-Item -LiteralPath $full -Force
        if ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) { throw 'Refusing linked output removal' }
        Write-Host "REMOVE VERIFIED BUILD OUTPUT: $full"
        Remove-Item -LiteralPath $full -Recurse -Force
    }
}
try {
    Set-Location -LiteralPath $repo
    $commit=(& git rev-parse HEAD).Trim()
    if (-not $commit.StartsWith('0ab86312')) { throw "Unexpected source $commit" }
    $dirty=@(& git status --porcelain --untracked-files=no)
    if ($LASTEXITCODE -ne 0 -or $dirty.Count -ne 0) { throw "Tracked source is not clean: $dirty" }
    [IO.File]::WriteAllText((Join-Path $evidence 'source-commit.txt'),$commit+"`n",[Text.UTF8Encoding]::new($false))
    Copy-Item -LiteralPath $PSCommandPath -Destination (Join-Path $evidence 'build-rime.ps1')
    Copy-Item -LiteralPath (Join-Path $repo 'go-backend\input_methods\yime\rime_runtime.lock.json') -Destination (Join-Path $evidence 'rime_runtime.lock.json')
    $env:HTTP_PROXY='http://127.0.0.1:1081'; $env:HTTPS_PROXY=$env:HTTP_PROXY
    . (Join-Path $repo 'tools\initialize-dev-environment.ps1')
    & (Join-Path $repo 'tools\assert-win32-build-prerequisites.ps1') -RepoRoot $repo -RequireToolchain
    Invoke-Native -FilePath 'cmake.exe' -ArgumentList @('--version')
    Invoke-Native -FilePath 'go.exe' -ArgumentList @('version')
    Invoke-Native -FilePath 'rustup.exe' -ArgumentList @('run','stable-i686-pc-windows-msvc','rustc','-vV')
    Invoke-Native -FilePath 'python.exe' -ArgumentList @('tools/verify_vendored_build_dependencies.py')
    foreach($spec in @(@('x86','Win32','build'),@('x64','x64','build64'))) {
        $native=Join-Path $temporary ('native-'+$spec[0])
        if(Test-Path -LiteralPath $native){throw "Native output exists: $native"}
        Invoke-Native -FilePath 'cmake.exe' -ArgumentList @('-S',$repo,'-B',$native,'-G','Visual Studio 17 2022','-A',$spec[1],'-DCMAKE_POLICY_VERSION_MINIMUM=3.5')
        Invoke-Native -FilePath 'cmake.exe' -ArgumentList @('--build',$native,'--config','Release','--target','PIMETextService','PIMERegistrationStatus','--parallel','8')
        $stage=Join-Path $repo ($spec[2]+'\PIMETextService\Release')
        $null=[IO.Directory]::CreateDirectory($stage)
        foreach($name in @('PIMETextService.dll','PIMERegistrationStatus.exe')) {
            Copy-Item -LiteralPath (Join-Path $native ('PIMETextService\Release\'+$name)) -Destination (Join-Path $stage $name) -Force
        }
        Copy-Item -LiteralPath (Join-Path $native 'CMakeCache.txt') -Destination (Join-Path $evidence ($spec[0]+'-CMakeCache.txt'))
    }
    Set-Location -LiteralPath (Join-Path $repo 'PIMELauncher')
    $env:CARGO_TARGET_DIR=Join-Path $repo 'PIMELauncher\target'
    if(-not ([IO.Path]::GetFullPath($env:CARGO_TARGET_DIR)).StartsWith($repo+'\PIMELauncher\',[StringComparison]::OrdinalIgnoreCase)){throw 'Unexpected Cargo target path'}
    Invoke-Native -FilePath 'rustup.exe' -ArgumentList @('run','stable-i686-pc-windows-msvc','cargo','clean','--release','--target','i686-pc-windows-msvc','--package','pimelauncher')
    Invoke-Native -FilePath 'rustup.exe' -ArgumentList @('run','stable-i686-pc-windows-msvc','cargo','build','--locked','--release','--target','i686-pc-windows-msvc')
    $launcher=Join-Path $repo 'build\PIMELauncher';$null=[IO.Directory]::CreateDirectory($launcher)
    Copy-Item -LiteralPath (Join-Path $env:CARGO_TARGET_DIR 'i686-pc-windows-msvc\release\PIMELauncher.exe') -Destination (Join-Path $launcher 'PIMELauncher.exe') -Force
    $env:CARGO_TARGET_DIR=$null
    Set-Location -LiteralPath $repo
    & (Join-Path $repo 'tools\verify-pe-architectures.ps1') -RepoRoot $repo -SkipPackagedRime
    $goRoot=Join-Path $repo 'go-backend'
    $package=Join-Path $goRoot 'build\go-backend'
    $rime=Join-Path $goRoot 'input_methods\yime'
    & (Join-Path $repo 'tools\verify-rime-runtime.ps1') -RuntimeDir $rime -LockFile (Join-Path $rime 'rime_runtime.lock.json')
    Remove-OutputTree -Path $package
    $null=[IO.Directory]::CreateDirectory($package)
    $env:GOOS='windows';$env:GOARCH='amd64';$env:CGO_ENABLED='0'
    $env:GOCACHE=Join-Path $repo '.tmp\go-cache';$env:GOTMPDIR=Join-Path $repo '.tmp\go-tmp'
    $null=[IO.Directory]::CreateDirectory($env:GOCACHE);$null=[IO.Directory]::CreateDirectory($env:GOTMPDIR)
    $version=(Get-Content -LiteralPath (Join-Path $repo 'version.txt') -Raw).Trim()
    $goWinres=Join-Path $goRoot 'build\tools\go-winres.exe'
    $null=[IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($goWinres))
    Set-Location -LiteralPath (Join-Path $repo 'third_party\go-winres')
    Invoke-Native -FilePath 'go.exe' -ArgumentList @('build','-mod=vendor','-trimpath','-buildvcs=false','-o',$goWinres,'.')
    Set-Location -LiteralPath $goRoot
    # Explicit -mod=readonly checks locked modules without go mod tidy edits.
    $apps=@(
        @('server.exe','.','YIME Go Backend Server','cli','rsrc_server',$false),
        @('reverse-lookup.exe','.\cmd\reverse-lookup-tool','Yime Reverse Lookup Tool','gui','cmd\reverse-lookup-tool\rsrc_reverse',$true),
        @('tool-hub.exe','.\cmd\tool-hub','Yime Tool Hub','gui','cmd\tool-hub\rsrc_hub',$true),
        @('yime-trainer.exe','.\cmd\yime-trainer','Yime Typing Trainer','gui','cmd\yime-trainer\rsrc_trainer',$true),
        @('input-toolbar.exe','.\cmd\input-toolbar','Yime Input Method Toolbar','gui','cmd\input-toolbar\rsrc_input_toolbar',$true),
        @('lexicon-manager.exe','.\cmd\lexicon-manager','Yime Lexicon Manager','gui','cmd\lexicon-manager\rsrc_lexicon',$true),
        @('system-lexicon-audit.exe','.\cmd\system-lexicon-audit','Yime System Lexicon Audit','gui','cmd\system-lexicon-audit\rsrc_audit',$true),
        @('lexicon-promotion-scan.exe','.\cmd\lexicon-promotion-scan','','','',$false),
        @('blocklist-manager.exe','.\cmd\blocklist-manager','Yime User Blocklist Manager','gui','cmd\blocklist-manager\rsrc_blocklist',$true),
        @('settings-tool.exe','.\cmd\settings-tool','Yime Settings Tool','gui','cmd\settings-tool\rsrc_settings',$true),
        @('diagnostics-tool.exe','.\cmd\diagnostics-tool','Yime Diagnostics Tool','gui','cmd\diagnostics-tool\rsrc_diagnostics',$true),
        @('yime-layout-designer.exe','.\cmd\yime-layout-designer','Yime Layout Designer','gui','cmd\yime-layout-designer\rsrc_layout_designer',$false)
    )
    foreach($app in $apps){
        $resource=if($app[4]){Join-Path $goRoot ($app[4]+'_windows_amd64.syso')}else{$null}
        if($resource -and (Test-Path -LiteralPath $resource)){throw "Resource already exists: $resource"}
        try {
            if($resource){Invoke-Native -FilePath $goWinres -ArgumentList @('simply','--arch','amd64','--product-version',$version,'--file-version',$version,'--product-name','YIME','--copyright','Copyright (C) 2026 Yime contributors','--file-description',$app[2],'--original-filename',$app[0],'--icon','input_methods\yime\icon.ico','--manifest',$app[3],'--out',$app[4])}
            $ldflags='-s -w '+$(if($app[5]){'-H=windowsgui '}else{''})+'-X main.version='+$version
            Invoke-Native -FilePath 'go.exe' -ArgumentList @('build','-mod=readonly','-trimpath','-buildvcs=false','-ldflags',$ldflags,'-o',(Join-Path $package $app[0]),$app[1])
        } finally {if($resource -and (Test-Path -LiteralPath $resource)){Remove-Item -LiteralPath $resource -Force}}
    }
    $methods=Join-Path $package 'input_methods';$null=[IO.Directory]::CreateDirectory($methods)
    foreach($method in Get-ChildItem -LiteralPath (Join-Path $goRoot 'input_methods') -Directory){
        if(Test-Path -LiteralPath (Join-Path $method.FullName 'ime.json')){Copy-Item -LiteralPath $method.FullName -Destination (Join-Path $methods $method.Name) -Recurse}
    }
    Get-ChildItem -LiteralPath $methods -Recurse -File -Force|Unblock-File
    foreach($relative in @('yime\brise','yime\icons\icons')){Remove-OutputTree -Path (Join-Path $methods $relative)}
    foreach($file in Get-ChildItem -LiteralPath $methods -Recurse -File -Filter '*.go'){Remove-Item -LiteralPath $file.FullName -Force}
    foreach($relative in @('yime\rime.dll.bak-32bit','yime\data\yime_core_trial.dict.yaml','yime\data\yime_core_trial.schema.yaml','yime\data\yime_core_trial_manifest.json')){
        $file=Join-Path $methods $relative;if(Test-Path -LiteralPath $file){Remove-Item -LiteralPath $file -Force}
    }
    [IO.File]::WriteAllText((Join-Path $goRoot 'build\backends.go-backend.json'),'[{"name":"go-backend","command":"go-backend\\server.exe","workingDir":"go-backend","params":""}]',[Text.UTF8Encoding]::new($false))
    Set-Location -LiteralPath $repo
    & (Join-Path $repo 'tools\verify-rime-runtime.ps1') -RuntimeDir (Join-Path $methods 'yime') -LockFile (Join-Path $rime 'rime_runtime.lock.json')
    & (Join-Path $repo 'tools\verify-pe-architectures.ps1') -RepoRoot $repo
    & (Join-Path $repo 'installer\simple\Build-RimePackage.ps1') -OutputRoot $output
    $dirtyAfter=@(& git status --porcelain --untracked-files=no)
    [IO.File]::WriteAllText((Join-Path $evidence 'tracked-status-after.txt'),($dirtyAfter -join "`n"),[Text.UTF8Encoding]::new($false))
    if($dirtyAfter.Count -ne 0){throw "Tracked source changed: $dirtyAfter"}
    Write-Host 'RIME_BUILD_SUCCESS'
} finally {Stop-Transcript}
