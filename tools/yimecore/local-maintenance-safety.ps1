# Read-only helpers shared by the native-context recovery rehearsal.
function Get-YimeCoreSharedFileRecord([string]$Path) {
    # A journal writer denies the sharing mode used by Get-FileHash. Read with
    # compatible sharing, but reject observed changes instead of claiming a
    # quiesced snapshot. Actual backups still require stopping all writers.
    $before=(Get-Item -LiteralPath $Path).LastWriteTimeUtc
    $stream=[IO.File]::Open($Path,[IO.FileMode]::Open,[IO.FileAccess]::Read,([IO.FileShare]::ReadWrite -bor [IO.FileShare]::Delete))
    try {
        $length=$stream.Length
        $sha=[Security.Cryptography.SHA256]::Create()
        try{$hash=([BitConverter]::ToString($sha.ComputeHash($stream))).Replace('-','').ToLowerInvariant()}finally{$sha.Dispose()}
        if($stream.Length -ne $length -or (Get-Item -LiteralPath $Path).LastWriteTimeUtc -ne $before){throw "Data changed while being observed: $Path"}
        [ordered]@{bytes=$length;sha256=$hash}
    } finally {$stream.Dispose()}
}

function Assert-YimeCorePlainPath([string]$Path) {
    $cursor=[IO.Path]::GetFullPath($Path)
    while($cursor) {
        if(Test-Path -LiteralPath $cursor) {
            if((Get-Item -LiteralPath $cursor -Force).Attributes -band [IO.FileAttributes]::ReparsePoint) {
                throw "Reparse point rejected: $cursor"
            }
        }
        $cursor=Split-Path -Parent $cursor
    }
}

function Assert-YimeCoreArchiveRecords([string]$Root, $Records) {
    $rootPath=[IO.Path]::GetFullPath($Root).TrimEnd('\')
    Assert-YimeCorePlainPath $rootPath
    $expected=@{}
    foreach($record in @($Records)) {
        $relative=[string]$record.path
        if(-not $relative -or [IO.Path]::IsPathRooted($relative) -or
            $relative -match '\\|:|(^|/)(\.|\.\.|)(/|$)|[. ](/|$)' -or $expected.ContainsKey($relative) -or
            [string]$record.sha256 -notmatch '^[a-fA-F0-9]{64}$' -or [long]$record.bytes -lt 0) {
            throw "Invalid or duplicate archive record: $relative"
        }
        $expected[$relative]=$record
    }
    $count=0
    foreach($item in Get-ChildItem -LiteralPath $rootPath -Recurse -Force) {
        if($item.Attributes -band [IO.FileAttributes]::ReparsePoint){throw "Indirect archive entry: $($item.FullName)"}
        if($item.PSIsContainer){continue}
        $relative=$item.FullName.Substring($rootPath.Length+1).Replace('\','/')
        $wanted=$expected[$relative]
        if(-not $wanted -or $item.Length -ne [long]$wanted.bytes -or
            (Get-FileHash -LiteralPath $item.FullName -Algorithm SHA256).Hash -ine [string]$wanted.sha256) {
            throw "Archive contains missing, changed or unlisted data: $relative"
        }
        $count++
    }
    if($count -ne $expected.Count){throw 'Archive file inventory does not match its manifest.'}
}

function Get-YimeCoreDataRecords([string]$StateRoot) {
    $root=[IO.Path]::GetFullPath($StateRoot)
    Assert-YimeCorePlainPath $root
    $files=@()
    $model=Join-Path $root 'user-model'
    if(Test-Path -LiteralPath $model) {
        # Inspect directories too; never follow a junction into another data store.
        Assert-YimeCorePlainPath $model
        foreach($item in Get-ChildItem -LiteralPath $model -Recurse -Force) {
            if($item.Attributes -band [IO.FileAttributes]::ReparsePoint){throw "Reparse point rejected: $($item.FullName)"}
            if(-not $item.PSIsContainer){$files+=@($item)}
        }
    }
    foreach($name in @('professional-lexicons.json','yime_blocklist.txt','yime_user_phrases.txt','yimecore_experimental_toolbar_state.json')) {
        $path=Join-Path $root $name
        Assert-YimeCorePlainPath $path
        if(Test-Path -LiteralPath $path -PathType Leaf){$files+=@(Get-Item -LiteralPath $path)}
    }
    @($files | ForEach-Object {
        $record=Get-YimeCoreSharedFileRecord $_.FullName
        [ordered]@{path=$_.FullName.Substring($root.Length+1).Replace('\','/');bytes=$record.bytes;sha256=$record.sha256}
    } | Sort-Object { $_.path })
}

function Assert-YimeCoreUnchangedData($Expected,$Actual) {
    if((ConvertTo-Json -InputObject @($Expected) -Depth 6 -Compress) -cne
       (ConvertTo-Json -InputObject @($Actual) -Depth 6 -Compress)) {
        throw 'Learning, user lexicon or settings changed after backup; refusing to overwrite newer data. Take a fresh backup.'
    }
}

function Convert-YimeCoreUtc($Value) {
    if($Value -is [datetime]){return $Value.ToUniversalTime()}
    return [DateTimeOffset]::Parse([string]$Value).UtcDateTime
}

function Test-YimeCoreLiveIdentity($Config,$Status,$Runtime,$Broker,$Boot) {
    if(-not $Runtime -or -not $Broker -or $Status.state -ne 'running'){return $false}
    try {
        $root=[IO.Path]::GetFullPath([string]$Config.install_root)
        $runtimePath=Join-Path $root 'bin\YimeCoreTrialRuntime.exe'
        $brokerPath=Join-Path $root 'bin\YimeBroker.exe'
        $rt=Convert-YimeCoreUtc $Runtime.CreationDate
        $bt=Convert-YimeCoreUtc $Broker.CreationDate
        $updated=Convert-YimeCoreUtc $Status.updated_at
        $bootUtc=Convert-YimeCoreUtc $Boot
        return [bool]($Runtime.ProcessId -eq $Status.runtime_pid -and $Broker.ProcessId -eq $Status.broker_pid -and
            $Broker.ParentProcessId -eq $Runtime.ProcessId -and
            [string]$Runtime.ExecutablePath -ieq $runtimePath -and [string]$Broker.ExecutablePath -ieq $brokerPath -and
            [string]$Config.runtime_path -ieq $runtimePath -and [string]$Config.broker_path -ieq $brokerPath -and
            [string]$Status.install_root -ieq $root -and [string]$Status.broker_path -ieq $brokerPath -and
            [string]$Status.state_root -ieq [string]$Config.state_root -and
            $rt -ge $bootUtc -and $bt -ge $rt -and $updated -ge $rt -and $updated -le [DateTime]::UtcNow.AddSeconds(5))
    } catch {return $false}
}

function Get-YimeCoreLiveRuntimeEvidence([string]$StateRoot) {
    $config=Get-Content -Encoding UTF8 -LiteralPath (Join-Path $StateRoot 'runtime-config.json') -Raw|ConvertFrom-Json
    $status=Get-Content -Encoding UTF8 -LiteralPath (Join-Path $StateRoot 'runtime-status.json') -Raw|ConvertFrom-Json
    $runtime=Get-CimInstance Win32_Process -Filter "ProcessId=$([int]$status.runtime_pid)"
    $broker=Get-CimInstance Win32_Process -Filter "ProcessId=$([int]$status.broker_pid)"
    $boot=(Get-CimInstance Win32_OperatingSystem).LastBootUpTime
    $passed=Test-YimeCoreLiveIdentity $config $status $runtime $broker $boot
    $sid=[Security.Principal.WindowsIdentity]::GetCurrent().User.Value
    $owners=@()
    foreach($process in @($runtime,$broker)) {
        if($process){
            $owner=Invoke-CimMethod -InputObject $process -MethodName GetOwnerSid
            $owners+=@([ordered]@{pid=$process.ProcessId;sid=$owner.Sid;return_code=$owner.ReturnValue})
            if($owner.ReturnValue -ne 0 -or $owner.Sid -ne $sid){$passed=$false}
        }
    }
    [ordered]@{passed=$passed;boot_utc=(Convert-YimeCoreUtc $boot).ToString('o');
        runtime=($runtime|Select-Object ProcessId,ParentProcessId,ExecutablePath,CreationDate);
        broker=($broker|Select-Object ProcessId,ParentProcessId,ExecutablePath,CreationDate);owners=$owners;status=$status}
}

function Assert-YimeCoreNativeFile([string]$Path) {
    $full=[IO.Path]::GetFullPath($Path)
    Assert-YimeCorePlainPath $full
    $escaped=$full.Replace('\','\\').Replace("'","\'")
    $native=Get-CimInstance CIM_DataFile -Filter "Name='$escaped'"
    if(-not $native -or [uint64]$native.FileSize -ne (Get-Item -LiteralPath $full).Length){throw "Archive/data file is not system-visible: $full"}
    [ordered]@{path=$full;bytes=[uint64]$native.FileSize;system_visible=$true;
        sha256=(Get-FileHash -LiteralPath $full -Algorithm SHA256).Hash.ToLowerInvariant()}
}

function Read-YimeCoreSystemKey([uint32]$Hive,[string]$Path) {
    $args=@{hDefKey=$Hive;sSubKeyName=$Path}
    $enumeration=Invoke-CimMethod -Namespace root/default -ClassName StdRegProv -MethodName EnumValues -Arguments $args
    if($enumeration.ReturnValue -eq 2){return [ordered]@{exists=$false}}
    if($null -eq $enumeration.ReturnValue -or $enumeration.ReturnValue -ne 0){throw "System key enumeration failed: $Path"}
    $values=@()
    for($i=0;$null -ne $enumeration.sNames -and $i -lt @($enumeration.sNames).Count;$i++) {
        $name=[string]$enumeration.sNames[$i];$kind=[int]$enumeration.Types[$i]
        $method=switch($kind){1{'GetStringValue'}2{'GetExpandedStringValue'}3{'GetBinaryValue'}4{'GetDWORDValue'}7{'GetMultiStringValue'}11{'GetQWORDValue'}default{throw "Unsupported registry kind $kind at $Path"}}
        $read=Invoke-CimMethod -Namespace root/default -ClassName StdRegProv -MethodName $method -Arguments (@{hDefKey=$Hive;sSubKeyName=$Path;sValueName=$name})
        if($null -eq $read.ReturnValue -or $read.ReturnValue -ne 0){throw "System registry read failed: $Path/$name"}
        $value=if($kind -in @(1,2,7)){$read.sValue}else{$read.uValue}
        # StdRegProv expands REG_EXPAND_SZ; the native process snapshot separately
        # retains its original unexpanded text. Both comparisons are mandatory.
        $values+=@([ordered]@{name=$name;kind=$kind;value=$value})
    }
    $subkeys=Invoke-CimMethod -Namespace root/default -ClassName StdRegProv -MethodName EnumKey -Arguments $args
    if($null -eq $subkeys.ReturnValue -or $subkeys.ReturnValue -ne 0){throw "System subkey enumeration failed: $Path"}
    $children=[ordered]@{}
    foreach($name in @($subkeys.sNames|Sort-Object)){$children[$name]=Read-YimeCoreSystemKey $Hive ($Path+'\'+$name)}
    [ordered]@{exists=$true;values=@($values|Sort-Object { $_.name });children=$children}
}
