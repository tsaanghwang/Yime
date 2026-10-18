// Command yime-keyboard-lab serves a physical-keyboard model backed by real
// YimeCore sessions. Commits belong to the browser page, never installed TSF.
package main

import (
	"context"
	"crypto/rand"
	"encoding/hex"
	"encoding/json"
	"errors"
	"flag"
	"fmt"
	"log"
	"net"
	"net/http"
	"os"
	"os/signal"
	"path/filepath"
	"time"

	"github.com/tsaanghwang/Yime/go-backend/input_methods/yime/codemode"
	"github.com/tsaanghwang/Yime/go-backend/input_methods/yime/engineapi"
	"github.com/tsaanghwang/Yime/go-backend/input_methods/yime/yimecore"
)

var modes = []string{"variable", "full", "shorthand"}

func main() {
	root := flag.String("root", "..", "source checkout root (default: parent of go-backend)")
	dataDir := flag.String("data-dir", "", "experimental generated data directory; default: <root>/.generated/ascii-keyboard-138/data")
	port := flag.Int("port", 8765, "loopback HTTP port; 0 chooses an available port")
	flag.Parse()
	if err := run(*root, *dataDir, *port); err != nil {
		log.Print(err)
		os.Exit(1)
	}
}

func run(root, dataDir string, port int) error {
	if port < 0 || port > 65535 {
		return errors.New("port must be between 0 and 65535")
	}
	root, err := filepath.Abs(root)
	if err != nil {
		return err
	}
	if dataDir == "" {
		dataDir = filepath.Join(root, ".generated", "ascii-keyboard-138", "data")
	}
	staticRoot := filepath.Join(root, "prototypes", "touch-terminal")
	data, err := os.ReadFile(filepath.Join(staticRoot, "data", "physical-layout.json"))
	if err != nil {
		return fmt.Errorf("read generated physical keyboard layout: %w", err)
	}
	var layout struct {
		LayoutID string `json:"layoutId"`
	}
	if err := json.Unmarshal(data, &layout); err != nil || layout.LayoutID == "" {
		return errors.New("generated physical keyboard layout requires layoutId")
	}
	manifest, err := loadManifest(dataDir, layout.LayoutID)
	if err != nil {
		return err
	}
	// The indexes are disposable and use only this checkout's regenerated
	// canonical dictionaries. No installed-data or old-index fallback exists.
	indexRoot, err := os.MkdirTemp("", "yime-keyboard-lab-")
	if err != nil {
		return err
	}
	defer os.RemoveAll(indexRoot)
	indices := make(map[string]*yimecore.FileIndex)
	defer func() {
		for _, index := range indices {
			_ = index.Close()
		}
	}()
	builds := make(map[string]yimecore.IndexBuildResult)
	for _, mode := range modes {
		source := filepath.Join(dataDir, "yime_"+mode+".dict.yaml")
		output := filepath.Join(indexRoot, mode+".yidx")
		build, err := yimecore.BuildIndexFile(mode, source, output)
		if err != nil {
			return fmt.Errorf("compile %s dictionary: %w", mode, err)
		}
		if build.SourceSHA256 != manifest.DictionarySHA256[filepath.Base(source)] {
			return fmt.Errorf("%s dictionary differs from layout-bound experimental manifest; regenerate data", mode)
		}
		index, err := yimecore.OpenFileIndex(output)
		if err != nil {
			return err
		}
		indices[mode], builds[mode] = index, build
		log.Printf("%s: %d canonical dictionary entries, source SHA-256 %s", mode, build.IndexedRecords, build.SourceSHA256)
	}
	listener, err := net.Listen("tcp4", fmt.Sprintf("127.0.0.1:%d", port))
	if err != nil {
		return err
	}
	defer listener.Close()
	app := newLab(staticRoot, layout.LayoutID, "http://"+listener.Addr().String(), func(mode string) (engineapi.Engine, error) {
		index, ok := indices[mode]
		if !ok {
			return nil, errors.New("unknown input mode")
		}
		return yimecore.NewFileEngine(index, 9)
	})
	app.builds = builds
	app.repositoryRoot = root
	server := &http.Server{Handler: app, ReadHeaderTimeout: 5 * time.Second, ReadTimeout: 10 * time.Second, WriteTimeout: 30 * time.Second, IdleTimeout: 60 * time.Second, MaxHeaderBytes: 16 << 10}
	ctx, cancel := signal.NotifyContext(context.Background(), os.Interrupt)
	defer cancel()
	shutdownDone := make(chan struct{})
	go func() {
		defer close(shutdownDone)
		<-ctx.Done()
		// Wait for in-flight sessions before unmapping their shared indexes.
		_ = server.Shutdown(context.Background())
	}()
	log.Printf("Yime keyboard lab: %s (real YimeCore, page-only commits, no installed input method)", app.origin)
	err = server.Serve(listener)
	cancel()
	<-shutdownDone
	if errors.Is(err, http.ErrServerClosed) {
		return nil
	}
	return err
}

func randomID() string {
	var value [24]byte
	if _, err := rand.Read(value[:]); err != nil {
		panic(err)
	}
	return hex.EncodeToString(value[:])
}

type dataManifest struct {
	SchemaVersion          int               `json:"schema_version"`
	LayoutProjectionSHA256 string            `json:"layout_projection_sha256"`
	DisabledYinyuanIDs     []string          `json:"disabled_yinyuan_ids"`
	DictionarySHA256       map[string]string `json:"dictionary_sha256"`
	Scope                  string            `json:"scope"`
	Limit                  int               `json:"limit"`
	InputPolicy            string            `json:"input_policy"`
}

func loadManifest(dataDir, layoutID string) (dataManifest, error) {
	var result dataManifest
	data, err := os.ReadFile(filepath.Join(dataDir, "ascii_keyboard_manifest.json"))
	if err != nil {
		return result, fmt.Errorf("read experimental manifest: %w", err)
	}
	if err := json.Unmarshal(data, &result); err != nil {
		return result, fmt.Errorf("experimental manifest: %w", err)
	}
	if result.SchemaVersion != 1 || result.Scope != "immutable_source_runtime_experiment" || result.InputPolicy != inputPolicy || result.LayoutProjectionSHA256 != layoutID || layoutID != codemode.LayoutProjectionSHA256 || result.Limit != 0 {
		return result, errors.New("experimental manifest does not match this physical layout; regenerate data")
	}
	if len(result.DisabledYinyuanIDs) != 0 || len(codemode.LayoutAlphabet) != 75 {
		return result, errors.New("concept keyboard requires 75 active ASCII carriers and no disabled Yinyuan IDs")
	}
	for _, mode := range modes {
		value := result.DictionarySHA256["yime_"+mode+".dict.yaml"]
		digest, err := hex.DecodeString(value)
		if err != nil || len(digest) != 32 {
			return result, fmt.Errorf("manifest lacks valid %s dictionary digest", mode)
		}
	}
	return result, nil
}
