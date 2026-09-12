# Loaded into the reviewed maintenance module. No mutation on import.
function Get-DefaultstringPeerControlPanel([string]$Sid){
    $m=Import-Module (Join-Path $PSScriptRoot 'rime-pime-peer-protection.psm1') -PassThru -Scope Local
    return & $m {
        param($sid)
        $root=$sid+'\Control Panel\International\User Profile'
        $c=Convert-YimePimeSystemRegistryCoordinate Users Shared $root
        $keys=Invoke-YimePimeSystemRegistryMethod EnumKey $c.hive $c.key 64
        if($keys.ReturnValue -ne 0){throw 'Peer Control Panel root missing.'}
        $found=@()
        foreach($path in @($root)+@($keys.sNames|ForEach-Object{$root+'\'+$_})){
            $values=Invoke-YimePimeSystemRegistryMethod EnumValues $c.hive $path 64
            if($values.ReturnValue -ne 0){throw 'Control Panel changed during observation.'}
            foreach($name in $values.sNames){
                if($name.IndexOf('{E40FA752-BB96-461D-A51D-F40EB437EC65}',[StringComparison]::OrdinalIgnoreCase) -lt 0){continue}
                if($name -ine '0804:{E40FA752-BB96-461D-A51D-F40EB437EC65}{126F54C6-E9B1-4E22-8652-03224CBD49F9}'){throw 'Unknown peer Control Panel reference.'}
                $found+=Get-YimePimeSystemRegistryValueRecord ([pscustomobject]@{id='peer-reference';hive='Users';view='Shared';key=$path;name=$name})
            }
        }
        if($found.Count -ne 1 -or -not $found[0].exists -or $found[0].value_kind -cne 'DWord'){throw 'Exact peer Control Panel DWORD reference required.'}
        return $found[0]
    } $Sid
}
function Assert-DefaultstringPeerDifference($Baseline,$Current,[string]$Sid) {
    $key=$Sid+'\SOFTWARE\Microsoft\CTF\TIP\{E40FA752-BB96-461D-A51D-F40EB437EC65}'
    $copy=$Current|ConvertTo-Json -Depth 90 -Compress|ConvertFrom-Json
    foreach($view in @('Registry32','Registry64')){
        $old=@($Baseline.registry|Where-Object {$_.hive -ceq 'Users' -and $_.view -ceq $view -and $_.key -ceq $key})
        $now=@($copy.registry|Where-Object {$_.hive -ceq 'Users' -and $_.view -ceq $view -and $_.key -ceq $key})
        if($old.Count -ne 1 -or $now.Count -ne 1 -or -not $old[0].exists){throw 'Fixed peer subtree binding is not exact.'}
        if($now[0].exists){
            if(($now[0]|ConvertTo-Json -Depth 90 -Compress) -cne ($old[0]|ConvertTo-Json -Depth 90 -Compress)){throw 'Existing peer TIP differs; overwrite forbidden.'}
        }else{
            if(@($now[0].values).Count -or @($now[0].children).Count){throw 'Absent peer tree contains unexpected data.'}
            $now[0].exists=$true;$now[0].values=$old[0].values;$now[0].children=$old[0].children
        }
    }
    if(($Baseline|ConvertTo-Json -Depth 90 -Compress) -cne ($copy|ConvertTo-Json -Depth 90 -Compress)){throw 'Peer changes extend beyond the admitted missing TIP; stop recovery.'}
}
function Assert-DefaultstringTipShape($Tree,[string]$Sid){
    $key=$Sid+'\SOFTWARE\Microsoft\CTF\TIP\{E40FA752-BB96-461D-A51D-F40EB437EC65}'
    $node=$Tree
    foreach($suffix in @('','\LanguageProfile','\LanguageProfile\0x00000804','\LanguageProfile\0x00000804\{126F54C6-E9B1-4E22-8652-03224CBD49F9}')){
        if($node.key -cne ($key+$suffix) -or $node.hive -cne 'Users' -or -not $node.exists){throw 'Original TIP shape differs from the reviewed recovery scope.'}
        if($suffix.EndsWith('}')){
            if(@($node.children).Count -ne 0 -or @($node.values).Count -ne 1){throw 'Unexpected original TIP leaf.'}
            $v=$node.values[0]
            if($v.name -cne 'Enable' -or $v.value_kind -cne 'DWord' -or $v.value -ne 1 -or -not $v.exists){throw 'Original Enable is not DWORD 1.'}
        }else{
            if(@($node.values).Count -ne 0 -or @($node.children).Count -ne 1){throw 'Unexpected original TIP intermediate node.'}
            $node=$node.children[0]
        }
    }
}
function Restore-DefaultstringPeerTip($Context,$Baseline,[string]$EvidenceRoot){
    $peer=Import-Module (Join-Path $PSScriptRoot 'rime-pime-peer-protection.psm1') -PassThru -Scope Local
    $sid=$Context.authorization.initiating_sid
    $before=& $peer {param($b,$s) Get-RimePimePeerProtectionSnapshot $b $s} $Context.boundary $sid
    Write-MaintenancePeerEvidence (Join-Path $EvidenceRoot 'peer-before-repair.json') $before
    Assert-DefaultstringPeerDifference $Baseline $before $sid
    $trees=@($Baseline.registry|Where-Object {$_.hive -ceq 'Users' -and $_.key -ceq ($sid+'\SOFTWARE\Microsoft\CTF\TIP\{E40FA752-BB96-461D-A51D-F40EB437EC65}')})
    if($trees.Count -ne 2){throw 'Both original views required.'}
    foreach($tree in $trees){Assert-DefaultstringTipShape $tree $sid}
    $missing=@($before.registry|Where-Object {$_.hive -ceq 'Users' -and $_.key -ceq $trees[0].key -and -not $_.exists})
    if($missing.Count -notin @(0,2)){throw 'User TIP observations disagree across views.'}
    if($missing.Count -eq 2){
        # Shared user TIP: one write, two independent post-write observations.
        # No deletion on failure: retain partial evidence for explicit review.
        & $peer {
            param($root)
            if(Test-YimePimeSystemRegistryKeyExists Users Shared $root){throw 'Peer TIP appeared before write; stop.'}
            $leaf=$root+'\LanguageProfile\0x00000804\{126F54C6-E9B1-4E22-8652-03224CBD49F9}'
            $c=Convert-YimePimeSystemRegistryCoordinate Users Shared $leaf
            $null=Invoke-YimePimeSystemRegistryMethod -Method CreateKey -Hive $c.hive -Key $c.key -ProviderArchitecture 64
            $r=Invoke-YimePimeSystemRegistryMethod -Method SetDWORDValue -Hive $c.hive -Key $c.key -ProviderArchitecture 64 -Values @{sValueName='Enable';uValue=[uint32]1}
            if($r.ReturnValue -ne 0){throw 'Peer Enable write failed.'}
        } $trees[0].key
    }
    $after=& $peer {param($b,$s) Get-RimePimePeerProtectionSnapshot $b $s} $Context.boundary $sid
    Write-MaintenancePeerEvidence (Join-Path $EvidenceRoot 'peer-after-repair.json') $after
    & $peer {param($a,$b) Assert-RimePimePeerProtectionUnchanged $a $b} $Baseline $after
}
