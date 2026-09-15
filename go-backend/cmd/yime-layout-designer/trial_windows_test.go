//go:build windows

package main

import (
	"path/filepath"
	"slices"
	"testing"
)

func TestExperimentalLayoutDesignerUsesIndependentIdentity(t *testing.T) {
	if got := layoutWindowClass(false); got != "YimeLayoutDesigner" {
		t.Fatalf("production layout class=%q", got)
	}
	if got := layoutWindowClass(true); got != "YimeCoreTrialLayoutDesigner" {
		t.Fatalf("Trial layout class=%q", got)
	}
	if got := layoutWindowTitle(true); got != "Yime 试验版键盘布局" {
		t.Fatalf("Trial layout title=%q", got)
	}
	stateRoot := filepath.Join(`C:\Users\tester`, "AppData", "Local", "YimeCore Experimental Trial")
	if got := trialLayoutRoot(stateRoot); got != filepath.Join(stateRoot, "layout") {
		t.Fatalf("Trial layout root=%q", got)
	}
	arguments := trialRuntimeArguments(`C:\Program Files\Trial`, stateRoot)
	if !slices.Contains(arguments, "-no-toolbar") {
		t.Fatalf("Trial layout restart must preserve native language-bar-only startup: %v", arguments)
	}
}
