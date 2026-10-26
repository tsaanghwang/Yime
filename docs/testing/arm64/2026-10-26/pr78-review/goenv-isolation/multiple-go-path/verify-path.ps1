$ErrorActionPreference='Stop'
$matches=@(Get-Command go -CommandType Application -ErrorAction Stop)
if($matches.Count -lt 2){throw 'Multiple Go candidates were not reproduced'}
$matches | ForEach-Object {$_.Source}
