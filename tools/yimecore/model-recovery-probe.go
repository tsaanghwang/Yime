//go:build ignore

// Offline recovery verifier. Run only against a disposable backup clone: opening
// the store may migrate/checkpoint files. Never point it at a live user model.
package main

import (
	"encoding/json"
	"flag"
	"fmt"
	"os"
	"path/filepath"

	"github.com/tsaanghwang/Yime/go-backend/input_methods/yime/yimebroker"
)

func main() {
	root := flag.String("clone", "", "disposable cloned model directory")
	source := flag.String("source-id", "", "source ID read from original journal")
	output := flag.String("output", "", "recovery evidence path")
	flag.Parse()
	if *root == "" || *source == "" || *output == "" {
		panic("clone, source-id and output are required")
	}
	if _, err := os.Stat(filepath.Join(*root, ".yime-recovery-clone")); err != nil {
		panic("explicit disposable-clone marker is required")
	}
	store, err := yimebroker.OpenDurableUserModel(yimebroker.DurableUserModelConfig{
		SnapshotPath: filepath.Join(*root, "user-model.json"), JournalPath: filepath.Join(*root, "user-model.journal"), SourceID: *source,
	})
	if err != nil {
		panic(err)
	}
	evidence := map[string]any{"passed": true, "generation": store.Model().Generation(), "source_id": store.Model().SourceID(),
		"learned_record_count": len(store.Model().LearnedRecords()), "stats": store.Stats(), "clone": *root}
	if err := store.Model().SaveTo(filepath.Join(*root, "recovered-model.json")); err != nil {
		panic(err)
	}
	if err := store.Close(); err != nil {
		panic(err)
	}
	data, err := json.MarshalIndent(evidence, "", "  ")
	if err != nil {
		panic(err)
	}
	if err = os.WriteFile(*output, append(data, '\n'), 0600); err != nil {
		panic(err)
	}
	fmt.Printf("Recovery clone validated: generation=%v records=%v\n", evidence["generation"], evidence["learned_record_count"])
}
