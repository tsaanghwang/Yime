package main

import (
	"flag"
	"fmt"
	"os"

	"github.com/tsaanghwang/Yime/go-backend/input_methods/yime/userlexicon"
)

func main() {
	sharedDir := flag.String("shared-dir", "", "Yime shared runtime data directory")
	userDir := flag.String("user-dir", "", "Yime Rime user data directory")
	flag.Parse()
	if *sharedDir == "" || *userDir == "" {
		fmt.Fprintln(os.Stderr, "missing required -shared-dir or -user-dir")
		os.Exit(2)
	}
	if err := userlexicon.RebuildAllRimeLexicons(*sharedDir, *userDir); err != nil {
		fmt.Fprintln(os.Stderr, "rebuild Yime user lexicons:", err)
		os.Exit(1)
	}
	fmt.Println("rebuilt Yime user lexicons")
}
