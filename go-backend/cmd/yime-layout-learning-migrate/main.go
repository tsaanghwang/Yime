package main

import (
	"flag"
	"fmt"
	"os"
	"path/filepath"

	"github.com/tsaanghwang/Yime/go-backend/input_methods/yime/learningmigration"
)

func main() {
	sharedDir := flag.String("shared-dir", "", "directory containing incoming Yime Rime data")
	userDir := flag.String("user-dir", "", "Rime user directory")
	flag.Parse()
	if *userDir == "" {
		if appData := os.Getenv("APPDATA"); appData != "" {
			*userDir = filepath.Join(appData, "PIME", "Rime")
		}
	}
	if *sharedDir == "" || *userDir == "" {
		fatal("必须指定 -shared-dir，且 -user-dir 或 APPDATA 必须可用")
	}
	transitions, err := learningmigration.DetectTransitions(*sharedDir, *userDir)
	if err != nil {
		fatal(err.Error())
	}
	reports, err := learningmigration.MigrateAll(*sharedDir, *userDir, transitions)
	if err != nil {
		fatal(err.Error())
	}
	if len(reports) == 0 {
		fmt.Println("没有需要迁移且实际存在的旧布局学习库")
		return
	}
	for _, r := range reports {
		fmt.Printf("%s: %s -> %s, total=%d migrated=%d unmatched=%d ambiguous=%d\n", r.Mode, r.SourceDB, r.TargetDB, r.Total, r.Migrated, r.Unmatched, r.Ambiguous)
	}
}

func fatal(message string) { fmt.Fprintln(os.Stderr, message); os.Exit(1) }
