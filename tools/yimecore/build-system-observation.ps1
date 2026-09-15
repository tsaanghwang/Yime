# Read-only registry observation for source builds.
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


function Assert-YimeCoreNativeFile([string]$Path) {
    $full=[IO.Path]::GetFullPath($Path)
    Assert-YimeCorePlainPath $full
    $escaped=$full.Replace('\','\\').Replace("'","\'")
    $native=Get-CimInstance CIM_DataFile -Filter "Name='$escaped'"
    if(-not $native -or [uint64]$native.FileSize -ne (Get-Item -LiteralPath $full).Length){throw "Archive/data file is not system-visible: $full"}
    [ordered]@{path=$full;bytes=[uint64]$native.FileSize;system_visible=$true;
        sha256=(Get-FileHash -LiteralPath $full -Algorithm SHA256).Hash.ToLowerInvariant()}
}
