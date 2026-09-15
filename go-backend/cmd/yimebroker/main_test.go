package main

import (
	"path/filepath"
	"testing"

	"github.com/tsaanghwang/Yime/go-backend/input_methods/yime/learningconfig"
	"github.com/tsaanghwang/Yime/go-backend/input_methods/yime/yimecore"
)

func TestEnabledUserModelHonorsLearningConfigWithoutDeletingModel(t *testing.T) {
	model, err := yimecore.NewUserModel("learning-toggle-test")
	if err != nil {
		t.Fatal(err)
	}
	path := filepath.Join(t.TempDir(), "learning.json")
	if got, err := enabledUserModel(path, model); err != nil || got != model {
		t.Fatalf("default model=%p err=%v", got, err)
	}
	if err := learningconfig.Save(path, false); err != nil {
		t.Fatal(err)
	}
	if got, err := enabledUserModel(path, model); err != nil || got != nil {
		t.Fatalf("disabled model=%p err=%v", got, err)
	}
	if model.SourceID() != "learning-toggle-test" {
		t.Fatal("disabling learning mutated the retained model")
	}
}
