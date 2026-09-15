//go:build windows

package yimecore

import (
	"fmt"
	"os"
	"reflect"
	"syscall"
	"unsafe"
)

func mapIndexFile(file *os.File, size int64) ([]byte, func() error, error) {
	if size <= 0 || uint64(size) > uint64(^uint(0)>>1) {
		return nil, nil, fmt.Errorf("unsupported mapping size %d", size)
	}
	mapping, err := syscall.CreateFileMapping(syscall.Handle(file.Fd()), nil, syscall.PAGE_READONLY, 0, 0, nil)
	if err != nil {
		return nil, nil, err
	}
	address, err := syscall.MapViewOfFile(mapping, syscall.FILE_MAP_READ, 0, 0, uintptr(size))
	if err != nil {
		_ = syscall.CloseHandle(mapping)
		return nil, nil, err
	}
	data := mappedBytes(address, int(size))
	closeMapping := func() error {
		unmapErr := syscall.UnmapViewOfFile(address)
		closeErr := syscall.CloseHandle(mapping)
		if unmapErr != nil {
			return unmapErr
		}
		return closeErr
	}
	return data, closeMapping, nil
}

func mappedBytes(address uintptr, size int) []byte {
	var data []byte
	header := (*reflect.SliceHeader)(unsafe.Pointer(&data))
	header.Data = address
	header.Len = size
	header.Cap = size
	return data
}
