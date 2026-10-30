package keyboardlab

import (
	"crypto/subtle"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"mime"
	"net"
	"net/http"
	"os"
	"path/filepath"
	"strings"

	"github.com/tsaanghwang/Yime/go-backend/input_methods/yime/yimecore"
)

const maxBody = 8192

type lab struct {
	staticRoot, layoutID, origin, token string
	repositoryRoot                      string
	builds                              map[string]yimecore.IndexBuildResult
	service                             *Service
}

func newLab(staticRoot, layoutID, origin string, factory engineFactory) *lab {
	return &lab{staticRoot: staticRoot, layoutID: layoutID, origin: origin, token: randomID(), service: NewService(layoutID, factory)}
}
func (a *lab) ServeHTTP(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Cache-Control", "no-store")
	w.Header().Set("X-Content-Type-Options", "nosniff")
	w.Header().Set("Referrer-Policy", "no-referrer")
	w.Header().Set("Content-Security-Policy", "default-src 'self'; connect-src 'self'; script-src 'self'; style-src 'self' 'unsafe-inline'; font-src 'self'; img-src 'self' data:; object-src 'none'; base-uri 'none'; frame-ancestors 'none'")
	host, _, err := net.SplitHostPort(r.RemoteAddr)
	ip := net.ParseIP(host)
	if err != nil || ip == nil || !ip.IsLoopback() || "http://"+r.Host != a.origin {
		writeError(w, http.StatusForbidden, "loopback host required")
		return
	}
	if origin := r.Header.Get("Origin"); origin != "" && origin != a.origin {
		writeError(w, http.StatusForbidden, "cross-origin request rejected")
		return
	}
	if site := r.Header.Get("Sec-Fetch-Site"); site != "" && site != "same-origin" && site != "none" {
		writeError(w, http.StatusForbidden, "cross-site request rejected")
		return
	}
	if r.URL.Path == "/api/info" && r.Method == http.MethodGet {
		writeJSON(w, http.StatusOK, map[string]any{"version": 1, "inputPolicy": SessionPolicy, "layoutId": a.layoutID, "token": a.token, "modes": modes, "scope": "isolated-yimecore-page-only", "indexes": a.builds})
		return
	}
	if strings.HasPrefix(r.URL.Path, "/api/") {
		if r.Method != http.MethodPost {
			writeError(w, http.StatusMethodNotAllowed, "POST required")
			return
		}
		if subtle.ConstantTimeCompare([]byte(r.Header.Get("X-Yime-Lab-Token")), []byte(a.token)) != 1 {
			writeError(w, http.StatusForbidden, "lab token required")
			return
		}
		contentType, _, _ := mime.ParseMediaType(r.Header.Get("Content-Type"))
		if contentType != "application/json" {
			writeError(w, http.StatusUnsupportedMediaType, "application/json required")
			return
		}
		switch r.URL.Path {
		case "/api/session":
			a.open(w, r)
		case "/api/event":
			a.event(w, r)
		default:
			writeError(w, http.StatusNotFound, "unknown API endpoint")
		}
		return
	}
	a.static(w, r)
}

func (a *lab) open(w http.ResponseWriter, r *http.Request) {
	var request struct {
		Mode     string `json:"mode"`
		LayoutID string `json:"layoutId"`
	}
	if err := readJSON(w, r, &request); err != nil {
		writeError(w, http.StatusBadRequest, err.Error())
		return
	}
	result := a.service.Open(request.Mode, request.LayoutID)
	writeBytes(w, result.Status, result.Body)
}
func (a *lab) event(w http.ResponseWriter, r *http.Request) {
	var request Event
	if err := readJSON(w, r, &request); err != nil {
		writeError(w, http.StatusBadRequest, err.Error())
		return
	}
	result := a.service.Dispatch(request)
	writeBytes(w, result.Status, result.Body)
}
func (a *lab) static(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet && r.Method != http.MethodHead {
		writeError(w, http.StatusMethodNotAllowed, "GET or HEAD required")
		return
	}
	relative := strings.TrimPrefix(r.URL.Path, "/")
	if relative == "" {
		relative = "index.html"
	}
	if relative == "assets/YinYuan-Regular.ttf" {
		a.font(w, r)
		return
	}
	// This service exposes only the physical-model entrypoint. Historical demo
	// data and implementation files must not be mistaken for the live backend.
	switch relative {
	case "index.html", "app.mjs", "input.mjs", "keyboard-layout.mjs", "geometry.mjs", "sizing.mjs", "style.css", "data/physical-layout.json", "README.md", "PROTOCOL.md", "HARDWARE.md":
	default:
		http.NotFound(w, r)
		return
	}
	root, err := filepath.EvalSymlinks(a.staticRoot)
	if err != nil {
		http.NotFound(w, r)
		return
	}
	target, err := filepath.EvalSymlinks(filepath.Join(root, filepath.FromSlash(relative)))
	if err != nil {
		http.NotFound(w, r)
		return
	}
	rel, err := filepath.Rel(root, target)
	if err != nil || rel == ".." || strings.HasPrefix(rel, ".."+string(filepath.Separator)) || filepath.IsAbs(rel) {
		http.NotFound(w, r)
		return
	}
	switch strings.ToLower(filepath.Ext(target)) {
	case ".html", ".css", ".mjs", ".json", ".md":
	default:
		http.NotFound(w, r)
		return
	}
	info, err := os.Stat(target)
	if err != nil || !info.Mode().IsRegular() {
		http.NotFound(w, r)
		return
	}
	if strings.HasSuffix(target, ".mjs") {
		w.Header().Set("Content-Type", "text/javascript; charset=utf-8")
	}
	http.ServeFile(w, r, target)
}

func (a *lab) font(w http.ResponseWriter, r *http.Request) {
	if a.repositoryRoot == "" {
		http.NotFound(w, r)
		return
	}
	root, err := filepath.EvalSymlinks(a.repositoryRoot)
	if err != nil {
		http.NotFound(w, r)
		return
	}
	// One known repository-owned file, not an exposed assets/fonts directory.
	target, err := filepath.EvalSymlinks(filepath.Join(root, "go-backend", "input_methods", "yime", "data", "fonts", "YinYuan-Regular.ttf"))
	if err != nil {
		http.NotFound(w, r)
		return
	}
	rel, err := filepath.Rel(root, target)
	if err != nil || rel == ".." || strings.HasPrefix(rel, ".."+string(filepath.Separator)) || filepath.IsAbs(rel) {
		http.NotFound(w, r)
		return
	}
	info, err := os.Stat(target)
	if err != nil || !info.Mode().IsRegular() {
		http.NotFound(w, r)
		return
	}
	w.Header().Set("Content-Type", "font/ttf")
	http.ServeFile(w, r, target)
}

func readJSON(w http.ResponseWriter, r *http.Request, target any) error {
	r.Body = http.MaxBytesReader(w, r.Body, maxBody)
	decoder := json.NewDecoder(r.Body)
	decoder.DisallowUnknownFields()
	if err := decoder.Decode(target); err != nil {
		return fmt.Errorf("invalid JSON request: %w", err)
	}
	if err := decoder.Decode(new(any)); err != io.EOF {
		return errors.New("request must contain exactly one JSON object")
	}
	return nil
}
func writeError(w http.ResponseWriter, status int, message string) {
	writeJSON(w, status, map[string]any{"ok": false, "error": message})
}
func writeJSON(w http.ResponseWriter, status int, value any) {
	body, _ := json.Marshal(value)
	writeBytes(w, status, body)
}
func writeBytes(w http.ResponseWriter, status int, body []byte) {
	w.Header().Set("Content-Type", "application/json; charset=utf-8")
	w.WriteHeader(status)
	_, _ = w.Write(body)
}
