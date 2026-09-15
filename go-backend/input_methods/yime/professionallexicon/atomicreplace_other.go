//go:build !windows

package professionallexicon

import "os"

func replaceFileAtomically(source, destination string) error {
	return os.Rename(source, destination)
}
