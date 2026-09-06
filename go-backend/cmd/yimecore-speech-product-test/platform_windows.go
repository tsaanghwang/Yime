//go:build windows

package main

import (
	"errors"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"syscall"
	"unsafe"
)

var kernel = syscall.NewLazyDLL("kernel32.dll")
var queryImage = kernel.NewProc("QueryFullProcessImageNameW")
var pipeServerPID = kernel.NewProc("GetNamedPipeServerProcessId")
var getWindowsDirectory = kernel.NewProc("GetWindowsDirectoryW")
var profileDirectory = syscall.NewLazyDLL("userenv.dll").NewProc("GetUserProfileDirectoryW")
var errForeignPipe = errors.New("private pipe server PID differs from verified owned child")

type processHandle struct {
	handle   syscall.Handle
	evidence processEvidence
}

func (h *processHandle) alive() bool {
	if h == nil || h.handle == 0 {
		return false
	}
	r, e := syscall.WaitForSingleObject(h.handle, 0)
	// Unknown liveness must not be reported as a successfully stopped process.
	return e != nil || r != syscall.WAIT_OBJECT_0
}
func (h *processHandle) close() {
	if h != nil && h.handle != 0 {
		syscall.CloseHandle(h.handle)
		h.handle = 0
	}
}
func hideProcess(cmd *exec.Cmd) { cmd.SysProcAttr = &syscall.SysProcAttr{HideWindow: true} }
func windowsDirectory() (string, error) {
	b := make([]uint16, 32768)
	n, _, e := getWindowsDirectory.Call(uintptr(unsafe.Pointer(&b[0])), uintptr(len(b)))
	if n == 0 || n >= uintptr(len(b)) {
		return "", e
	}
	return syscall.UTF16ToString(b[:n]), nil
}
func tokenSID(process syscall.Handle) (string, error) {
	var token syscall.Token
	if err := syscall.OpenProcessToken(process, syscall.TOKEN_QUERY, &token); err != nil {
		return "", err
	}
	defer token.Close()
	user, err := token.GetTokenUser()
	if err != nil {
		return "", err
	}
	return user.User.Sid.String()
}
func actualProfile() (string, string, error) {
	process, err := syscall.GetCurrentProcess()
	if err != nil {
		return "", "", err
	}
	sid, err := tokenSID(process)
	if err != nil {
		return "", "", err
	}
	var token syscall.Token
	if err = syscall.OpenProcessToken(process, syscall.TOKEN_QUERY, &token); err != nil {
		return "", "", err
	}
	defer token.Close()
	var size uint32
	_, _, _ = profileDirectory.Call(uintptr(token), 0, uintptr(unsafe.Pointer(&size)))
	if size < 2 || size > 32768 {
		return "", "", errors.New("OS profile length unavailable")
	}
	buffer := make([]uint16, size)
	ok, _, e := profileDirectory.Call(uintptr(token), uintptr(unsafe.Pointer(&buffer[0])), uintptr(unsafe.Pointer(&size)))
	if ok == 0 {
		return "", "", e
	}
	profile := syscall.UTF16ToString(buffer)
	if err = plainPath(profile); err != nil {
		return "", "", err
	}
	return profile, sid, nil
}
func plainPath(path string) error {
	if !filepath.IsAbs(path) || len(path) < 4 || path[1] != ':' || strings.HasPrefix(path, `\\`) {
		return errors.New("canonical absolute local path required")
	}
	if strings.ContainsAny(path[2:], `:*?"<>|`) || strings.Contains(path, "/") {
		return errors.New("ambiguous local path")
	}
	for _, part := range strings.Split(path[3:], `\`) {
		if part == "" || part == "." || part == ".." || strings.TrimRight(part, ". ") != part {
			return errors.New("ambiguous local path component")
		}
		device := strings.ToUpper(strings.SplitN(part, ".", 2)[0])
		if device == "CON" || device == "NUL" || device == "AUX" || device == "PRN" || (len(device) == 4 && (strings.HasPrefix(device, "COM") || strings.HasPrefix(device, "LPT")) && device[3] >= '1' && device[3] <= '9') {
			return errors.New("device path forbidden")
		}
	}
	for current := path; ; current = filepath.Dir(current) {
		pointer, err := syscall.UTF16PtrFromString(current)
		if err != nil {
			return err
		}
		attrs, err := syscall.GetFileAttributes(pointer)
		if err != nil && !os.IsNotExist(err) {
			return err
		}
		if err == nil && attrs&syscall.FILE_ATTRIBUTE_REPARSE_POINT != 0 {
			return errors.New("reparse traversal forbidden")
		}
		if filepath.Dir(current) == current {
			return nil
		}
	}
}
func bindProcess(pid uint32, image string, parent uint32, after uint64, sid string) (*processHandle, error) {
	handle, err := syscall.OpenProcess(0x1000|syscall.SYNCHRONIZE, false, pid)
	if err != nil {
		return nil, err
	}
	h := &processHandle{handle: handle}
	success := false
	defer func() {
		if !success {
			h.close()
		}
	}()
	if !h.alive() {
		return nil, errors.New("target process already exited")
	}
	buffer := make([]uint16, 32768)
	size := uint32(len(buffer))
	ok, _, e := queryImage.Call(uintptr(handle), 0, uintptr(unsafe.Pointer(&buffer[0])), uintptr(unsafe.Pointer(&size)))
	if ok == 0 {
		return nil, e
	}
	actualImage := syscall.UTF16ToString(buffer[:size])
	if !strings.EqualFold(actualImage, image) {
		return nil, errors.New("owned child image mismatch")
	}
	var created, exited, kernelTime, userTime syscall.Filetime
	if err = syscall.GetProcessTimes(handle, &created, &exited, &kernelTime, &userTime); err != nil {
		return nil, err
	}
	start := uint64(created.HighDateTime)<<32 | uint64(created.LowDateTime)
	if start < after {
		return nil, errors.New("owned child start predates parent")
	}
	actualSID, err := tokenSID(handle)
	if err != nil || actualSID != sid {
		return nil, errors.New("owned child SID mismatch")
	}
	snapshot, err := syscall.CreateToolhelp32Snapshot(syscall.TH32CS_SNAPPROCESS, 0)
	if err != nil {
		return nil, err
	}
	defer syscall.CloseHandle(snapshot)
	entry := syscall.ProcessEntry32{Size: uint32(unsafe.Sizeof(syscall.ProcessEntry32{}))}
	found := false
	for e := syscall.Process32First(snapshot, &entry); e == nil; e = syscall.Process32Next(snapshot, &entry) {
		if entry.ProcessID == pid {
			found = true
			break
		}
	}
	if !found || entry.ParentProcessID != parent {
		return nil, errors.New("owned child parent mismatch")
	}
	h.evidence = processEvidence{PID: pid, ParentPID: parent, Image: actualImage, Created: start, SID: actualSID}
	success = true
	return h, nil
}
func openOwnedPipe(name string, pid uint32) (*os.File, error) {
	ptr, err := syscall.UTF16PtrFromString(name)
	if err != nil {
		return nil, err
	}
	// Overlapped byte pipe provides bounded I/O via os.File deadlines. Security
	// identification does not delegate our client impersonation token to peers.
	h, err := syscall.CreateFile(ptr, syscall.GENERIC_READ|syscall.GENERIC_WRITE, 0, nil, syscall.OPEN_EXISTING, syscall.FILE_FLAG_OVERLAPPED|0x00100000|0x00010000, 0)
	if err != nil {
		return nil, err
	}
	var server uint32
	ok, _, e := pipeServerPID.Call(uintptr(h), uintptr(unsafe.Pointer(&server)))
	if ok == 0 {
		syscall.CloseHandle(h)
		return nil, e
	}
	if server != pid {
		syscall.CloseHandle(h)
		return nil, errForeignPipe
	}
	f := os.NewFile(uintptr(h), name)
	if f == nil {
		syscall.CloseHandle(h)
		return nil, errors.New("private pipe file unavailable")
	}
	return f, nil
}
