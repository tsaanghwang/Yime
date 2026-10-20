// Command yime-keyboard-lab serves the isolated concept-keyboard web prototype.
package main

import (
	"flag"
	"github.com/tsaanghwang/Yime/go-backend/internal/keyboardlab"
	"log"
	"os"
)

func main() {
	root := flag.String("root", "..", "source checkout root (default: parent of go-backend)")
	dataDir := flag.String("data-dir", "", "experimental generated data directory; default: <root>/.generated/ascii-keyboard-134/data")
	port := flag.Int("port", 8765, "loopback HTTP port; 0 chooses an available port")
	flag.Parse()
	if err := keyboardlab.Serve(*root, *dataDir, *port); err != nil {
		log.Print(err)
		os.Exit(1)
	}
}
