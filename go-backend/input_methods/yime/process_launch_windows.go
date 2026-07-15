//go:build windows

package yime

import "github.com/tsaanghwang/Yime/go-backend/input_methods/yime/win32ui"

func startDetachedExecutable(filePath string, args ...string) error {
	return win32ui.StartDetachedGUIExecutable(filePath, args...)
}
