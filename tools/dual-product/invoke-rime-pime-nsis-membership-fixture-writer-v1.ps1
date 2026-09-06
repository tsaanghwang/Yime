[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$Root,
    [Parameter(Mandatory)][ValidatePattern('^[0-9a-f]{64}$')][string]$ExpectedSidSha256
)

$ErrorActionPreference = 'Stop'
$repo = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..')).TrimEnd([char]92)
$parent = [IO.Path]::GetFullPath((Join-Path $repo '.tmp\dual-product')).TrimEnd([char]92)
$full = [IO.Path]::GetFullPath($Root).TrimEnd([char]92)
$relative = if ($full.StartsWith($parent + '\', [StringComparison]::OrdinalIgnoreCase)) {
    $full.Substring($parent.Length + 1)
} else { '' }
$segments = @($relative.Split([char]92, [StringSplitOptions]::RemoveEmptyEntries))
if ($segments.Count -lt 2 -or $segments[0] -cnotmatch '^dp1-j-membership-test-[A-Za-z0-9-]+$' -or
    -not (Test-Path -LiteralPath $full -PathType Container)) {
    throw 'Fixture writer rejected its root.'
}
$cursor = $full
while ($cursor.Length -ge $parent.Length -and
    ($cursor.Equals($parent, [StringComparison]::OrdinalIgnoreCase) -or
     $cursor.StartsWith($parent + '\', [StringComparison]::OrdinalIgnoreCase))) {
    $item = Get-Item -LiteralPath $cursor -Force
    if ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) { throw 'Fixture writer rejected a reparse path.' }
    if ($cursor.Equals($parent, [StringComparison]::OrdinalIgnoreCase)) { break }
    $cursor = Split-Path -Parent $cursor
}

$sid = [Security.Principal.WindowsIdentity]::GetCurrent().User.Value
$sha = [Security.Cryptography.SHA256]::Create()
try {
    $actual = ([BitConverter]::ToString($sha.ComputeHash([Text.UTF8Encoding]::new($false).GetBytes($sid)))).Replace('-', '').ToLowerInvariant()
}
finally { $sha.Dispose() }
if ($actual -cne $ExpectedSidSha256) { throw 'Fixture writer did not inherit the expected SID.' }

$path = Join-Path $full 'FOREIGN.TMP'
$stream = [IO.File]::Open($path, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write, [IO.FileShare]::Read)
try { $stream.WriteByte(0x4a); $stream.Flush($true) }
finally { $stream.Dispose() }
[IO.File]::Delete($path)
