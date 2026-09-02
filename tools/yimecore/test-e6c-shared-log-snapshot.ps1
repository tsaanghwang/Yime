[CmdletBinding()]
param()
$ErrorActionPreference='Stop'
$tokens=$null;$errors=$null
$source=Join-Path $PSScriptRoot 'capture-local-reboot-verification.ps1'
$ast=[System.Management.Automation.Language.Parser]::ParseFile($source,[ref]$tokens,[ref]$errors)
if($errors.Count){throw 'Reboot collector parse failed'}
$functionAst=$ast.Find({param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq 'Copy-SharedLogPrefix'},$true)
if(-not $functionAst){throw 'Shared log reader is missing'}
. ([scriptblock]::Create($functionAst.Extent.Text))
$repo=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..'))
$fixture=Join-Path $repo ('.tmp\yimecore-experiment\shared-log-regression-'+[Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $fixture|Out-Null
$live=Join-Path $fixture 'writer.log'
$snapshot=Join-Path $fixture 'snapshot.log'
$writer=[IO.File]::Open($live,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::ReadWrite)
try {
    $bytes=[Text.Encoding]::UTF8.GetBytes("first`nsecond`n")
    $writer.Write($bytes,0,$bytes.Length);$writer.Flush()
    $copied=Copy-SharedLogPrefix $live $snapshot
    if($copied.copied_bytes -ne $bytes.Length -or [IO.File]::ReadAllText($snapshot) -cne "first`nsecond`n"){throw 'Snapshot differs from the open log'}
    $more=[Text.Encoding]::UTF8.GetBytes("third`n")
    $writer.Write($more,0,$more.Length);$writer.Flush()
    if((Get-Item -LiteralPath $snapshot).Length -ne $bytes.Length){throw 'Snapshot changed after the writer appended'}
    $rejected=$false
    try{$null=Copy-SharedLogPrefix $live $snapshot}catch{$rejected=$true}
    if(-not $rejected){throw 'Existing evidence was overwritten'}
}finally{$writer.Dispose()}
Write-Host 'Shared log snapshot passed: live writer remains open, snapshot stays immutable, existing evidence is not overwritten.'
