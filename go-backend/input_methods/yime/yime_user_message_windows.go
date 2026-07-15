//go:build windows

package yime

import (
	"syscall"
	"unsafe"
)

var showUserMessageBox = msgBoxW

const (
	mbSetForeground                  uintptr = 0x00010000
	mbTopmost                        uintptr = 0x00040000
	mbDefaultButton2                 uintptr = 0x00000100
	maintenanceDialogVisibilityFlags         = mbSetForeground | mbTopmost
)

func requestRimeRedeployConfirmation() bool {
	return confirmMessageBoxW(
		"重新部署 Rime",
		"重新部署仅用于手工修改配置后使其生效，或修复 Rime 配置异常。\n\n"+
			"操作会在后台重新编译运行数据，并在下一次输入时重建当前会话；不会恢复默认词库，也不会删除用户词库。\n\n"+
			"一般情况下无需执行。确定要继续吗？",
	)
}

func requestRimeSyncConfirmation() bool {
	return confirmMessageBoxW(
		"同步 Rime 用户数据",
		"此操作只同步 Rime 自己管理的用户学习数据，不包含 YIME 设置、用户词库源文件和屏蔽词表。\n\n确定要继续吗？",
	)
}

func (ime *IME) showUserLexiconMessage(title, message, icon string) {
	ime.showUserMessage(title, message, icon)
}

func (ime *IME) showUserMessage(title, message, icon string) {
	if title == "" {
		title = "音元输入法"
	}
	if message == "" {
		return
	}
	showUserMessageBox(title, message, icon)
}

func msgBoxW(title, message, icon string) {
	user32 := syscall.NewLazyDLL("user32.dll")
	messageBoxW := user32.NewProc("MessageBoxW")

	var mbIcon uintptr
	switch icon {
	case "Error":
		mbIcon = 0x10
	case "Warning":
		mbIcon = 0x30
	case "Information":
		mbIcon = 0x40
	default:
		mbIcon = 0x40
	}

	titlePtr, err := syscall.UTF16PtrFromString(title)
	if err != nil {
		return
	}
	messagePtr, err := syscall.UTF16PtrFromString(message)
	if err != nil {
		return
	}

	// These notifications can be emitted by a background maintenance worker.
	// Force them above ordinary windows so they do not appear only as a taskbar
	// button while the user waits for a result.
	messageBoxW.Call(0, uintptr(unsafe.Pointer(messagePtr)), uintptr(unsafe.Pointer(titlePtr)), mbIcon|maintenanceDialogVisibilityFlags)
}

func confirmMessageBoxW(title, message string) bool {
	user32 := syscall.NewLazyDLL("user32.dll")
	messageBoxW := user32.NewProc("MessageBoxW")
	getForegroundWindow := user32.NewProc("GetForegroundWindow")
	titlePtr, err := syscall.UTF16PtrFromString(title)
	if err != nil {
		return false
	}
	messagePtr, err := syscall.UTF16PtrFromString(message)
	if err != nil {
		return false
	}
	// Attach the confirmation to the application from which the language-bar
	// menu was opened. Visibility flags cover hosts that do not allow a normal
	// cross-process owner relationship. Cancel remains the default button.
	owner, _, _ := getForegroundWindow.Call()
	flags := uintptr(0x01|0x30) | mbDefaultButton2 | maintenanceDialogVisibilityFlags
	result, _, _ := messageBoxW.Call(owner, uintptr(unsafe.Pointer(messagePtr)), uintptr(unsafe.Pointer(titlePtr)), flags)
	return result == 1 // IDOK
}
