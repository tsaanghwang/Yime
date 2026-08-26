[CmdletBinding()]
param(
    [string]$StateRoot = (Join-Path $env:LOCALAPPDATA 'YimeCore Experimental Trial'),
    [datetime]$SinceUtc = [datetime]::UtcNow.AddMinutes(-15),
    [switch]$ActiveCompositionKeptOriginalMode,
    [switch]$IdleNewSessionUsedChangedMode,
    [string]$OutputPath
)

$ErrorActionPreference = 'Stop'
$stateRootPath = [IO.Path]::GetFullPath($StateRoot)
$eventPath = Join-Path $stateRootPath 'evidence\language-bar-events.jsonl'
if (-not (Test-Path -LiteralPath $eventPath -PathType Leaf)) {
    throw "language-bar host evidence is missing: $eventPath"
}
$events = @(Get-Content -LiteralPath $eventPath -Encoding UTF8 | ForEach-Object {
    if (-not [string]::IsNullOrWhiteSpace($_)) {
        try { $_ | ConvertFrom-Json } catch { throw "invalid language-bar event JSON: $_" }
    }
} | Where-Object {
    # ConvertFrom-Json already materializes ISO-8601 timestamps as DateTime in
    # current PowerShell. Casting that DateTime back to string drops the zone;
    # parsing the string again then applies the local offset a second time.
    $eventTime = if ($_.timestamp -is [datetime]) {
        ([datetime]$_.timestamp).ToUniversalTime()
    } else {
        [datetimeoffset]::Parse([string]$_.timestamp).UtcDateTime
    }
    $eventTime -ge $SinceUtc.ToUniversalTime()
})
if ($events.Count -eq 0) { throw "no language-bar events were recorded after $($SinceUtc.ToUniversalTime().ToString('o'))" }

$leftClick = @($events | Where-Object { $_.event -eq 'left_click' -and [int]$_.hresult -eq 0 })
$rightOpen = @($events | Where-Object {
    ($_.event -eq 'right_click_open' -or $_.event -eq 'init_menu') -and [int]$_.hresult -eq 0
})
$successfulCommands = @($events | Where-Object {
    ($_.event -eq 'right_click_command' -or $_.event -eq 'menu_select') -and [int]$_.hresult -eq 0
})
$modeCommands = @(0x6C10, 0x6C11, 0x6C12)
$fontCommands = @(0x6C20, 0x6C21, 0x6C22)
$annotationCommands = @(0x6C30, 0x6C31, 0x6C32, 0x6C33)
$punctuationCommands = @(0x6C50, 0x6C51)
$shapeCommands = @(0x6C60, 0x6C61)
$scriptCommands = @(0x6C70, 0x6C71)
$modeSelection = @($successfulCommands | Where-Object { $modeCommands -contains [int]$_.command_id })
$fontSelection = @($successfulCommands | Where-Object { $fontCommands -contains [int]$_.command_id })
$annotationSelection = @($successfulCommands | Where-Object { $annotationCommands -contains [int]$_.command_id })
$punctuationSelection = @($successfulCommands | Where-Object { $punctuationCommands -contains [int]$_.command_id })
$shapeSelection = @($successfulCommands | Where-Object { $shapeCommands -contains [int]$_.command_id })
$scriptSelection = @($successfulCommands | Where-Object { $scriptCommands -contains [int]$_.command_id })

$passed = $leftClick.Count -gt 0 -and $rightOpen.Count -gt 0 -and
    $modeSelection.Count -gt 0 -and $fontSelection.Count -gt 0 -and
    $annotationSelection.Count -gt 0 -and $punctuationSelection.Count -gt 0 -and
    $shapeSelection.Count -gt 0 -and $scriptSelection.Count -gt 0 -and
    $ActiveCompositionKeptOriginalMode -and
    $IdleNewSessionUsedChangedMode
if ([string]::IsNullOrWhiteSpace($OutputPath)) {
    $OutputPath = Join-Path $stateRootPath 'evidence\language-bar-live-verification.json'
}
$outputPathValue = [IO.Path]::GetFullPath($OutputPath)
New-Item -ItemType Directory -Force -Path (Split-Path -Parent $outputPathValue) | Out-Null
$result = [ordered]@{
    schema_version = 'yimecore-language-bar-live-verification-v1'
    generated_at = [datetime]::UtcNow.ToString('o')
    since_utc = $SinceUtc.ToUniversalTime().ToString('o')
    event_path = $eventPath
    event_count = $events.Count
    native_left_click_toggle_recorded = $leftClick.Count -gt 0
    native_right_click_menu_recorded = $rightOpen.Count -gt 0
    mode_cascade_selection_recorded = $modeSelection.Count -gt 0
    font_cascade_selection_recorded = $fontSelection.Count -gt 0
    annotation_cascade_selection_recorded = $annotationSelection.Count -gt 0
    punctuation_cascade_selection_recorded = $punctuationSelection.Count -gt 0
    shape_cascade_selection_recorded = $shapeSelection.Count -gt 0
    script_cascade_selection_recorded = $scriptSelection.Count -gt 0
    active_composition_kept_original_mode = [bool]$ActiveCompositionKeptOriginalMode
    idle_new_session_used_changed_mode = [bool]$IdleNewSessionUsedChangedMode
    passed = [bool]$passed
    events = $events
}
$result | ConvertTo-Json -Depth 7 | Set-Content -LiteralPath $outputPathValue -Encoding UTF8
if (-not $passed) {
    throw ('language-bar live verification is incomplete: ' + ($result | ConvertTo-Json -Depth 4 -Compress))
}
Write-Host "E6-C language-bar live verification passed: $outputPathValue"
