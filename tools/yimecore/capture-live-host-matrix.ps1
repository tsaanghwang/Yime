[CmdletBinding()]
param(
    [Parameter(Mandatory)][int[]]$HostProcessId,
    [string]$StateRoot = (Join-Path $env:LOCALAPPDATA 'YimeCore Experimental Trial'),
    [Parameter(Mandatory)][string]$OutputPath
)

# Read-only live-host metadata collector. It does not inspect window titles,
# document text, command lines, clipboard content, settings, or learning data.
$ErrorActionPreference = 'Stop'

function Get-PeMachine([string]$Path) {
    $stream=[IO.File]::OpenRead($Path)
    try {
        $reader=[IO.BinaryReader]::new($stream)
        $stream.Position=0x3c
        $peOffset=$reader.ReadInt32()
        $stream.Position=$peOffset+4
        '0x{0:X4}' -f $reader.ReadUInt16()
    } finally {
        if($reader){$reader.Dispose()}
        $stream.Dispose()
    }
}

$record=[ordered]@{
    schema_version='yimecore-real-live-host-metadata-v1'
    generated_at=[DateTime]::UtcNow.ToString('o')
    computer_name=$env:COMPUTERNAME
    package=$null
    hosts=@()
    complete=$false
    passed=$false
    privacy=@{
        window_titles_read=$false
        command_lines_read=$false
        user_text_read=$false
        clipboard_read=$false
        learning_data_read=$false
    }
    side_effects=@{
        processes_changed=$false
        registry_changed=$false
        product_state_changed=$false
        default_input_method_changed=$false
    }
    limitation='Loaded-module metadata does not prove that the profile was active or that input behavior passed; join it only with the operator manual-result record.'
}

$installRoot=$null
try {
    $config=Get-Content -LiteralPath (Join-Path $StateRoot 'runtime-config.json') -Raw -Encoding UTF8|ConvertFrom-Json
    $installRoot=[IO.Path]::GetFullPath([string]$config.install_root)
    $manifestPath=Join-Path $installRoot 'package-manifest.json'
    $descriptor=Get-Content -LiteralPath (Join-Path $installRoot 'local-product.json') -Raw -Encoding UTF8|ConvertFrom-Json
    $metadata=Get-Content -LiteralPath (Join-Path $installRoot 'install-metadata.json') -Raw -Encoding UTF8|ConvertFrom-Json
    $record.package=[ordered]@{
        status='pass'
        version=[string]$descriptor.version
        git_commit=[string]$metadata.git_commit
        install_root=$installRoot
        manifest_sha256=(Get-FileHash -LiteralPath $manifestPath -Algorithm SHA256).Hash.ToLowerInvariant()
        expected_modules=[ordered]@{
            x64=Join-Path $installRoot 'x64\YimeTextServiceExperiment.dll'
            x86=Join-Path $installRoot 'x86\YimeTextServiceExperiment.dll'
        }
    }
} catch {
    $record.package=[ordered]@{status='unavailable';reason=$_.Exception.Message}
}

$hostRows=@()
foreach($processId in $HostProcessId) {
    $row=[ordered]@{
        process_id=$processId
        status='unavailable'
        reason=$null
        process_name=$null
        executable=$null
        executable_version=$null
        executable_sha256=$null
        pe_machine=$null
        architecture=$null
        started_at=$null
        expected_text_service=$null
        loaded_yime_modules=@()
        exact_current_module_verified=$false
    }
    try {
        $process=Get-Process -Id $processId -ErrorAction Stop
        $image=[IO.Path]::GetFullPath($process.MainModule.FileName)
        $machine=Get-PeMachine $image
        $arch=switch($machine){'0x8664'{'x64'};'0x014C'{'x86'};default{'unsupported'}}
        $expected=$null
        if($installRoot -and $arch -in @('x64','x86')){$expected=Join-Path $installRoot "$arch\YimeTextServiceExperiment.dll"}
        $modules=@($process.Modules|Where-Object {$_.ModuleName -eq 'YimeTextServiceExperiment.dll'}|ForEach-Object {
            $modulePath=[IO.Path]::GetFullPath($_.FileName)
            [ordered]@{path=$modulePath;sha256=(Get-FileHash -LiteralPath $modulePath -Algorithm SHA256).Hash.ToLowerInvariant()}
        })
        $exact=@($modules|Where-Object {$expected -and $_.path -ieq $expected})
        $row.process_name=$process.ProcessName
        $row.executable=$image
        $row.executable_version=(Get-Item -LiteralPath $image).VersionInfo.FileVersion
        $row.executable_sha256=(Get-FileHash -LiteralPath $image -Algorithm SHA256).Hash.ToLowerInvariant()
        $row.pe_machine=$machine
        $row.architecture=$arch
        $row.started_at=$process.StartTime.ToUniversalTime().ToString('o')
        $row.expected_text_service=$expected
        $row.loaded_yime_modules=$modules
        $row.exact_current_module_verified=($exact.Count -eq 1 -and $modules.Count -eq 1)
        if($arch -eq 'unsupported'){$row.status='fail';$row.reason="Unsupported PE machine $machine."}
        elseif(-not $installRoot){$row.status='unavailable';$row.reason='Current installed package could not be discovered.'}
        elseif($row.exact_current_module_verified){$row.status='pass';$row.reason='Exactly one current-package text-service DLL is loaded.'}
        else{$row.status='fail';$row.reason='The exact current-package text-service DLL is not loaded.'}
    } catch {
        $row.reason=$_.Exception.Message
    }
    $hostRows+=@([pscustomobject]$row)
}
$record.hosts=$hostRows
$record.complete=($record.package.status -eq 'pass' -and @($hostRows).Count -eq @($HostProcessId).Count -and @($hostRows|Where-Object {$_.status -eq 'unavailable'}).Count -eq 0)
$record.passed=($record.complete -and @($hostRows|Where-Object {$_.status -ne 'pass'}).Count -eq 0)

$target=[IO.Path]::GetFullPath($OutputPath)
if(Test-Path -LiteralPath $target){throw 'Refusing to overwrite existing evidence.'}
$parent=Split-Path -Parent $target
if(-not (Test-Path -LiteralPath $parent -PathType Container)){[void][IO.Directory]::CreateDirectory($parent)}
$json=$record|ConvertTo-Json -Depth 10
[IO.File]::WriteAllText($target,$json+"`r`n",[Text.UTF8Encoding]::new($false))
$json
