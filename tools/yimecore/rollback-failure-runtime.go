//go:build ignore

// Rehearsal-only executable: causes the staged runtime-start phase to fail
// without opening input data, pipes, windows, or child processes.
package main

import "os"

func main() { os.Exit(86) }
