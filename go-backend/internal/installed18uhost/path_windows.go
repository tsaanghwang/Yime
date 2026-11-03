//go:build windows

package installed18uhost

import "syscall"

func reparse(path string) bool {
	p, e := syscall.UTF16PtrFromString(path)
	if e != nil {
		return true
	}
	a, e := syscall.GetFileAttributes(p)
	return e != nil || a&0x400 != 0
}
