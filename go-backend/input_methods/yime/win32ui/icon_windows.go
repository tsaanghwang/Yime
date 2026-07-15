//go:build windows

package win32ui

import (
	"os"
	"path/filepath"
	"syscall"
	"unsafe"
)

const (
	imageIcon      = 1
	lrLoadFromFile = 0x0010
	lrDefaultSize  = 0x0040
	idiApplication = 32512
)

var (
	iconUser32     = syscall.NewLazyDLL("user32.dll")
	iconLoadImageW = iconUser32.NewProc("LoadImageW")
	iconLoadIconW  = iconUser32.NewProc("LoadIconW")
)

// LoadYimeIcon loads the shared input-profile icon used by every Yime window.
// Keeping the icon outside the executable lets profile and tool-window branding
// stay synchronized without depending on each executable's embedded resource.
func LoadYimeIcon(instance uintptr) uintptr {
	executable, err := os.Executable()
	if err == nil {
		path := yimeIconPath(executable)
		if encoded, encodeErr := syscall.UTF16PtrFromString(path); encodeErr == nil {
			if icon, _, _ := iconLoadImageW.Call(
				0,
				uintptr(unsafe.Pointer(encoded)),
				imageIcon,
				0,
				0,
				lrLoadFromFile|lrDefaultSize,
			); icon != 0 {
				return icon
			}
		}
	}
	icon, _, _ := iconLoadIconW.Call(instance, idiApplication)
	return icon
}

func yimeIconPath(executable string) string {
	return filepath.Join(filepath.Dir(executable), "input_methods", "yime", "icon.ico")
}
