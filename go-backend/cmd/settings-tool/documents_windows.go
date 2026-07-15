//go:build windows

package main

import (
	"os"
	"path/filepath"
	"syscall"
	"unsafe"
)

var (
	modshell32Settings               = syscall.NewLazyDLL("shell32.dll")
	modole32Settings                 = syscall.NewLazyDLL("ole32.dll")
	procSHGetKnownFolderPathSettings = modshell32Settings.NewProc("SHGetKnownFolderPath")
	procCoTaskMemFreeSettings        = modole32Settings.NewProc("CoTaskMemFree")
)

type knownFolderID struct {
	Data1 uint32
	Data2 uint16
	Data3 uint16
	Data4 [8]byte
}

func windowsDocumentsDirectory() string {
	documents := knownFolderID{
		Data1: 0xFDD39AD0,
		Data2: 0x238F,
		Data3: 0x46AF,
		Data4: [8]byte{0xAD, 0xB4, 0x6C, 0x85, 0x48, 0x03, 0x69, 0xC7},
	}
	var pathPtr *uint16
	result, _, _ := procSHGetKnownFolderPathSettings.Call(
		uintptr(unsafe.Pointer(&documents)), 0, 0, uintptr(unsafe.Pointer(&pathPtr)),
	)
	if result == 0 && pathPtr != nil {
		defer procCoTaskMemFreeSettings.Call(uintptr(unsafe.Pointer(pathPtr)))
		return utf16StringFromPointer(pathPtr)
	}
	home, err := os.UserHomeDir()
	if err != nil {
		return ""
	}
	return filepath.Join(home, "Documents")
}

func utf16StringFromPointer(ptr *uint16) string {
	if ptr == nil {
		return ""
	}
	units := make([]uint16, 0, 260)
	for index := uintptr(0); ; index++ {
		unit := *(*uint16)(unsafe.Add(unsafe.Pointer(ptr), index*2))
		if unit == 0 {
			break
		}
		units = append(units, unit)
	}
	return syscall.UTF16ToString(units)
}

func defaultBackupRoot() string {
	documents := windowsDocumentsDirectory()
	if documents == "" {
		return ""
	}
	return filepath.Join(documents, "YIME 备份")
}
