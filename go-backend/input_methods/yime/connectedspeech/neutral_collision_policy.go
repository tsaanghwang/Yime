package connectedspeech

import (
	"encoding/csv"
	"errors"
	"fmt"
	"io"
	"os"
	"strings"
)

type NeutralCollisionPolicy struct {
	PolicyID       string
	Scope          string
	CollisionKind  string
	Decision       string
	RankingPolicy  string
	ActivationGate string
	Exclusions     []string
	Status         string
	Rationale      string
}

func LoadNeutralCollisionPolicy(path string) (NeutralCollisionPolicy, error) {
	file, err := os.Open(path)
	if err != nil {
		return NeutralCollisionPolicy{}, err
	}
	defer file.Close()
	reader := csv.NewReader(file)
	reader.Comma = '\t'
	header, err := reader.Read()
	if err != nil {
		return NeutralCollisionPolicy{}, err
	}
	row, err := reader.Read()
	if err != nil {
		return NeutralCollisionPolicy{}, err
	}
	if extra, extraErr := reader.Read(); !errors.Is(extraErr, io.EOF) || len(extra) != 0 {
		return NeutralCollisionPolicy{}, errors.New("neutral collision policy must contain exactly one data row")
	}
	values := map[string]string{}
	for index, name := range header {
		if index < len(row) {
			values[name] = strings.TrimSpace(row[index])
		}
	}
	policy := NeutralCollisionPolicy{
		PolicyID: values["policy_id"], Scope: values["scope"], CollisionKind: values["collision_kind"],
		Decision: values["decision"], RankingPolicy: values["ranking_policy"], ActivationGate: values["activation_gate"],
		Exclusions: splitNonEmpty(values["exclusions"]), Status: values["status"], Rationale: values["rationale"],
	}
	if err := ValidateNeutralCollisionPolicy(policy); err != nil {
		return NeutralCollisionPolicy{}, err
	}
	return policy, nil
}

func ValidateNeutralCollisionPolicy(policy NeutralCollisionPolicy) error {
	expected := map[string]string{
		"scope": policy.Scope, "collision_kind": policy.CollisionKind, "decision": policy.Decision,
		"ranking_policy": policy.RankingPolicy, "activation_gate": policy.ActivationGate, "status": policy.Status,
	}
	wants := map[string]string{
		"scope": "contextual_neutral_tone", "collision_kind": "same_surface_code_different_text",
		"decision": "include_in_candidate_bucket", "ranking_policy": "inherit_each_candidate_canonical_weight",
		"activation_gate": "reviewed_surface_rule", "status": "approved_engineering_policy",
	}
	if policy.PolicyID == "" || policy.Rationale == "" {
		return errors.New("neutral collision policy requires policy_id and rationale")
	}
	for field, want := range wants {
		if expected[field] != want {
			return fmt.Errorf("neutral collision policy %s=%q, want %q", field, expected[field], want)
		}
	}
	for _, required := range []string{"prior_rule_dependency", "neutral_after_neutral", "neutral_without_predecessor"} {
		if !containsString(policy.Exclusions, required) {
			return fmt.Errorf("neutral collision policy must exclude %s", required)
		}
	}
	return nil
}
