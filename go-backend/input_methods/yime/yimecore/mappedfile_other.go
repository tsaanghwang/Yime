//go:build !windows

package yimecore

import (
	"io"
	"os"
)

func mapIndexFile(file *os.File, size int64) ([]byte, func() error, error) {
	data, err := io.ReadAll(io.NewSectionReader(file, 0, size))
	if err != nil {
		return nil, nil, err
	}
	return data, func() error { return nil }, nil
}
