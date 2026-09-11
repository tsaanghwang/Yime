[CmdletBinding()]
param([Parameter(Mandatory=$true)][string]$RequestPath)
$ErrorActionPreference='Stop'
# NSIS strings have a bounded length. Transfer each argument separately as data;
# never build a PowerShell expression from paths or concatenate a long command.
try{
    $stream=[IO.File]::Open($RequestPath,'Open','Read','Read')
    try{
        if($stream.Length -lt 2 -or $stream.Length -gt 32768 -or $stream.Length % 2){throw 'Invalid candidate request length.'}
        $reader=[IO.StreamReader]::new($stream,[Text.UnicodeEncoding]::new($false,$false,$true),$false)
        try{$text=$reader.ReadToEnd()}finally{$reader.Dispose()}
    }finally{$stream.Dispose()}
    $lines=$text.Split(@("`r`n"),[StringSplitOptions]::None)
    if($lines.Count -ne 9 -or $lines[8] -cne ''){throw 'Invalid candidate request field count.'}
    foreach($line in $lines){if($line -match '["\r\n\t\x00]' -or $line.EndsWith('\')){throw 'Ambiguous candidate request field.'}}
    if($lines[0] -cnotin @('Install','Remove','Resume')){throw 'Invalid candidate request mode.'}
    foreach($i in @(3,7)){if($lines[$i] -cnotmatch '^[0-9a-f]{64}$'){throw 'Invalid candidate request digest.'}}
    if(($lines[0] -ceq 'Install' -and $lines[6] -cne '') -or
       ($lines[0] -cne 'Install' -and $lines[6] -cnotmatch '^[0-9a-f]{64}$')){throw 'Invalid candidate request prepared digest.'}
    foreach($i in @(1,2,4,5)){if(-not [IO.Path]::IsPathRooted($lines[$i])){throw 'Candidate request path must be absolute.'}}
    $parameters=@{Mode=$lines[0];InstallerPath=$lines[1];AuthorizationPath=$lines[2];TrustedApprovalSha256=$lines[3];
        BoundaryPath=$lines[4];ReceiptPath=$lines[5];PreparedSha256=$lines[6];ExpectedManifestSha256=$lines[7];
        PackageRoot=(Split-Path -Parent $PSScriptRoot)}
    & (Join-Path $PSScriptRoot 'invoke-rime-pime-candidate.ps1') @parameters
    exit $LASTEXITCODE
}catch{Write-Error $_ -ErrorAction Continue;exit 51}
