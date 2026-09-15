$ErrorActionPreference='Stop'
$work=Join-Path ([IO.Path]::GetTempPath()) ('yime-logging-'+[guid]::NewGuid().ToString('N'))
$null=[IO.Directory]::CreateDirectory($work)
foreach($name in @('Setup.ps1','Product.psm1')){[IO.File]::Copy((Join-Path $PSScriptRoot $name),(Join-Path $work $name))}
$shell=Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
$admin=([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
function Check-Log([int]$ExpectedExit,[string]$ExpectedText){
    $id=[guid]::NewGuid().ToString('N')
    # Missing/mocked package fails before any registry or process operation.
    $previous=$ErrorActionPreference
    try{
        $ErrorActionPreference='Continue'
        $output=& $shell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $work 'Setup.ps1') -Action Install -LogId $id 2>&1
    }finally{$ErrorActionPreference=$previous}
    if($LASTEXITCODE -ne $ExpectedExit){throw ('Wrong exit code: '+$LASTEXITCODE+'; '+($output -join "`n"))}
    $suffix=if($admin){'.admin.log'}else{'.user.log'}
    $path=Join-Path ([Environment]::GetFolderPath('UserProfile')) ('Yime Setup Logs\'+$id+$suffix)
    $text=Get-Content -LiteralPath $path -Raw
    foreach($wanted in @('Action: Install','FAILED stage: package check','Exception:',$ExpectedText)){
        if(-not $text.Contains($wanted)){throw ('Missing diagnostic in durable transcript: '+$wanted)}
    }
    [IO.File]::Delete($path)
}
Check-Log 1 'product-package.json'
# Verify that a cancelled operation is distinguishable from an arbitrary error.
[IO.File]::WriteAllText((Join-Path $work 'Product.psm1'),"function Read-Package { throw [OperationCanceledException]::new('synthetic-user-cancel') }; Export-ModuleMember -Function Read-Package")
Check-Log 2 'synthetic-user-cancel'
[IO.File]::WriteAllText((Join-Path $work 'Product.psm1'),"function Read-Package { throw [InvalidOperationException]::new('synthetic-UAC-cancel',[ComponentModel.Win32Exception]::new(1223)) }; Export-ModuleMember -Function Read-Package")
Check-Log 3 'synthetic-UAC-cancel'
Write-Output 'PASS: durable failure transcript, full exception, stage, operation cancellation and wrapped UAC cancellation. No installed product changed.'
exit 0
