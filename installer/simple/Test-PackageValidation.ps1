$ErrorActionPreference='Stop';Set-StrictMode -Version 2.0
Import-Module (Join-Path $PSScriptRoot 'Product.psm1') -Force
$work=Join-Path ([IO.Path]::GetTempPath()) ('yime-package-validation-'+[guid]::NewGuid().ToString('N'))
$resources=@('profile-icon.ico','bin/YimeCoreInputToolbar.exe','bin/YimeCoreTrainer.exe','bin/YimeCoreToolCenter.exe')
function New-Fixture([string]$Product,[string]$Missing=''){
    $root=Join-Path $work ([guid]::NewGuid().ToString('N'))
    $info=Get-Product $Product
    $names=@(('x64/'+$info.dll),('x86/'+$info.dll),$info.exe.Replace('\','/'))
    if($Product -eq 'yimecore'){
        $names+=@('x64/YimeTextServiceRegistration.exe','x86/YimeTextServiceRegistration.exe',
            'bin/YimeBroker.exe','indexes/full.yidx','indexes/variable.yidx','indexes/shorthand.yidx',
            'data/yime_pinyin_codes.tsv','data/fonts/YinYuan-Regular.ttf')+$resources
    }else{
        $names+=@('x64/PIMERegistrationStatus.exe','x86/PIMERegistrationStatus.exe',
            'backends.json','go-backend/server.exe','go-backend/input_methods/yime/ime.json',
            'go-backend/input_methods/yime/data/fonts/YinYuan-Regular.ttf')
    }
    # Omit the member from BOTH the manifest and payload: hashes/counts still agree.
    $files=@(foreach($name in $names){
        if($name -ceq $Missing){continue}
        $path=Join-Path $root ('payload/'+$name)
        $null=[IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($path))
        [IO.File]::WriteAllText($path,'synthetic fixture only: '+$name)
        @{path=$name;bytes=(Get-Item -LiteralPath $path).Length;sha256=(Get-ContentHash $path)}
    })
    $manifest=@{format='yime-simple-package-1';product=$Product;version='test';files=$files}
    [IO.File]::WriteAllText((Join-Path $root 'product-package.json'),($manifest|ConvertTo-Json -Depth 5))
    return $root
}
foreach($product in @('yimecore','rime-pime')){$null=Read-Package (New-Fixture $product)}
foreach($missing in $resources){
    $root=New-Fixture 'yimecore' $missing
    $message=''
    try{$null=Read-Package $root}catch{$message=$_.Exception.Message}
    if($message -cne ('Missing product resource: '+$missing)){throw ('Missing resource was not rejected: '+$missing+'; '+$message)}
}
Write-Output 'PASS: complete independent product fixtures accepted; missing icon and each runtime tool rejected despite consistent manifest hashes. No binaries executed.'
