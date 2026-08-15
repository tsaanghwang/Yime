[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$repoRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$temporaryRoot = Join-Path $repoRoot '.tmp'
$outputDir = Join-Path $temporaryRoot 'contextual-tone-model-audit'
$runnerDir = Join-Path $temporaryRoot 'contextual-tone-model-audit-runner'
$runnerPath = Join-Path $runnerDir 'main.go'
$goCache = Join-Path $temporaryRoot 'go-contextual-tone-model-cache'
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
	result, err := connectedspeech.RunContextualToneModelAudit(connectedspeech.DefaultContextualToneModelAuditConfig(*repo))
	if err != nil {
		fmt.Fprintln(os.Stderr, err)
		os.Exit(1)
	}
	fmt.Printf("Contextual tone-quality hypothesis model audit: complete\nlayers=%d rules=%d dependencies=%d conflicts=%d deferred_rules=%d runtime_aliases=%d passed=%t\n",
		result.Summary.LayerCount,
		result.Summary.RuleCount,
		result.Summary.DependencyCount,
		result.Summary.ConflictCount,
		result.Summary.DeferredRuleCount,
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
    throw "Contextual-tone hypothesis model audit failed with exit code $exitCode"
}

Write-Host "Report directory: $outputDir"
