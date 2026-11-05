# Isolated real Windows file handles / mapped image, no installed product mutation.
[CmdletBinding()]
param()
$ErrorActionPreference='Stop';Set-StrictMode -Version 2.0
$module=Import-Module (Join-Path $PSScriptRoot '../Product.psm1') -Force -PassThru
$base=Join-Path ([IO.Path]::GetTempPath()) ('yime-file-access-'+[guid]::NewGuid().ToString('N'))
$null=[IO.Directory]::CreateDirectory($base)
function Require([bool]$Value,[string]$Message){if(-not $Value){throw $Message}}
function Denied([string]$Root){
    $lines=[Collections.Generic.List[string]]::new();$refused=$false
    try{Wait-ProductFiles $Root -Silent | ForEach-Object {$lines.Add([string]$_)}}catch{$refused=$true}
    Require $refused 'Failed open must stop maintenance'
    return ($lines -join "`n")
}
Add-Type @'
using System;
using System.Runtime.InteropServices;
public static class FileAccessFixture {
    [DllImport("kernel32.dll", CharSet=CharSet.Unicode, SetLastError=true)]
    public static extern IntPtr LoadLibraryEx(string path, IntPtr file, uint flags);
    [DllImport("kernel32.dll")] public static extern bool FreeLibrary(IntPtr module);
}
'@
try{
    $one=Join-Path $base 'one';$two=Join-Path $base 'two'
    $null=[IO.Directory]::CreateDirectory($one);$null=[IO.Directory]::CreateDirectory($two)
    $first=Join-Path $one 'same.dll';$second=Join-Path $two 'same.dll'
    [IO.File]::WriteAllText($first,'keep-first');[IO.File]::WriteAllText($second,'keep-second')
    $before=Get-ContentHash $first
    $handle=[IO.File]::Open($first,'Open','Read','Read')
    try{
        $log=Denied $base
        Require ($log.Contains('sharing-violation') -and $log.Contains('"win32":32')) 'Sharing error lost'
        $record=($log -split "`n"|Where-Object {$_ -like 'File access failure:*'}) -replace '^File access failure: ',''|ConvertFrom-Json
        Require ($record.path -ceq $first) 'Full path must distinguish duplicate basenames'
        Require ($record.hresult -ceq '0x80070020') 'Original HRESULT lost'
        Require ($log.Contains('File users query:')) 'Actual Restart Manager query did not run'
        Require ((Get-ContentHash $first) -ceq $before) 'Failed probe changed bytes'
    }finally{$handle.Dispose()}
    Wait-ProductFiles $base -Silent
    [IO.File]::SetAttributes($first,[IO.FileAttributes]::ReadOnly)
    try{
        $log=Denied $base
        Require ($log.Contains('access-denied-or-mapped-image') -and $log.Contains('"win32":5')) 'Access denial misclassified'
    }finally{[IO.File]::SetAttributes($first,[IO.FileAttributes]::Normal)}
    # Map a private copy without running DllMain or loading dependency DLLs.
    $image=Join-Path $base 'mapped-version.dll'
    [IO.File]::Copy((Join-Path $env:SystemRoot 'System32/version.dll'),$image)
    $imageHash=Get-ContentHash $image
    $mapped=[FileAccessFixture]::LoadLibraryEx($image,[IntPtr]::Zero,1)
    Require ($mapped -ne [IntPtr]::Zero) 'Fixture image did not map'
    try{
        $log=Denied $base
        Require ($log.Contains('File access failure:')) 'Mapped image must stop replacement'
        Require ((Get-ContentHash $image) -ceq $imageHash) 'Mapped image changed'
    }finally{$null=[FileAccessFixture]::FreeLibrary($mapped)}
    Wait-ProductFiles $base -Silent
    # A diagnostic failure must never bypass a real blocked file.
    & $module {function script:Get-ProductFileUsers {param([string[]]$Paths) throw 'synthetic-query-unavailable'}}
    $handle=[IO.File]::Open($first,'Open','Read','Read')
    try{
        $log=Denied $base
        Require ($log.Contains('File users query unavailable:') -and $log.Contains('synthetic-query-unavailable')) 'Query failure hidden'
    }finally{$handle.Dispose()}
    $missing=Join-Path $base 'missing.dll'
    try{$stream=[IO.File]::Open($missing,'Open','ReadWrite','None');$stream.Dispose();throw 'Unexpected open'}
    catch{$failure=Get-ProductFileAccessFailure $missing $_.Exception}
    Require ($failure.win32 -eq 2 -and $failure.kind -ceq 'other-file-error') 'Other file errors misclassified'
    Require ((Get-ContentHash $first) -ceq $before) 'Fixture content changed'
    Write-Output 'PASS file access: sharing, full path, HRESULT, query, read-only denial, mapped DLL, release, query failure and missing file; no installed product changed'
}finally{
    # Resolve and confine cleanup to this newly created GUID directory.
    $resolved=[IO.Path]::GetFullPath($base)
    $temp=[IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\')+'\'
    if(-not $resolved.StartsWith($temp,[StringComparison]::OrdinalIgnoreCase) -or
        [IO.Path]::GetFileName($resolved) -notmatch '^yime-file-access-[a-f0-9]{32}$'){throw 'Unsafe fixture cleanup path'}
    Remove-Item -LiteralPath $resolved -Recurse -Force
    Remove-Module $module.Name -Force
}
