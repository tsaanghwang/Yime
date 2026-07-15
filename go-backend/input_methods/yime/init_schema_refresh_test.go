package yime

import (
	"errors"
	"testing"

	"github.com/tsaanghwang/Yime/go-backend/pime"
)

func TestInitDoesNotRequestFullDeployWithoutSuccessfulSchemaChange(t *testing.T) {
	tests := []struct {
		name    string
		changed bool
		err     error
	}{
		{name: "unchanged"},
		{name: "refresh error", changed: true, err: errors.New("refresh failed")},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			t.Setenv("APPDATA", t.TempDir())
			backend := &configurableInitBackend{testBackend: newTestBackend(), initializeResult: true}
			oldFactory := createRimeBackend
			oldRefresh := refreshRimeSchemasOnInit
			createRimeBackend = func() rimeBackend { return backend }
			refreshRimeSchemasOnInit = func(sharedDir, userDir string) (bool, error) {
				return tt.changed, tt.err
			}
			t.Cleanup(func() {
				createRimeBackend = oldFactory
				refreshRimeSchemasOnInit = oldRefresh
			})

			ime := New(&pime.Client{ID: "test-client"}).(*IME)
			if !ime.Init(&pime.Request{}) {
				t.Fatal("expected initialization to succeed")
			}
			if backend.firstRun {
				t.Fatal("full deployment must require a successful schema content change")
			}
		})
	}
}
