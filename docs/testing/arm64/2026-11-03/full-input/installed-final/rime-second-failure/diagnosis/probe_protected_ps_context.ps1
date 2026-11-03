[CmdletBinding()]
param([Parameter(Mandatory=$true)][string]$Report)
$ErrorActionPreference='Stop'
Set-StrictMode -Version 2.0
if(Test-Path -LiteralPath $Report){throw 'Preserve previous observer report'}
$admin=([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if(-not $admin){throw 'Expected same-account administrator observer'}
$rows=@()
foreach($architecture in @('x86','arm64')){
    $probe='C:\Program Files\Yime Rime-PIME\'+$architecture+'\PIMERegistrationStatus.exe'
    Write-Output ('BEGIN READ-ONLY PROBE '+$architecture)
    $errorText=''
    $nativeExit=$null
    try{
        & $probe 'verify-registered' | Out-Host
        $nativeExit=$LASTEXITCODE
    }catch{$errorText=$_.Exception.ToString()}
    Write-Output ('END READ-ONLY PROBE '+$architecture+' exit='+$nativeExit)
    $rows+=@{architecture=$architecture;exitCode=$nativeExit;error=$errorText}
}
$result=[ordered]@{
    schema='yime-rime-protected-powershell-readonly-observation-v1'
    capturedAtUTC=[DateTime]::UtcNow.ToString('o')
    administrator=$admin
    sid=[Security.Principal.WindowsIdentity]::GetCurrent().User.Value
    process=[Diagnostics.Process]::GetCurrentProcess().MainModule.FileName
    pshome=$PSHOME
    processArchitecture=[Runtime.InteropServices.RuntimeInformation]::ProcessArchitecture.ToString()
    environmentPath=$env:PATH
    environmentPathExt=$env:PATHEXT
    readOnly=$true
    registrationMutated=$false
    profileActivated=$false
    results=$rows
}
[IO.File]::WriteAllText($Report,($result|ConvertTo-Json -Depth 6),[Text.UTF8Encoding]::new($false))
Write-Output ('READ-ONLY RESULT '+$Report)
