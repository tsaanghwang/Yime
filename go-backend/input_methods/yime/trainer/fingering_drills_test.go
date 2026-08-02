package trainer

import "testing"

func TestFingeringDrillsProvideAdjacentSameFingerAndAlternatingPractice(t *testing.T) {
	resolver, err := NewResolver(repositoryDataDir(t))
	if err != nil {
		t.Fatal(err)
	}
	groups, err := resolver.ResolveFingeringDrills()
	if err != nil {
		t.Fatal(err)
	}
	if len(groups) != 3 {
		t.Fatalf("groups=%d", len(groups))
	}
	for _, group := range groups {
		if group.Category != GroupCategoryFingering || len(group.Exercises) < 5 {
			t.Fatalf("incomplete fingering group %#v", group)
		}
		for _, exercise := range group.Exercises {
			if len(exercise.AnswerUnits) != 2 || exercise.Expected != exercise.AnswerUnits[0].ExpectedKey+exercise.AnswerUnits[1].ExpectedKey {
				t.Fatalf("invalid fingering exercise %#v", exercise)
			}
		}
	}
}
