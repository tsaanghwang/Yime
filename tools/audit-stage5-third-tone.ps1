[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$repoRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$temporaryRoot = Join-Path $repoRoot '.tmp'
$outputDir = Join-Path $temporaryRoot 'third-tone-stage5a-audit'
$runnerDir = Join-Path $temporaryRoot 'third-tone-stage5a-runner'
$runnerPath = Join-Path $runnerDir 'main.go'
$goCache = Join-Path $temporaryRoot 'go-third-tone-stage5a-cache'
$goCommand = Get-Command go -ErrorAction Stop

[IO.Directory]::CreateDirectory($runnerDir) | Out-Null
[IO.Directory]::CreateDirectory($goCache) | Out-Null
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
	flag.Parse()
	result, err := connectedspeech.RunThirdToneStage5AAudit(connectedspeech.DefaultThirdToneStage5AConfig(*repo))
	if err != nil {
		fmt.Fprintln(os.Stderr, err)
		os.Exit(1)
	}
	fmt.Printf("Third-tone Stage 5A audit: complete\ncandidates=%d projectable=%d blocked_longer=%d longer_sequences=%d three_plus=%d runtime_aliases=%d passed=%t\n",
		result.Summary.DisyllabicDoubleThirdCount,
		result.Summary.ProjectableCandidateCount,
		result.Summary.BlockedLongerCandidateCount,
		result.Summary.LongerEntryWithPairCount,
		result.Summary.ThreePlusChainCount,
		result.Summary.RuntimeAliasesGenerated,
		result.Summary.Passed,
	)
}
'@
[IO.File]::WriteAllText($runnerPath, $runnerSource, [Text.UTF8Encoding]::new($false))

$oldGoCache = $env:GOCACHE
$exitCode = 1
Push-Location (Join-Path $repoRoot 'go-backend')
try {
    $env:GOCACHE = $goCache
    & $goCommand.Source run $runnerPath -repo $repoRoot
    $exitCode = $LASTEXITCODE
} finally {
    $env:GOCACHE = $oldGoCache
    Pop-Location
    if ([IO.Directory]::Exists($runnerDir)) {
        [IO.Directory]::Delete($runnerDir, $true)
    }
}

if ($exitCode -ne 0) {
    throw "Third-tone Stage 5A audit failed with exit code $exitCode"
}

Write-Host "Report directory: $outputDir"
