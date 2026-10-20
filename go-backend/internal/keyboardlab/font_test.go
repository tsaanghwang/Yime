package keyboardlab

import (
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"testing"
)

func TestFontRouteServesOnlyKnownRepositoryFont(t *testing.T) {
	a := testLab(t)
	a.repositoryRoot = t.TempDir()
	fontDir := filepath.Join(a.repositoryRoot, "go-backend", "input_methods", "yime", "data", "fonts")
	if err := os.MkdirAll(fontDir, 0700); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(fontDir, "YinYuan-Regular.ttf"), []byte("test font bytes"), 0600); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(fontDir, "other.ttf"), []byte("not exposed"), 0600); err != nil {
		t.Fatal(err)
	}
	for _, tc := range []struct {
		path string
		want int
	}{
		{"/assets/YinYuan-Regular.ttf", 200},
		{"/assets/other.ttf", 404},
		{"/assets/", 404},
		{"/assets/../go-backend/input_methods/yime/data/fonts/YinYuan-Regular.ttf", 404},
		{"/assets/%2e%2e/go-backend/input_methods/yime/data/fonts/YinYuan-Regular.ttf", 404},
	} {
		r := httptest.NewRequest(http.MethodGet, testOrigin+tc.path, nil)
		r.RemoteAddr = "127.0.0.1:1"
		w := httptest.NewRecorder()
		a.ServeHTTP(w, r)
		if w.Code != tc.want {
			t.Fatalf("%s: status %d", tc.path, w.Code)
		}
		if tc.want == 200 && (w.Header().Get("Content-Type") != "font/ttf" || w.Body.String() != "test font bytes") {
			t.Fatalf("wrong font response: %v %s", w.Header(), w.Body.String())
		}
	}
}

func TestFontRouteRejectsSymlinkOutsideRepository(t *testing.T) {
	a := testLab(t)
	a.repositoryRoot = t.TempDir()
	fontDir := filepath.Join(a.repositoryRoot, "go-backend", "input_methods", "yime", "data", "fonts")
	if err := os.MkdirAll(fontDir, 0700); err != nil {
		t.Fatal(err)
	}
	outside := filepath.Join(t.TempDir(), "outside.ttf")
	if err := os.WriteFile(outside, []byte("outside repository"), 0600); err != nil {
		t.Fatal(err)
	}
	if err := os.Symlink(outside, filepath.Join(fontDir, "YinYuan-Regular.ttf")); err != nil {
		t.Skipf("symlink creation unavailable: %v", err)
	}
	r := httptest.NewRequest(http.MethodGet, testOrigin+"/assets/YinYuan-Regular.ttf", nil)
	r.RemoteAddr = "127.0.0.1:1"
	w := httptest.NewRecorder()
	a.ServeHTTP(w, r)
	if w.Code != 404 {
		t.Fatalf("outside font exposed: %d %s", w.Code, w.Body.String())
	}
}
