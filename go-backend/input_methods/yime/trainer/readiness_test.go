package trainer

import "testing"

func TestTrainerContentReadinessCoversFingeringAndAllFormalSyllables(t *testing.T) {
	resolver, err := NewResolver(repositoryDataDir(t))
	if err != nil {
		t.Fatal(err)
	}
	readiness := resolver.ContentReadiness()
	if readiness.YinyuanTotal != 57 || readiness.FingeringCovered != 57 || readiness.EncodedSyllables != 1733 || !readiness.CandidateSimulation {
		t.Fatalf("readiness=%#v", readiness)
	}
	if readiness.AudioAvailable > readiness.AudioDeclared || readiness.AudioDeclared > readiness.YinyuanTotal {
		t.Fatalf("invalid optional audio coverage: %#v", readiness)
	}
}
