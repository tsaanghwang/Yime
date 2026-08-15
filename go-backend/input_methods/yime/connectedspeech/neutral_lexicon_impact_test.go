package connectedspeech

import (
	"os"
	"path/filepath"
	"testing"
)

func TestNeutralAliasRankEffectIgnoresExistingMappings(t *testing.T) {
	if got := neutralAliasRankEffect("already_present", 7, "999", 1); got != "already_present_no_change" {
		t.Fatalf("existing mapping must not be counted as a ranking change: got %q", got)
	}
}

func TestNeutralAliasRankEffectClassifiesOnlyNewMappings(t *testing.T) {
	tests := []struct {
		name           string
		competitorRows int
		aliasWeight    string
		topCompetitor  int
		want           string
	}{
		{name: "empty bucket", aliasWeight: "100", want: "no_competitor"},
		{name: "new top", competitorRows: 1, aliasWeight: "101", topCompetitor: 100, want: "would_become_top"},
		{name: "tie", competitorRows: 1, aliasWeight: "100", topCompetitor: 100, want: "would_tie_top"},
		{name: "below top", competitorRows: 1, aliasWeight: "99", topCompetitor: 100, want: "below_existing_top"},
	}
	for _, test := range tests {
		t.Run(test.name, func(t *testing.T) {
			if got := neutralAliasRankEffect("new", test.competitorRows, test.aliasWeight, test.topCompetitor); got != test.want {
				t.Fatalf("got %q, want %q", got, test.want)
			}
		})
	}
}

func TestNeutralReviewPriorityKeepsRuleDependenciesFirst(t *testing.T) {
	reasons := map[string]bool{
		"below_existing_top":    true,
		"would_become_top":      true,
		"would_tie_top":         true,
		"prior_rule_dependency": true,
	}
	if got := neutralReviewPriority(reasons); got != "prior_rule_dependency" {
		t.Fatalf("got %q, want prior_rule_dependency", got)
	}
	delete(reasons, "prior_rule_dependency")
	if got := neutralReviewPriority(reasons); got != "would_tie_top" {
		t.Fatalf("got %q, want would_tie_top", got)
	}
}

func TestPriorRuleDependencyCoversTheWholePhrase(t *testing.T) {
	if !containsPriorRuleSyllable([]string{"yi1", "gan1", "zi5"}) {
		t.Fatal("a non-adjacent yi1 must still make the complete surface alias depend on prior tone-sandhi processing")
	}
	if containsPriorRuleSyllable([]string{"xue2", "sheng5"}) {
		t.Fatal("ordinary neutral-tone phrase was incorrectly marked prior-rule dependent")
	}
}

func TestNeutralCollisionPolicyAcceptsHomophonesWithoutApprovingRules(t *testing.T) {
	path := filepath.Join(t.TempDir(), "neutral_tone_collision_policy.tsv")
	content := "policy_id\tscope\tcollision_kind\tdecision\tranking_policy\tactivation_gate\texclusions\tstatus\trationale\n" +
		"p1\tcontextual_neutral_tone\tsame_surface_code_different_text\tinclude_in_candidate_bucket\tinherit_each_candidate_canonical_weight\treviewed_surface_rule\tprior_rule_dependency,neutral_after_neutral,neutral_without_predecessor\tapproved_engineering_policy\tactual homophones may share an input code\n"
	if err := os.WriteFile(path, []byte(content), 0o644); err != nil {
		t.Fatal(err)
	}
	policy, err := LoadNeutralCollisionPolicy(path)
	if err != nil {
		t.Fatal(err)
	}
	if policy.Decision != "include_in_candidate_bucket" || policy.ActivationGate != "reviewed_surface_rule" {
		t.Fatalf("unexpected policy: %#v", policy)
	}
}

func TestNeutralCollisionPolicyRejectsFabricatedRanking(t *testing.T) {
	policy := NeutralCollisionPolicy{
		PolicyID: "p1", Scope: "contextual_neutral_tone", CollisionKind: "same_surface_code_different_text",
		Decision: "include_in_candidate_bucket", RankingPolicy: "fabricate_alias_penalty", ActivationGate: "reviewed_surface_rule",
		Exclusions: []string{"prior_rule_dependency", "neutral_after_neutral", "neutral_without_predecessor"},
		Status:     "approved_engineering_policy", Rationale: "invalid test policy",
	}
	if err := ValidateNeutralCollisionPolicy(policy); err == nil {
		t.Fatal("expected fabricated alias ranking policy to be rejected")
	}
}
