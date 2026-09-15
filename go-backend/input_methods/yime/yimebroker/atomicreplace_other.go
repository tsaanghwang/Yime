//go:build !windows

package yimebroker

import "os"

func replaceJournalAtomically(source, destination string) error {
	return os.Rename(source, destination)
}
