[CmdletBinding()]
param()
$ErrorActionPreference='Stop'
$path='C:\Users\tsaan\AppData\Local\YimeCore Experimental Trial\runtime-status.json'
$raw=Get-Content -LiteralPath $path -Raw -Encoding UTF8
$default=$raw|ConvertFrom-Json
$asString=$raw|ConvertFrom-Json -DateKind String
$broken=[DateTimeOffset]::Parse($default.updated_at)
$roundtrip=[DateTimeOffset]::Parse([string]$asString.updated_at,[Globalization.CultureInfo]::InvariantCulture,[Globalization.DateTimeStyles]::RoundtripKind)
$record=[ordered]@{
  read_only=$true;product_processes_started_or_stopped=$false;powershell=$PSVersionTable.PSVersion.ToString()
  default_type=$default.updated_at.GetType().FullName;default_kind=$default.updated_at.Kind.ToString()
  default_roundtrip=$default.updated_at.ToString('o');default_string_cast=[string]$default.updated_at
  old_parse_utc=$broken.UtcDateTime.ToString('o');old_parse_offset=$broken.Offset.ToString()
  datetime_preserving_kind_utc=$default.updated_at.ToUniversalTime().ToString('o')
  json_string_type=$asString.updated_at.GetType().FullName;json_string_value=$asString.updated_at
  explicit_roundtrip_utc=$roundtrip.UtcDateTime.ToString('o')
}
$output=Join-Path $PSScriptRoot 'arm64-r2-status-timestamp-diagnostic.json'
if(Test-Path -LiteralPath $output){throw 'Preserve prior diagnostic.'}
$json=$record|ConvertTo-Json -Depth 6
[IO.File]::WriteAllText($output,$json,[Text.UTF8Encoding]::new($false))
$json
