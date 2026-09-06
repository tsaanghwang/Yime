//go:build windows

package main

import (
	"errors"
	"os"
	"path/filepath"
	"syscall"
)

func packagePlainPath(path string) error {
	abs, err := filepath.Abs(path)
	if err != nil {
		return err
	}
	for current := abs; ; current = filepath.Dir(current) {
		pointer, err := syscall.UTF16PtrFromString(current)
		if err != nil {
			return err
		}
		attributes, err := syscall.GetFileAttributes(pointer)
		if err != nil && !os.IsNotExist(err) {
			return err
		}
		if err == nil && attributes&syscall.FILE_ATTRIBUTE_REPARSE_POINT != 0 {
			return errors.New("reparse points forbidden in candidate package paths")
		}
		if filepath.Dir(current) == current {
			return nil
		}
	}
}
