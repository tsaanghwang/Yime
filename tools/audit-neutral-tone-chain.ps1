[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$repoRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$temporaryRoot = Join-Path $repoRoot '.tmp'
$outputDir = Join-Path $temporaryRoot 'neutral-tone-chain-audit'
$runnerDir = Join-Path $temporaryRoot 'neutral-tone-chain-audit-runner'
$runnerPath = Join-Path $runnerDir 'main.go'
$goCommand = Get-Command go -ErrorAction Stop

[IO.Directory]::CreateDirectory($runnerDir) | Out-Null
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
	result, err := connectedspeech.RunNeutralChainAudit(connectedspeech.DefaultNeutralChainAuditConfig(*repo))
	if err != nil {
		fmt.Fprintln(os.Stderr, err)
		os.Exit(1)
	}
	fmt.Printf("Neutral-tone chain audit: complete\nsyllables=%d lexicon_entries=%d reverse_checks=%d user_lexicon_checks=%d passed=%t\n",
		result.Summary.NeutralSyllableCount,
		result.Summary.NeutralLexiconEntryCount,
		result.Summary.ReverseLookupCheckCount,
		result.Summary.UserLexiconCheckCount,
		result.Summary.Passed,
	)
}
'@
[IO.File]::WriteAllText($runnerPath, $runnerSource, [Text.UTF8Encoding]::new($false))

$exitCode = 1
Push-Location (Join-Path $repoRoot 'go-backend')
try {
    & $goCommand.Source run $runnerPath -repo $repoRoot
    $exitCode = $LASTEXITCODE
} finally {
    Pop-Location
    if ([IO.Directory]::Exists($runnerDir)) {
        [IO.Directory]::Delete($runnerDir, $true)
    }
}

if ($exitCode -ne 0) {
    throw "Neutral-tone chain audit failed with exit code $exitCode"
}

Write-Host "Report directory: $outputDir"
