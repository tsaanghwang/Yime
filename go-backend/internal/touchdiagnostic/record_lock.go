package touchdiagnostic

import (
	"errors"
	"os"
	"path/filepath"
	"strings"
)

var ErrStorageBusy = errors.New("diagnostic storage busy")
var ErrIncompleteRun = errors.New("diagnostic run was not completed")

type recordLockMode uint8

const (
	recordLockExisting recordLockMode = iota
	recordLockCreate
	recordLockCreateNew
)

func lockRecordDirectory(dir string) (*os.File, error) {
	return lockRecordPath(filepath.Join(dir, ".retention.lock"), recordLockCreate)
}

func activeRecordPath(dir, name string) string {
	return filepath.Join(dir, name+".active")
}

// The directory lock must already be held. A locked marker belongs to a live
// recorder; an unlocked marker is deliberately left after an incomplete run.
func activeRecord(dir, name string) (bool, bool, error) {
	file, err := lockRecordPath(activeRecordPath(dir, name), recordLockExisting)
	if errors.Is(err, os.ErrNotExist) {
		return false, false, nil
	}
	if errors.Is(err, ErrStorageBusy) {
		return true, true, nil
	}
	if err != nil {
		return false, false, err
	}
	if err := file.Close(); err != nil {
		return false, true, err
	}
	return false, true, nil
}

// Called with the directory lock held, before creating the next marker. A crash
// after marker.Sync but before data creation leaves no run for normal retention
// to enumerate. Reclaim only empty, unlocked markers with no data path. Unknown
// or nonempty files remain untouched; arbitrary external file counts are not
// bounded by the recorder's MaxRuns contract.
func cleanupOrphanRecordMarkers(dir string) error {
	entries, err := os.ReadDir(dir)
	if err != nil {
		return err
	}
	for _, entry := range entries {
		if !strings.HasSuffix(entry.Name(), ".active") {
			continue
		}
		name := strings.TrimSuffix(entry.Name(), ".active")
		if _, err := recordTime(name); err != nil {
			continue
		}
		info, err := entry.Info()
		if err != nil {
			return err
		}
		if !info.Mode().IsRegular() || info.Size() != 0 {
			continue
		}
		if err := removeOrphanRecordMarker(dir, name); err != nil {
			return err
		}
	}
	return nil
}

func removeOrphanRecordMarker(dir, name string) (err error) {
	data := filepath.Join(dir, name)
	if _, err := os.Lstat(data); !errors.Is(err, os.ErrNotExist) {
		return err // Existing data of any type is not an orphan.
	}
	path := activeRecordPath(dir, name)
	file, err := lockRecordPath(path, recordLockExisting)
	if errors.Is(err, ErrStorageBusy) || errors.Is(err, os.ErrNotExist) {
		return nil
	}
	if err != nil {
		return err
	}
	defer func() {
		if file != nil {
			if closeErr := file.Close(); err == nil {
				err = closeErr
			}
		}
	}()
	info, err := file.Stat()
	if err != nil {
		return err
	}
	if !info.Mode().IsRegular() || info.Size() != 0 {
		return nil
	}
	if _, err := os.Lstat(data); !errors.Is(err, os.ErrNotExist) {
		return err
	}
	closeErr := file.Close()
	file = nil
	if closeErr != nil {
		return closeErr
	}
	// Windows cannot unlink our exclusively opened marker. The enclosing
	// directory lock serializes cooperating creators through this close/remove.
	current, err := os.Lstat(path)
	if errors.Is(err, os.ErrNotExist) {
		return nil
	}
	if err != nil {
		return err
	}
	if !current.Mode().IsRegular() || current.Size() != 0 || !os.SameFile(info, current) {
		return nil
	}
	return os.Remove(path)
}
