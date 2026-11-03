# Actual installed-byte/marker verifier on isolated files. Process creation and
# token classification are mocked; no runtime, UAC, registry or installer runs.
[CmdletBinding()]
param()
$ErrorActionPreference='Stop';Set-StrictMode -Version 2.0
$module=Import-Module (Join-Path $PSScriptRoot '../Product.psm1') -Force -PassThru
$base=Join-Path ([IO.Path]::GetTempPath()) ('yime-startup-contract-'+[guid]::NewGuid().ToString('N'))
$base=Assert-PlainPath $base
$null=[IO.Directory]::CreateDirectory($base)
& $module {
    $script:launches=@();$script:administrator=$false
    function script:Test-SetupAdministrator {return $script:administrator}
    function script:Get-ProductInstallPaths {param($Product);return $script:fixturePaths}
    function script:Start-Sleep {param($Milliseconds)}
    function script:Start-Process {
        param($FilePath,$ArgumentList,$WorkingDirectory,$WindowStyle,[switch]$PassThru,$Verb)
        if($script:administrator -or $Verb){throw 'Mock observed an elevated runtime launch'}
        $script:launches+=,[pscustomobject]@{path=$FilePath;arguments=$ArgumentList;directory=$WorkingDirectory;window=$WindowStyle}
        $result=[pscustomobject]@{HasExited=$false}
        $result|Add-Member -MemberType ScriptMethod -Name Dispose -Value {}
        return $result
    }
}
function Write-Json($Path,$Value){[IO.File]::WriteAllText($Path,($Value|ConvertTo-Json -Depth 8),[Text.UTF8Encoding]::new($false))}
function New-Fixture([string]$Name,[string]$Id='yimecore',[string]$Descriptor=''){
    $root=Join-Path $base $Name;$null=[IO.Directory]::CreateDirectory((Join-Path $root '.setup'))
    $product=Get-Product $Id
    $names=@($product.exe.Replace('\','/'),'data/startup-check.txt')
    if($Id -eq 'yimecore-18u'){$names+='installed-18u-product.json'}
    $rows=@(foreach($name in $names){
        $p=Join-Path $root $name;$null=[IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($p))
        if($name -eq 'installed-18u-product.json'){Write-Json $p @{schema=$Descriptor}}
        else{[IO.File]::WriteAllText($p,('inert isolated fixture '+$name))}
        [ordered]@{path=$name;bytes=(Get-Item -LiteralPath $p).Length;sha256=(Get-ContentHash $p)}
    })
    $manifest=[ordered]@{format='yime-simple-package-2';product=$Id;version='startup-fixture';target='windows-arm64';host_architecture='arm64';tsf64_architecture='arm64x';files=$rows}
    if($Id -eq 'rime-pime'){$manifest.format='yime-simple-package-1';foreach($key in @('target','host_architecture','tsf64_architecture')){$manifest.Remove($key)}}
    elseif($Id -eq 'yimecore-18u'){$manifest.format='yime-simple-package-18u-1';$manifest.target='windows-amd64';$manifest.host_architecture='amd64';$manifest.tsf64_architecture='x64'}
    $json=Join-Path $root '.setup/product-package.json';Write-Json $json $manifest
    $parsed=Get-Content -LiteralPath $json -Raw -Encoding UTF8|ConvertFrom-Json
    $contract=Get-PackageContract $parsed
    Write-Json (Join-Path $root '.yime-product.json') @{format='yime-simple-install-1';product=$Id;version='startup-fixture';target=$contract.target}
    $state=Join-Path $base ($Name+'-state')
    & $module {param($r,$s);$script:fixturePaths=[pscustomobject]@{root=$r;state=$s};$script:administrator=$false;$script:launches=@()} $root $state
    return [pscustomobject]@{root=$root;manifest=$parsed;product=$product;contract=$contract;hash=(Get-ContentHash $json);state=$state}
}
function Assert-Refused($Fixture,[string]$Label){
    $refused=$false;try{Start-VerifiedInstalledRuntime $Fixture $Fixture.hash}catch{$refused=$true}
    if(-not $refused -or (& $module {$script:launches.Count}) -ne 0){throw ('Startup did not refuse before process launch: '+$Label)}
}
try{
    $fixture=New-Fixture 'standard'
    Start-VerifiedInstalledRuntime $fixture $fixture.hash
    $launch=@(& $module {$script:launches})
    if($launch.Count -ne 1 -or $launch[0].path -cne (Join-Path $fixture.root $fixture.product.exe) -or
       $launch[0].directory -cne $fixture.root -or $launch[0].window -cne 'Hidden' -or
       $launch[0].arguments -cne ('-install-root "{0}" -state-root "{1}"' -f $fixture.root,$fixture.state)){throw 'Ordinary standard launch arguments differ'}
    foreach($case in @('administrator','marker-missing','marker-product','marker-version','marker-target','marker-format','manifest-hash','runtime-hash','data-hash')){
        $fixture=New-Fixture $case
        $markerPath=Join-Path $fixture.root '.yime-product.json';$marker=Get-Content -LiteralPath $markerPath -Raw|ConvertFrom-Json
        switch($case){
            'administrator' {& $module {$script:administrator=$true}}
            'marker-missing' {[IO.File]::Delete($markerPath)}
            'marker-product' {$marker.product='rime-pime';Write-Json $markerPath $marker}
            'marker-version' {$marker.version='wrong';Write-Json $markerPath $marker}
            'marker-target' {$marker.target='windows-amd64';Write-Json $markerPath $marker}
            'marker-format' {$marker.format='foreign';Write-Json $markerPath $marker}
            'manifest-hash' {[IO.File]::AppendAllText((Join-Path $fixture.root '.setup/product-package.json'),' ')}
            'runtime-hash' {[IO.File]::AppendAllText((Join-Path $fixture.root $fixture.product.exe),'tampered')}
            'data-hash' {[IO.File]::AppendAllText((Join-Path $fixture.root 'data/startup-check.txt'),'tampered')}
        }
        Assert-Refused $fixture $case
    }
    $fixture=New-Fixture 'legacy-rime' 'rime-pime'
    Start-VerifiedInstalledRuntime $fixture $fixture.hash
    $launch=@(& $module {$script:launches})
    if($launch.Count -ne 1 -or $launch[0].path -cne (Join-Path $fixture.root 'PIMELauncher.exe') -or $launch[0].arguments){throw 'Legacy independent Rime startup changed'}
    $fixture=New-Fixture '18u-v1' 'yimecore-18u' 'installed-18u-product-v1'
    Start-VerifiedInstalledRuntime $fixture $fixture.hash
    if((& $module {$script:launches.Count}) -ne 0){throw 'Version-one 18u must not autostart'}
    $fixture=New-Fixture '18u-v2' 'yimecore-18u' 'installed-18u-product-v2'
    Start-VerifiedInstalledRuntime $fixture $fixture.hash
    $launch=@(& $module {$script:launches})
    $expected='--installed-18u-run --install-root "{0}" --manifest-sha256 {1}' -f $fixture.root,(Get-ContentHash (Join-Path $fixture.root 'installed-18u-product.json'))
    if($launch.Count -ne 1 -or $launch[0].arguments -cne $expected){throw 'Full 18u startup lost its checked descriptor'}
    # Check real Setup control flow as well as the runtime function's token gate.
    $setupPath=Join-Path $PSScriptRoot '../Setup.ps1'
    $tokens=$null;$errors=$null;$ast=[Management.Automation.Language.Parser]::ParseFile($setupPath,[ref]$tokens,[ref]$errors)
    if($errors.Count){throw 'Setup does not parse'}
    $calls=@($ast.FindAll({param($n) $n -is [Management.Automation.Language.CommandAst] -and $n.GetCommandName() -eq 'Start-VerifiedInstalledRuntime'},$true))
    if($calls.Count -ne 1){throw 'Setup must have exactly one verified ordinary-user launch site'}
    $parents=@();for($node=$calls[0].Parent;$node;$node=$node.Parent){if($node -is [Management.Automation.Language.IfStatementAst]){$parents+=,$node.Clauses[0].Item1.Extent.Text}}
    if('$code -eq 0 -and $Action -eq ''Install''' -cnotin $parents -or '-not $administrator' -cnotin $parents){throw 'Startup escaped the successful original nonadmin Install branch'}
    $condition=$calls[0].Parent
    while($condition -isnot [Management.Automation.Language.IfStatementAst]){$condition=$condition.Parent}
    foreach($scenario in @(@{code=7;action='Install';count=0},@{code=0;action='Uninstall';count=0},@{code=0;action='Install';count=1})){
        $package=New-Fixture ('control-'+$scenario.code+'-'+$scenario.action)
        $packageManifestHash=$package.hash;$code=$scenario.code;$Action=$scenario.action
        . ([scriptblock]::Create($condition.Extent.Text))
        if((& $module {$script:launches.Count}) -ne $scenario.count){throw 'Real post-UAC branch did not preserve action/exit-code gating'}
    }
    $setup=[IO.File]::ReadAllText($setupPath)
    if($setup.Substring($setup.IndexOf("`$stage='copy new product files'")).Contains('Start-Process')){throw 'Elevated installation tail must never launch runtime'}
    if(-not $setup.Contains('Installed from an administrator process. No runtime was started.')){throw 'Direct administrator caller must receive explicit no-start guidance'}
    # Execute the real, inert guard and verification-dispatch AST blocks. Native
    # probes are mocked; no registry, installed payload or product is accessed.
    & {
        $guards=@($ast.FindAll({param($n) $n -is [Management.Automation.Language.IfStatementAst] -and $n.Clauses[0].Item1.Extent.Text.StartsWith('$NativeRimeValidationDeferred -and')},$true))
        $dispatch=@($ast.FindAll({param($n) $n -is [Management.Automation.Language.IfStatementAst] -and $n.Clauses[0].Item1.Extent.Text -ceq '$product.id -eq ''rime-pime''' -and $n.Extent.Text.Contains('verify-registered')},$true))
        if($guards.Count -ne 1 -or $dispatch.Count -ne 1){throw 'Expected one guarded Rime stage handoff and registration dispatch'}
        foreach($case in @('parent','direct-admin','uninstall','check','18u','legacy','not-admin','no-sid','no-native-guard')){
            $Action='Install';$product=[pscustomobject]@{id='rime-pime'}
            $contract=[pscustomobject]@{target='windows-arm64';nativeDirectory='arm64'}
            $administrator=$true;$InitiatingSid='same-sid';$nativeMaintenance='verified native entry'
            $NativeRimeValidationDeferred=$true
            switch($case){
                'direct-admin' {$NativeRimeValidationDeferred=$false}
                'uninstall' {$Action='Uninstall'}
                'check' {$Action='Check'}
                '18u' {$product.id='yimecore-18u'}
                'legacy' {$contract.target='windows-amd64'}
                'not-admin' {$administrator=$false}
                'no-sid' {$InitiatingSid=''}
                'no-native-guard' {$nativeMaintenance=''}
            }
            $refused=$false;try{. ([scriptblock]::Create($guards[0].Extent.Text))}catch{$refused=$true}
            if($refused -ne ($case -notin @('parent','direct-admin'))){throw ('Unexpected stage handoff guard: '+$case)}
        }
        function Run-Native([string]$Path,[string[]]$Arguments){$script:rimeCalls+=,[pscustomobject]@{path=$Path;arguments=$Arguments}}
        foreach($case in @('parent','direct-admin','legacy','18u')){
            $product=[pscustomobject]@{id='rime-pime'};$contract=[pscustomobject]@{nativeDirectory='arm64'}
            $NativeRimeValidationDeferred=($case -eq 'parent')
            if($case -eq 'legacy'){$contract.nativeDirectory='x64'}
            if($case -eq '18u'){$product.id='yimecore-18u'}
            $root=Join-Path $base 'inert-rime-dispatch';$script:rimeCalls=@()
            . ([scriptblock]::Create($dispatch[0].Extent.Text))
            $expectedCount=if($case -in @('parent','18u')){0}else{2}
            if($script:rimeCalls.Count -ne $expectedCount){throw ('Rime verification dispatched in wrong stage: '+$case)}
            if($expectedCount){
                for($i=0;$i -lt 2;$i++){
                    $arch=@('x86',$contract.nativeDirectory)[$i]
                    if($script:rimeCalls[$i].path -cne (Join-Path $root ($arch+'\PIMERegistrationStatus.exe')) -or
                       ($script:rimeCalls[$i].arguments -join '|') -cne 'verify-registered'){throw 'Direct-admin or legacy strong registration check changed'}
                }
            }
        }
        Write-Output 'PASS 9 real Rime handoff guard cases and 4 registration dispatch cases; native calls mocked, no product execution.'
    }
    Write-Output 'PASS 13 isolated startup cases plus 3 actual post-UAC branch scenarios: normal standard/legacy Rime/full 18u, v1 no-start, administrator and 8 installed-integrity refusals; failed Install/Uninstall never launch. Token/process calls mocked; no system lifecycle.'
}finally{
    $resolved=Assert-PlainPath $base
    if($resolved -cne $base -or -not [IO.Path]::GetFileName($resolved).StartsWith('yime-startup-contract-')){throw 'Unexpected fixture cleanup path'}
    Remove-Item -LiteralPath $resolved -Recurse -Force
    Remove-Module $module.Name -Force
}
