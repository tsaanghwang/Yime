[CmdletBinding()]
param([Parameter(Mandatory)][string]$ShellRoot,[Parameter(Mandatory)][string]$ReportPath)
$ErrorActionPreference='Stop'
Set-StrictMode -Version 2.0
function Get-Machine([string]$Path){
    $stream=[IO.File]::OpenRead($Path)
    $reader=[IO.BinaryReader]::new($stream)
    try{
        if($reader.ReadUInt16() -ne 0x5a4d){throw "Not PE: $Path"}
        $stream.Position=60;$offset=$reader.ReadUInt32()
        if($offset -gt $stream.Length-6){throw "Invalid PE: $Path"}
        $stream.Position=$offset
        if($reader.ReadUInt32() -ne 0x00004550){throw "Invalid PE signature: $Path"}
        return $reader.ReadUInt16()
    }finally{$reader.Dispose();$stream.Dispose()}
}
if([Runtime.InteropServices.RuntimeInformation]::ProcessArchitecture.ToString() -cne 'Arm64'){
    throw 'Signature inspection must execute in native ARM64 PowerShell'
}
$root=[IO.Path]::GetFullPath($ShellRoot)
$records=@(foreach($name in @('pwsh.exe','coreclr.dll','clrjit.dll','hostfxr.dll','hostpolicy.dll')){
    $path=Join-Path $root $name
    $machine=Get-Machine $path
    if($machine -ne 0xaa64){throw "Shell component is not native ARM64: $name"}
    $signature=Get-AuthenticodeSignature -LiteralPath $path
    if($signature.Status.ToString() -cne 'Valid' -or -not $signature.SignerCertificate -or
       $signature.SignerCertificate.Subject -notmatch '(^|,\s*)O=Microsoft Corporation(,|$)'){
        throw "Shell component lacks a valid Microsoft signature: $name ($($signature.Status))"
    }
    [ordered]@{path=$name;machine='0xaa64';sha256=(Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant();
        signatureStatus=$signature.Status.ToString();subject=$signature.SignerCertificate.Subject;
        certificateThumbprint=$signature.SignerCertificate.Thumbprint;certificateNotAfter=$signature.SignerCertificate.NotAfter.ToUniversalTime().ToString('o')}
})
foreach($name in @('LICENSE.txt','ThirdPartyNotices.txt')){
    if(-not (Test-Path -LiteralPath (Join-Path $root $name) -PathType Leaf)){throw "Missing shell license: $name"}
}
$report=[ordered]@{schema=1;sourceRoot=$root;observedUtc=[DateTime]::UtcNow.ToString('o');
    processArchitecture='arm64';powerShellVersion=$PSVersionTable.PSVersion.ToString();processPSHOME=$PSHOME;files=$records}
[IO.File]::WriteAllText([IO.Path]::GetFullPath($ReportPath),($report|ConvertTo-Json -Depth 8),[Text.UTF8Encoding]::new($false))
Write-Output ('PASS: native Microsoft PowerShell '+$PSVersionTable.PSVersion+'; '+$records.Count+' signed native components')
