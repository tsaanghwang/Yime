[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$repoRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$temporaryRoot = Join-Path $repoRoot '.tmp'
$outputDir = Join-Path $temporaryRoot 'neutral-tone-context-audit'
$runnerDir = Join-Path $temporaryRoot 'neutral-tone-context-audit-runner'
$runnerPath = Join-Path $runnerDir 'main.go'
$goCacheDir = Join-Path $temporaryRoot 'neutral-tone-context-go-cache'
$goCommand = Get-Command go -ErrorAction Stop

[IO.Directory]::CreateDirectory($runnerDir) | Out-Null
[IO.Directory]::CreateDirectory($goCacheDir) | Out-Null
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
	result, err := connectedspeech.RunNeutralSurfaceAudit(connectedspeech.DefaultNeutralSurfaceAuditConfig(*repo))
	if err != nil {
		fmt.Fprintln(os.Stderr, err)
		os.Exit(1)
	}
	fmt.Printf("Neutral-tone context projection audit: complete\nclasses=%d pitch_levels=%d projected_grades=%d collision_buckets=%d contextual_identities=%d neutral_syllables=%d syllable_projections=%d compatibility_matches=%d tone3_collisions=%d ambiguous_observations=%d rewrite_rows=%d runtime_aliases=%d passed=%t\n",
		result.Summary.ContextClassCount,
		result.Summary.SurfacePitchLevelCount,
		result.Summary.ProjectedGradeCount,
		result.Summary.ProjectionCollisionBucketCount,
		result.Summary.ContextualIdentityCount,
		result.Summary.NeutralSyllableCount,
		result.Summary.SyllableProjectionCount,
		result.Summary.CompatibilityTupleMatchCount,
		result.Summary.SameBaseTone3CollisionCount,
		result.Summary.AmbiguousTupleObservationCount,
		result.Summary.RewriteMapRowCount,
		result.Summary.RuntimeAliasesGenerated,
		result.Summary.Passed,
	)
	impact, err := connectedspeech.RunNeutralLexiconImpactAudit(connectedspeech.DefaultNeutralLexiconImpactConfig(*repo))
	if err != nil {
		fmt.Fprintln(os.Stderr, err)
		os.Exit(1)
	}
	fmt.Printf("Neutral-tone lexicon impact audit: complete\nneutral_records=%d eligible=%d ineligible=%d changed_aliases=%d unchanged=%d three_mode_rows=%d new_mappings=%d already_present=%d competing_rows=%d competing_aliases=%d accepted_competing_aliases=%d collision_decision=%s would_top=%d would_tie=%d below_top=%d review_queue=%d runtime_aliases=%d passed=%t\n",
		impact.Summary.NeutralLexiconDistinctCount,
		impact.Summary.EligibleLexiconRecordCount,
		impact.Summary.IneligibleLexiconRecordCount,
		impact.Summary.ChangedAliasRecordCount,
		impact.Summary.CompatibilityUnchangedRecordCount,
		impact.Summary.ThreeModeAliasRowCount,
		impact.Summary.NewStaticMappingCount,
		impact.Summary.AlreadyPresentMappingCount,
		impact.Summary.CompetingBucketRowCount,
		impact.Summary.AliasRecordsWithCompetition,
		impact.Summary.AcceptedCompetingAliasCount,
		impact.Summary.CollisionDecision,
		impact.Summary.WouldBecomeTopCount,
		impact.Summary.WouldTieTopCount,
		impact.Summary.BelowExistingTopCount,
		impact.Summary.ReviewQueueRecordCount,
		impact.Summary.RuntimeAliasesGenerated,
		impact.Summary.Passed,
	)
	stage3, err := connectedspeech.RunNeutralStage3RimeTrial(connectedspeech.DefaultNeutralStage3TrialConfig(*repo))
	if err != nil {
		fmt.Fprintln(os.Stderr, err)
		os.Exit(1)
	}
	fmt.Printf("Neutral-tone Stage 3-1 temporary Rime trial: complete\nselected=%d three_mode_entries=%d bucket_entries=%d deferred_consecutive=%d runtime_aliases=%d passed=%t\n",
		stage3.Summary.SelectedAliasCount,
		stage3.Summary.ThreeModeEntryCount,
		stage3.Summary.ExistingBucketEntryCount,
		stage3.Summary.DeferredConsecutiveNeutral,
		stage3.Summary.RuntimeAliasesGenerated,
		stage3.Summary.Passed,
	)
	fullBatch, err := connectedspeech.RunNeutralStage3FullBatchAudit(connectedspeech.DefaultNeutralStage3FullBatchConfig(*repo))
	if err != nil {
		fmt.Fprintln(os.Stderr, err)
		os.Exit(1)
	}
	fmt.Printf("Neutral-tone Stage 3-2 full-batch audit: complete\nincluded=%d excluded_prior=%d distinct_mappings=%d exact_duplicates=%d internal_collision_buckets=%d max_bucket=%d internal_colliding_aliases=%d existing_competing_aliases=%d runtime_aliases=%d passed=%t\n",
		fullBatch.Summary.IncludedSimpleChangedRecordCount,
		fullBatch.Summary.ExcludedPriorRuleRecordCount,
		fullBatch.Summary.ThreeModeDistinctMappingCount,
		fullBatch.Summary.ExactDuplicateMappingCount,
		fullBatch.Summary.InternalCollisionBucketCount,
		fullBatch.Summary.MaximumInternalCandidateCount,
		fullBatch.Summary.InternalCollidingAliasRecordCount,
		fullBatch.Summary.ExistingCompetingAliasRecordCount,
		fullBatch.Summary.RuntimeAliasesGenerated,
		fullBatch.Summary.Passed,
	)
	fmt.Printf("prefix_net_new_relations=%v prefix_codes_with_net_new=%v prefix_codes_also_new_exact=%v new_exact_prefix_codes=%v old_longer_codes_affected=%v\n",
		fullBatch.Summary.NetNewVisibleTextRelationsByMode,
		fullBatch.Summary.OldPrefixesWithNetNewTextByMode,
		fullBatch.Summary.OldPrefixesAlsoNewExactByMode,
		fullBatch.Summary.NewExactPrefixCodesByMode,
		fullBatch.Summary.OldLongerCodesAffectedByMode,
	)
	fmt.Printf("new_new_only_buckets=%v new_new_only_net_old_prefix=%v new_new_only_prefix_old_longer=%v new_new_only_any_visible_prefix=%v\n",
		fullBatch.Summary.InternalNewOnlyBucketsByMode,
		fullBatch.Summary.InternalNewOnlyNetPrefixByMode,
		fullBatch.Summary.InternalNewOnlyOldSuffixByMode,
		fullBatch.Summary.InternalNewOnlyAnyPrefixByMode,
	)
}
'@
[IO.File]::WriteAllText($runnerPath, $runnerSource, [Text.UTF8Encoding]::new($false))

$exitCode = 1
$previousGoCache = $env:GOCACHE
$env:GOCACHE = $goCacheDir
Push-Location (Join-Path $repoRoot 'go-backend')
try {
    & $goCommand.Source run $runnerPath -repo $repoRoot
    $exitCode = $LASTEXITCODE
} finally {
    Pop-Location
    if ([IO.Directory]::Exists($runnerDir)) {
        [IO.Directory]::Delete($runnerDir, $true)
    }
    if ($null -eq $previousGoCache) {
        Remove-Item Env:GOCACHE -ErrorAction SilentlyContinue
    } else {
        $env:GOCACHE = $previousGoCache
    }
}

if ($exitCode -ne 0) {
    throw "Neutral-tone context projection audit failed with exit code $exitCode"
}

Write-Host "Report directory: $outputDir"
Write-Host "Lexicon impact report: $(Join-Path $temporaryRoot 'neutral-tone-lexicon-impact-audit')"
Write-Host "Temporary Stage 3-1 Rime package: $(Join-Path $temporaryRoot 'neutral-tone-stage3-1-rime')"
Write-Host "Stage 3-2 full-batch package: $(Join-Path $temporaryRoot 'neutral-tone-stage3-2-full-batch')"
