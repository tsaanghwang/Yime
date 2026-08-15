[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$repoRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$temporaryRoot = Join-Path $repoRoot '.tmp'
$runnerDir = Join-Path $temporaryRoot 'connected-speech-stage2-yi-bu-runner'
$runnerPath = Join-Path $runnerDir 'main.go'
$recordsPath = Join-Path $repoRoot 'docs\project\connected_speech\stage2_yi_bu_records.json'
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
	records := flag.String("records", "", "Stage 2A record JSON")
	flag.Parse()

	chain, err := connectedspeech.RunYiBuChainAudit(connectedspeech.DefaultYiBuChainAuditConfig(*repo))
	if err != nil {
		fmt.Fprintln(os.Stderr, err)
		os.Exit(1)
	}

	trialConfig := connectedspeech.DefaultConfig(*repo, *records)
	trialConfig.Switches = connectedspeech.Switches{Enabled: true, ToneSandhi: true}
	trial, err := connectedspeech.RunAudit(trialConfig)
	if err != nil {
		fmt.Fprintln(os.Stderr, err)
		os.Exit(1)
	}
	stage2b, err := connectedspeech.RunStage2BRimeTrial(connectedspeech.DefaultStage2BTrialConfig(*repo))
	if err != nil {
		fmt.Fprintln(os.Stderr, err)
		os.Exit(1)
	}

	fmt.Printf("Stage 2B yi/bu trial: complete\ncases=%d three_mode_checks=%d runtime_aliases=%d trial_records=%d trial_aliases=%d temporary_rime_entries=%d passed=%t\n",
		chain.Summary.CaseCount,
		chain.Summary.ThreeModeCheckCount,
		chain.Summary.RuntimeAliasesGenerated,
		trial.Summary.TrialRecordCount,
		trial.Summary.TrialAliasCount,
		stage2b.Summary.ThreeModeEntryCount,
		chain.Summary.Passed && trial.Summary.Passed && stage2b.Summary.Passed,
	)
}
'@
[IO.File]::WriteAllText($runnerPath, $runnerSource, [Text.UTF8Encoding]::new($false))

$exitCode = 1
Push-Location (Join-Path $repoRoot 'go-backend')
try {
    & $goCommand.Source run $runnerPath -repo $repoRoot -records $recordsPath
    $exitCode = $LASTEXITCODE
} finally {
    Pop-Location
    if ([IO.Directory]::Exists($runnerDir)) {
        [IO.Directory]::Delete($runnerDir, $true)
    }
}

if ($exitCode -ne 0) {
    throw "Stage 2A yi/bu audit failed with exit code $exitCode"
}

Write-Host "Chain report: $(Join-Path $temporaryRoot 'connected-speech-stage2-yi-bu-audit')"
Write-Host "Trial report: $(Join-Path $temporaryRoot 'connected-speech-audit')"
Write-Host "Temporary Rime package: $(Join-Path $temporaryRoot 'connected-speech-stage2b-rime')"
