# Pure supplied-evidence contract; NOT an execution capability or a native probe.
Set-StrictMode -Version 2.0
$script:SchemaPath=Join-Path $PSScriptRoot 'rime-pime-dp1u-isolated-preflight.schema.json'

function Assert-Dp1UShape($Value,$Schema,[string]$At) {
    if($Schema.type -eq 'object') {
        if($Value -isnot [pscustomobject]){throw "$At must be an object"}
        $names=@($Value.PSObject.Properties.Name)
        $expected=@($Schema.required)
        if($names.Count -ne $expected.Count){throw "$At field set mismatch"}
        foreach($name in $expected){
            if($names -cnotcontains $name){throw "$At missing $name"}
            Assert-Dp1UShape $Value.$name $Schema.properties.$name "$At.$name"
        }
    } elseif($Schema.type -eq 'boolean') {
        if($Value -isnot [bool]){throw "$At must be boolean"}
    } elseif($Schema.type -eq 'string') {
        if($Value -isnot [string] -or [string]::IsNullOrWhiteSpace($Value)){throw "$At must be nonempty string"}
        if($Value -cne $Value.Trim() -or $Value -match '[\x00-\x1f]'){throw "$At noncanonical string"}
    } else {throw 'Unsupported contract type'}
    if($Schema.PSObject.Properties['const'] -and $Value -cne $Schema.const){throw "$At constant mismatch"}
    if($Schema.PSObject.Properties['pattern'] -and $Value -cnotmatch $Schema.pattern){throw "$At pattern mismatch"}
}

function Get-Dp1UDigest($Authorization,$Schema,[string]$Domain='dp1u-authorization-v1') {
    # Schema-ordered, UTF-8 byte-length-prefixed scalar values. Independent of JSON whitespace / PS edition.
    $text=$Domain+';'
    foreach($name in $Schema.required){
        $v=$Authorization.$name
        if($v -is [bool]){$v=$v.ToString().ToLowerInvariant()}
        $text += $name+':'+[Text.Encoding]::UTF8.GetByteCount($v).ToString([Globalization.CultureInfo]::InvariantCulture)+':'+$v+';'
    }
    $sha=[Security.Cryptography.SHA256]::Create()
    try {return ([BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($text)))).Replace('-','').ToLowerInvariant()}
    finally {$sha.Dispose()}
}

function Assert-Dp1URoot([string]$Path,[bool]$Protected=$false) {
    # Lexical checks only. Future native adapter must independently prove no alias/reparse/hardlink.
    if($Path -cnotmatch '^[A-Z]:\\[^\\]+' -or $Path.EndsWith('\') -or
        $Path -match '[\x00-\x1f/"<>|?*%]' -or $Path.Substring(2).Contains(':')){throw 'Noncanonical absolute root'}
    foreach($part in $Path.Substring(3).Split('\')){
        if(-not $part -or $part -in @('.','..') -or $part -match '[ .]$|~|^(?i:CON|PRN|AUX|NUL|COM[0-9]|LPT[0-9])(?:\.|$)'){
            throw 'Ambiguous root component'
        }
    }
    if(-not $Protected -and $Path -match '(?i)\\(?:AppData|Windows|Program Files(?: \(x86\))?)(?:\\|$)'){throw 'Protected or private system location'}
}

function Test-RimePimeDp1UIsolatedPreflight {
    [CmdletBinding()]
    param($Evidence, [string]$TrustedApprovalSha256, [string]$NowUtc)
    $reasons=[Collections.Generic.List[string]]::new()
    $digest=''
    try {
        $schema=Get-Content -LiteralPath $script:SchemaPath -Raw | ConvertFrom-Json
        Assert-Dp1UShape $Evidence $schema 'evidence'
        $a=$Evidence.authorization;$p=$Evidence.preflight;$b=$Evidence.product_boundary
        $digest=Get-Dp1UDigest $a $schema.properties.authorization
        if($TrustedApprovalSha256 -cnotmatch '^[0-9a-f]{64}$' -or $TrustedApprovalSha256 -cne $digest){throw 'Independent approval digest missing or mismatched'}
        if((Get-Dp1UDigest $b $schema.properties.product_boundary 'dp1u-product-boundary-v1') -cne $a.product_boundary_sha256){throw 'Product boundary digest mismatch'}
        foreach($name in @('install_root','state_root','recovery_root')){
            if($b.$name -cne $a.$name){throw 'Product boundary root mismatch'}
        }
        $identities=@($b.clsid,$b.profile_guid,$b.peer_clsid,$b.peer_profile_guid)
        if(@($identities|Select-Object -Unique).Count -ne 4){throw 'Product COM/profile identity overlap'}
        foreach($name in @('runtime_endpoint','run_value_name','uninstall_key_name')){
            if($b.$name -ieq $b.('peer_'+$name)){throw 'Product endpoint or registry ownership overlap'}
        }
        $format='yyyy-MM-ddTHH:mm:ssZ'
        $style=[Globalization.DateTimeStyles]::AssumeUniversal -bor [Globalization.DateTimeStyles]::AdjustToUniversal
        $now=[DateTime]::ParseExact($NowUtc,$format,[Globalization.CultureInfo]::InvariantCulture,$style)
        $start=[DateTime]::ParseExact($a.approved_at_utc,$format,[Globalization.CultureInfo]::InvariantCulture,$style)
        $end=[DateTime]::ParseExact($a.expires_at_utc,$format,[Globalization.CultureInfo]::InvariantCulture,$style)
        $observed=[DateTime]::ParseExact($p.observed_at_utc,$format,[Globalization.CultureInfo]::InvariantCulture,$style)
        if($start -gt $now -or $end -le $now -or $end -le $start -or ($end-$start).TotalHours -gt 24){throw 'Approval outside bounded validity'}
        if($observed -lt $start -or $observed -gt $now -or ($now-$observed).TotalMinutes -gt 5){throw 'Preflight observation stale or future'}
        foreach($name in @('run_id','target_name','target_machine_id','initiating_sid','state_root','install_root',
            'recovery_root','package_sha256','canonical_receipt_sha256','product_boundary_sha256')){
            if($a.$name -cne $p.$name){throw "Observed authorization binding mismatch: $name"}
        }
        if($a.target_name -match '(?i)^MYCOMPUTER(?:\.|$)' -or $p.target_name -match '(?i)^MYCOMPUTER(?:\.|$)'){
            throw 'MYCOMPUTER daily-use local.12 target prohibited'
        }
        foreach($sid in @($p.process_sid,$p.elevation_worker_sid,$p.runtime_sid)){
            if($sid -cne $a.initiating_sid){throw 'Initiating SID chain mismatch'}
        }
        if($p.registry_hku_path -cne ('HKEY_USERS\'+$a.initiating_sid)){throw 'Registry user scope mismatch'}
        $roots=@($a.install_root,$a.state_root,$a.recovery_root,$b.peer_install_root,$b.peer_state_root,
            $b.peer_recovery_root,$b.production_install_root,$b.production_state_root)
        for($i=0;$i -lt $roots.Count;$i++){Assert-Dp1URoot $roots[$i] ($i -ge 3)}
        for($i=0;$i -lt $roots.Count;$i++){
            for($j=$i+1;$j -lt $roots.Count;$j++){
                if($roots[$i].Equals($roots[$j],[StringComparison]::OrdinalIgnoreCase) -or
                    $roots[$i].StartsWith($roots[$j]+'\',[StringComparison]::OrdinalIgnoreCase) -or
                    $roots[$j].StartsWith($roots[$i]+'\',[StringComparison]::OrdinalIgnoreCase)){throw 'Overlapping product/state/recovery roots'}
            }
        }
    } catch {$reasons.Add($_.Exception.Message)}
    [pscustomobject][ordered]@{
        schema_version='yime-rime-pime-dp1u-isolated-preflight-result-v1'
        supplied_contract_valid=($reasons.Count -eq 0)
        authorization_sha256=$digest
        reasons=@($reasons)
        execution_authorized=$false
        native_target_verified=$false
        registration_gate_passed=$false;rollback_gate_passed=$false
        removal_gate_passed=$false;runtime_gate_passed=$false;dp1_u_acceptance_passed=$false
    }
}
Export-ModuleMember -Function Test-RimePimeDp1UIsolatedPreflight
