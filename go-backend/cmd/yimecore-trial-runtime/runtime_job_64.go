//go:build windows && (amd64 || arm64)

package main

import (
	"encoding/binary"
	"fmt"
	"unsafe"
)

func setKillOnJobClose(handle uintptr) error {
	var information [144]byte
	binary.LittleEndian.PutUint32(information[16:20], jobObjectLimitKillOnJobClose)
	set, _, callErr := procSetJobInfo.Call(
		handle, jobObjectExtendedLimitInformation,
		uintptr(unsafe.Pointer(&information[0])), uintptr(len(information)),
	)
	if set == 0 {
		return fmt.Errorf("SetInformationJobObject failed: %w", callErr)
	}
	return nil
}
