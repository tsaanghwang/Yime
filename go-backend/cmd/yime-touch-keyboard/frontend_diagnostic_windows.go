//go:build windows && (amd64 || arm64)

package main

import (
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"syscall"
	"time"
	"unsafe"
)

// No document title, text, composition, or candidate content is collected.
type frontendDiagnostic struct {
	Time                                         string `json:"time"`
	Build                                        string `json:"build"`
	Stage                                        string `json:"stage"`
	Error                                        string `json:"error,omitempty"`
	Window, Focus                                uintptr
	Process, Thread, WindowProcess, WindowThread uint32
	WindowClass, FocusClass                      string
}

func diagnosticTarget() frontendDiagnostic {
	t := foreground()
	d := frontendDiagnostic{Time: time.Now().Format(time.RFC3339Nano), Build: "18u-auto-focus-dev", Window: t.Window, Focus: t.Focus}
	thread, _, _ := U("GetWindowThreadProcessId").Call(t.Focus, uintptr(unsafe.Pointer(&d.Process)))
	d.Thread = uint32(thread)
	thread, _, _ = U("GetWindowThreadProcessId").Call(t.Window, uintptr(unsafe.Pointer(&d.WindowProcess)))
	d.WindowThread = uint32(thread)
	class := func(h uintptr) string {
		var b [256]uint16
		n, _, _ := U("GetClassNameW").Call(h, uintptr(unsafe.Pointer(&b[0])), 256)
		if n == 0 {
			return ""
		}
		return syscall.UTF16ToString(b[:n])
	}
	d.WindowClass, d.FocusClass = class(t.Window), class(t.Focus)
	return d
}

func saveFrontendDiagnostic(dir string, d frontendDiagnostic) (string, error) {
	if err := os.MkdirAll(dir, 0700); err != nil {
		return "", err
	}
	f, err := os.CreateTemp(dir, "binding-*.json")
	if err != nil {
		return "", err
	}
	path := f.Name()
	encoder := json.NewEncoder(f)
	encoder.SetIndent("", "  ")
	err = encoder.Encode(d)
	closeErr := f.Close()
	if err == nil {
		err = closeErr
	}
	return path, err
}

func (a *ui) recordFrontendDiagnostic(d frontendDiagnostic, stage string, err error) {
	d.Stage = stage
	result := "绑定成功；尚未证明中文提交成功"
	if err != nil {
		d.Error = err.Error()
		result = "绑定失败：" + d.Error
	}
	a.diagnosticSummary = "最近" + result + "；设置→最近诊断"
	root, e := os.UserCacheDir()
	path := ""
	if e == nil {
		path, e = saveFrontendDiagnostic(filepath.Join(root, "Yime18uTouch", "Diagnostics"), d)
	}
	storage := "记录：" + path
	if e != nil {
		storage = "诊断保存失败：" + e.Error()
	}
	a.diagnosticPages = []string{fmt.Sprintf("%s\n阶段：%s\n时间：%s", result, stage, d.Time), fmt.Sprintf("顶层 HWND=%x PID=%d TID=%d 类=%s\n正文 HWND=%x PID=%d TID=%d 类=%s", d.Window, d.WindowProcess, d.WindowThread, d.WindowClass, d.Focus, d.Process, d.Thread, d.FocusClass), storage + "\n不含正文、标题或组码。文字提交不自动补发；连接状态查询不修改正文。"}
}
