//go:build windows

package yime

import (
	"os"
	"path/filepath"
	"syscall"
	"unsafe"
)

const inputToolbarWindowClass = "YimeInputToolbar"

var (
	inputToolbarUser32       = syscall.NewLazyDLL("user32.dll")
	inputToolbarFindWindowW  = inputToolbarUser32.NewProc("FindWindowW")
	inputToolbarPostMessageW = inputToolbarUser32.NewProc("PostMessageW")
)

func platformInputToolbarVisible() bool {
	className, _ := syscall.UTF16PtrFromString(inputToolbarWindowClass)
	hwnd, _, _ := inputToolbarFindWindowW.Call(
		uintptr(unsafe.Pointer(className)),
		0,
	)
	return hwnd != 0
}

func platformToggleInputToolbar(ime *IME) error {
	className, _ := syscall.UTF16PtrFromString(inputToolbarWindowClass)
	hwnd, _, _ := inputToolbarFindWindowW.Call(
		uintptr(unsafe.Pointer(className)),
		0,
	)
	if hwnd != 0 {
		const wmClose = 0x0010
		inputToolbarPostMessageW.Call(hwnd, wmClose, 0, 0)
		return nil
	}
	toolPath := ime.inputToolbarPath()
	if toolPath == "" {
		return os.ErrNotExist
	}
	return startDetachedExecutable(
		toolPath,
		"-StatePath", ime.inputToolbarStatePath(),
		"-SettingsTool", ime.settingsToolPath(),
		"-UserDir", ime.userDir(),
		"-SharedDir", ime.sharedDir(),
		"-HelpDir", ime.helpDir(),
		"-LogDir", filepath.Join(os.Getenv("LOCALAPPDATA"), "PIME", "Logs"),
	)
}

func (ime *IME) inputToolbarPath() string {
	exePath, err := os.Executable()
	if err != nil {
		return ""
	}
	return filepath.Join(filepath.Dir(exePath), "input-toolbar.exe")
}
