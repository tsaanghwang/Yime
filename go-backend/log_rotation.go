package main

import (
	"fmt"
	"os"
	"path/filepath"
	"sync"
)

const (
	defaultLogMaxSize = 10 * 1024 * 1024
	defaultLogBackups = 5
)

type rotatingLogWriter struct {
	mu         sync.Mutex
	path       string
	maxSize    int64
	maxBackups int
	file       *os.File
	size       int64
}

func newRotatingLogWriter(path string, maxSize int64, maxBackups int) (*rotatingLogWriter, error) {
	if maxSize <= 0 {
		return nil, fmt.Errorf("log max size must be positive")
	}
	if maxBackups < 0 {
		return nil, fmt.Errorf("log backup count must not be negative")
	}
	w := &rotatingLogWriter{path: path, maxSize: maxSize, maxBackups: maxBackups}
	if err := w.open(); err != nil {
		return nil, err
	}
	return w, nil
}

func (w *rotatingLogWriter) open() error {
	file, err := os.OpenFile(w.path, os.O_CREATE|os.O_WRONLY|os.O_APPEND, 0o666)
	if err != nil {
		return err
	}
	info, err := file.Stat()
	if err != nil {
		file.Close()
		return err
	}
	w.file, w.size = file, info.Size()
	return nil
}

func (w *rotatingLogWriter) Write(p []byte) (int, error) {
	w.mu.Lock()
	defer w.mu.Unlock()
	if w.file == nil {
		return 0, os.ErrClosed
	}
	if w.size > 0 && w.size+int64(len(p)) > w.maxSize {
		if err := w.rotate(); err != nil {
			return 0, err
		}
	}
	n, err := w.file.Write(p)
	w.size += int64(n)
	return n, err
}

func (w *rotatingLogWriter) Close() error {
	w.mu.Lock()
	defer w.mu.Unlock()
	if w.file == nil {
		return nil
	}
	err := w.file.Close()
	w.file = nil
	return err
}

func (w *rotatingLogWriter) rotate() error {
	if err := w.file.Close(); err != nil {
		return err
	}
	w.file = nil
	if w.maxBackups == 0 {
		if err := os.Remove(w.path); err != nil && !os.IsNotExist(err) {
			return err
		}
	} else {
		if err := os.Remove(backupLogPath(w.path, w.maxBackups)); err != nil && !os.IsNotExist(err) {
			return err
		}
		for i := w.maxBackups - 1; i >= 1; i-- {
			if err := renameIfExists(backupLogPath(w.path, i), backupLogPath(w.path, i+1)); err != nil {
				return err
			}
		}
		if err := renameIfExists(w.path, backupLogPath(w.path, 1)); err != nil {
			return err
		}
	}
	return w.open()
}

func backupLogPath(path string, index int) string { return fmt.Sprintf("%s.%d", path, index) }

func renameIfExists(oldPath, newPath string) error {
	if err := os.Rename(oldPath, newPath); err != nil && !os.IsNotExist(err) {
		return fmt.Errorf("rotate log %s to %s: %w", filepath.Base(oldPath), filepath.Base(newPath), err)
	}
	return nil
}
