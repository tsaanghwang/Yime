//go:build !windows

package speechruntime

import "os"

func productPlainPath(path string) error { return PlainPath(path) }
func replaceSettingsAtomically(source, destination string) error {
	return os.Rename(source, destination)
}
