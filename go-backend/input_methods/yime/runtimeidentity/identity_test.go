package runtimeidentity

import (
	"os"
	"path/filepath"
	"testing"
)

func TestLoadDerivesContentAddressedNamespaces(t *testing.T) {
	dir := t.TempDir()
	payload := `{"entry_count":12,"distinct_texts":10,"source_dictionary_sha256":"7edf122913925291d1259241d3b1494faec9173a478a1658e0959062c1e8f155","source_selection_sha256":"4ec48d3627b8efa8344d38430f85710570a6576693cc0cd2990dc3fb4e3bac17"}`
	if err := os.WriteFile(filepath.Join(dir, SourceManifestFileName), []byte(payload), 0o644); err != nil {
		t.Fatal(err)
	}
	identity, err := Load(dir)
	if err != nil {
		t.Fatal(err)
	}
	if identity.CoreVersion() != "core-7edf12291392" || identity.UserDBNamespace() != "core_7edf12291392" {
		t.Fatalf("unexpected identity: %#v", identity)
	}
}

func TestLoadRejectsIncompleteManifest(t *testing.T) {
	dir := t.TempDir()
	if err := os.WriteFile(filepath.Join(dir, SourceManifestFileName), []byte(`{"entry_count":12}`), 0o644); err != nil {
		t.Fatal(err)
	}
	if _, err := Load(dir); err == nil {
		t.Fatal("expected incomplete source identity to be rejected")
	}
}
