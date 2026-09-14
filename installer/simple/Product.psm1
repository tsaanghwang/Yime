Set-StrictMode -Version 2.0
$ErrorActionPreference='Stop'

function Get-Product([string]$Id){
    switch($Id){
        'yimecore' { return [pscustomobject]@{id=$Id;name='YimeCore';directory='YimeCore';state='YimeCore Experimental Trial';clsid='{E40FA752-BB96-461D-A51D-F40EB437EC65}';profile='{126F54C6-E9B1-4E22-8652-03224CBD49F9}';dll='YimeTextServiceExperiment.dll';exe='bin\YimeCoreTrialRuntime.exe'} }
        'rime-pime' { return [pscustomobject]@{id=$Id;name='Yime Rime-PIME';directory='Yime Rime-PIME';state='PIME\Rime';clsid='{35F67E9D-A54D-4177-9697-8B0AB71A9E04}';profile='{3F6B5A12-8D44-4E71-9A2E-6B4F9C1D2A30}';dll='PIMETextService.dll';exe='PIMELauncher.exe'} }
        default {throw 'Unknown product'}
    }
}
function Assert-PlainPath([string]$Path){
    $full=[IO.Path]::GetFullPath($Path).TrimEnd('\')
    if($full -notmatch '^[A-Za-z]:\\' -or $full.Substring(2).Contains(':') -or $full.Length -le 3){throw 'A local product directory is required'}
    for($p=$full;$p;$p=[IO.Path]::GetDirectoryName($p)){
        if((Test-Path -LiteralPath $p) -and ((Get-Item -LiteralPath $p -Force).Attributes -band [IO.FileAttributes]::ReparsePoint)){throw 'Linked product paths are not supported'}
    }
    return $full
}
function Get-ProductFiles([string]$Root){
    $root=Assert-PlainPath $Root
    $pending=[Collections.Generic.Stack[string]]::new();$pending.Push($root)
    while($pending.Count){
        foreach($item in Get-ChildItem -LiteralPath $pending.Pop() -Force){
            if($item.Attributes -band [IO.FileAttributes]::ReparsePoint){throw 'Linked files are not supported'}
            if($item.PSIsContainer){$pending.Push($item.FullName)}else{$item}
        }
    }
}
function Get-ContentHash([string]$Path){
    $stream=[IO.File]::OpenRead($Path);$sha=[Security.Cryptography.SHA256]::Create()
    try{return ([BitConverter]::ToString($sha.ComputeHash($stream))).Replace('-','').ToLowerInvariant()}
    finally{$sha.Dispose();$stream.Dispose()}
}
function Read-Package([string]$Root){
    $root=Assert-PlainPath $Root
    $manifest=Get-Content -LiteralPath (Join-Path $root 'product-package.json') -Raw -Encoding UTF8|ConvertFrom-Json
    if($manifest.format -cne 'yime-simple-package-1'){throw 'Unsupported package'}
    $product=Get-Product $manifest.product
    $seen=[Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach($row in $manifest.files){
        if($row.path -match '(^[/\\]|:|(^|[/\\])\.\.?([/\\]|$))' -or -not $seen.Add($row.path)){throw 'Invalid package member'}
        $path=Assert-PlainPath (Join-Path $root ('payload\'+$row.path))
        if(-not $path.StartsWith($root+'\payload\',[StringComparison]::OrdinalIgnoreCase)){throw 'Package member escaped payload'}
        if((Get-Item -LiteralPath $path).Length -ne $row.bytes -or (Get-ContentHash $path) -cne $row.sha256){throw ('Package damaged: '+$row.path)}
    }
    $actual=@(Get-ProductFiles (Join-Path $root 'payload'))
    if($actual.Count -ne $seen.Count){throw 'Package contains unlisted files'}
    foreach($arch in @('x64','x86')){
        if(-not $seen.Contains($arch+'/'+$product.dll)){throw ('Missing text service: '+$arch)}
        if($product.id -eq 'yimecore' -and -not $seen.Contains($arch+'/YimeTextServiceRegistration.exe')){throw 'Missing native registration tool'}
        if($product.id -eq 'rime-pime' -and -not $seen.Contains($arch+'/PIMERegistrationStatus.exe')){throw 'Missing native registration verifier'}
    }
    if(-not $seen.Contains($product.exe.Replace('\','/'))){throw 'Missing runtime'}
    $required=if($product.id -eq 'yimecore'){@('bin/YimeBroker.exe','indexes/full.yidx','indexes/variable.yidx','indexes/shorthand.yidx','data/yime_pinyin_codes.tsv','data/fonts/YinYuan-Regular.ttf')}else{@('backends.json','go-backend/server.exe','go-backend/input_methods/yime/ime.json','go-backend/input_methods/yime/data/fonts/YinYuan-Regular.ttf')}
    foreach($name in $required){if(-not $seen.Contains($name)){throw ('Missing product resource: '+$name)}}
    return [pscustomobject]@{root=$root;manifest=$manifest;product=$product}
}
function Assert-OwnedDirectory([string]$Root,[string]$Product){
    $root=Assert-PlainPath $Root
    if(-not (Test-Path -LiteralPath $root)){return}
    $marker=Join-Path $root '.yime-product.json'
    if(-not (Test-Path -LiteralPath $marker)){
        if(@(Get-ChildItem -LiteralPath $root -Force).Count){throw 'Directory is not owned by this installer; do not erase it'}
        return
    }
    $record=Get-Content -LiteralPath $marker -Raw -Encoding UTF8|ConvertFrom-Json
    if($record.product -cne $Product -or $record.format -cne 'yime-simple-install-1'){throw 'Directory belongs to another product'}
    $null=@(Get-ProductFiles $root)
}
function Wait-ProductFiles([string]$Root,[switch]$Silent){
    if(-not (Test-Path -LiteralPath $Root)){return}
    while($true){
        $busy=@(foreach($file in Get-ProductFiles $Root){
            try{$s=[IO.File]::Open($file.FullName,'Open','ReadWrite','None');$s.Dispose()}
            catch{$file.Name}
        })
        if(-not $busy.Count){return}
        if($Silent){throw ('Files unavailable: '+($busy -join ', '))}
        Add-Type -AssemblyName System.Windows.Forms
        $text="请保存工作并退出正在使用本输入法的应用，再选择重试。`r`n仍被占用或不可写：`r`n"+($busy -join "`r`n")+"`r`n无法释放时可以取消，正常重启后再运行。不会强制关闭文档应用。"
        if([Windows.Forms.MessageBox]::Show($text,'输入法安装维护','RetryCancel','Warning') -ne 'Retry'){throw [OperationCanceledException]::new('Cancelled')}
    }
}
function Copy-ProductPayload($Package,[string]$Destination){
    Assert-OwnedDirectory $Destination $Package.product.id
    $null=[IO.Directory]::CreateDirectory($Destination)
    # Write ownership first. A partially copied install can be removed/reinstalled.
    [IO.File]::WriteAllText((Join-Path $Destination '.yime-product.json'),(@{format='yime-simple-install-1';product=$Package.product.id;version=$Package.manifest.version}|ConvertTo-Json),[Text.UTF8Encoding]::new($false))
    foreach($row in $Package.manifest.files){
        $target=Join-Path $Destination $row.path
        $null=[IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($target))
        [IO.File]::Copy((Join-Path $Package.root ('payload\'+$row.path)),$target,$true)
    }
}
function Remove-ProductDirectory([string]$Root,[string]$Product){
    Assert-OwnedDirectory $Root $Product
    if(Test-Path -LiteralPath $Root){
        $root=Assert-PlainPath $Root
        # Keep ownership until all other children are gone, including partial deletion.
        foreach($item in Get-ChildItem -LiteralPath $root -Force){
            if($item.Name -ne '.yime-product.json'){Remove-Item -LiteralPath $item.FullName -Recurse -Force}
        }
        $marker=Join-Path $root '.yime-product.json'
        if(Test-Path -LiteralPath $marker){Remove-Item -LiteralPath $marker -Force}
        Remove-Item -LiteralPath $root
    }
}
Export-ModuleMember -Function *-*
