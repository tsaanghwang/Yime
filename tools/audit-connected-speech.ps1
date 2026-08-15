[CmdletBinding()]
param(
    [string]$Records,
    [switch]$EnableToneSandhi,
    [switch]$EnableNeutralToneSurface,
    [switch]$EnableErhuaSuffixCompatibility,
    [switch]$EnableErhuaFused,
    [switch]$EnableParticleAllomorphy,
    [switch]$EnableAssimilation,
    [switch]$EnableDissimilation,
    [switch]$EnableAllTrialModules
)

$ErrorActionPreference = 'Stop'
$repoRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$temporaryRoot = Join-Path $repoRoot '.tmp'
$outputDir = Join-Path $temporaryRoot 'connected-speech-audit'
$runnerDir = Join-Path $temporaryRoot 'connected-speech-audit-runner'
$defaultInputDir = Join-Path $temporaryRoot 'connected-speech-audit-input'

if ([string]::IsNullOrWhiteSpace($Records)) {
    [IO.Directory]::CreateDirectory($defaultInputDir) | Out-Null
    $Records = Join-Path $defaultInputDir 'records.json'
    [IO.File]::WriteAllText($Records, "[]`n", [Text.UTF8Encoding]::new($false))
} else {
    $Records = [IO.Path]::GetFullPath($Records)
}

if (-not [IO.File]::Exists($Records)) {
    throw "找不到结构化审定记录：$Records"
}

$goCommand = Get-Command go -ErrorAction Stop
[IO.Directory]::CreateDirectory($runnerDir) | Out-Null
$runnerPath = Join-Path $runnerDir 'main.go'
$runnerSource = @'
package main

import (
	"flag"
	"fmt"
	"os"

	"github.com/tsaanghwang/Yime/go-backend/input_methods/yime/connectedspeech"
)

func main() {
	repo := flag.String("repo", "", "repository root")
	records := flag.String("records", "", "record JSON path")
	toneSandhi := flag.Bool("tone-sandhi", false, "enable tone sandhi trial")
	neutralTone := flag.Bool("neutral-tone", false, "enable neutral tone surface trial")
	erhuaSuffix := flag.Bool("erhua-suffix", false, "enable erhua suffix compatibility trial")
	erhuaFused := flag.Bool("erhua-fused", false, "enable fused erhua trial")
	particle := flag.Bool("particle", false, "enable particle allomorphy trial")
	assimilation := flag.Bool("assimilation", false, "enable assimilation trial")
	dissimilation := flag.Bool("dissimilation", false, "enable dissimilation trial")
	flag.Parse()

	config := connectedspeech.DefaultConfig(*repo, *records)
	config.Switches = connectedspeech.Switches{
		Enabled: *toneSandhi || *neutralTone || *erhuaSuffix || *erhuaFused || *particle || *assimilation || *dissimilation,
		ToneSandhi: *toneSandhi,
		NeutralToneSurface: *neutralTone,
		ErhuaSuffixCompatibility: *erhuaSuffix,
		ErhuaFused: *erhuaFused,
		ParticleAllomorphy: *particle,
		Assimilation: *assimilation,
		Dissimilation: *dissimilation,
	}
	result, err := connectedspeech.RunAudit(config)
	if err != nil {
		fmt.Fprintln(os.Stderr, err)
		os.Exit(1)
	}
	fmt.Printf("Connected-speech offline audit: complete\nrecords=%d trial_records=%d trial_aliases=%d passed=%t\n", result.Summary.RecordCount, result.Summary.TrialRecordCount, result.Summary.TrialAliasCount, result.Summary.Passed)
}
'@
[IO.File]::WriteAllText($runnerPath, $runnerSource, [Text.UTF8Encoding]::new($false))

$enableAll = $EnableAllTrialModules.IsPresent
$arguments = @(
    'run', $runnerPath,
    '-repo', $repoRoot,
    '-records', $Records,
    '-tone-sandhi', ($enableAll -or $EnableToneSandhi.IsPresent).ToString().ToLowerInvariant(),
    '-neutral-tone', ($enableAll -or $EnableNeutralToneSurface.IsPresent).ToString().ToLowerInvariant(),
    '-erhua-suffix', ($enableAll -or $EnableErhuaSuffixCompatibility.IsPresent).ToString().ToLowerInvariant(),
    '-erhua-fused', ($enableAll -or $EnableErhuaFused.IsPresent).ToString().ToLowerInvariant(),
    '-particle', ($enableAll -or $EnableParticleAllomorphy.IsPresent).ToString().ToLowerInvariant(),
    '-assimilation', ($enableAll -or $EnableAssimilation.IsPresent).ToString().ToLowerInvariant(),
    '-dissimilation', ($enableAll -or $EnableDissimilation.IsPresent).ToString().ToLowerInvariant()
)

$exitCode = 1
Push-Location (Join-Path $repoRoot 'go-backend')
try {
    & $goCommand.Source @arguments
    $exitCode = $LASTEXITCODE
} finally {
    Pop-Location
    if ([IO.Directory]::Exists($runnerDir)) {
        [IO.Directory]::Delete($runnerDir, $true)
    }
}

if ($exitCode -ne 0) {
    throw "语流音变离线审计失败，退出代码：$exitCode"
}

Write-Host "Report directory: $outputDir"
