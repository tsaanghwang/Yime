[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$repoRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$temporaryRoot = Join-Path $repoRoot '.tmp'
$outputDir = Join-Path $temporaryRoot 'particle-a-stage6b-projection'
$runnerDir = Join-Path $temporaryRoot 'particle-a-stage6b-runner'
$runnerPath = Join-Path $runnerDir 'main.go'
$goCache = Join-Path $temporaryRoot 'go-particle-a-stage6b-cache'
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
	result, err := connectedspeech.RunParticleAStage6BProjection(connectedspeech.DefaultParticleAStage6BConfig(*repo))
	if err != nil {
		fmt.Fprintln(os.Stderr, err)
		os.Exit(1)
	}
	fmt.Printf("Particle-a Stage 6B projection: complete\nexplicit=%d projected=%d blocked_longer=%d collisions=%d unresolved=%d runtime_aliases=%d passed=%t\n",
		result.Summary.ExplicitParticleACount, result.Summary.ProjectableCandidateCount, result.Summary.BlockedLongerCount,
		result.Summary.CollisionMappings, result.Summary.UnresolvedCount, result.Summary.RuntimeAliasesGenerated, result.Summary.Passed)
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
    if ([IO.Directory]::Exists($runnerDir)) { [IO.Directory]::Delete($runnerDir, $true) }
}
if ($exitCode -ne 0) { throw "Particle-a Stage 6B projection failed with exit code $exitCode" }
Write-Host "Report directory: $outputDir"
