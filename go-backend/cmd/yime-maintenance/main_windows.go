//go:build windows

package main

import (
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"os"
	"os/exec"
	"path/filepath"
	"runtime"
	"sort"
	"strconv"
	"strings"
	"syscall"
	"unsafe"
)

var kernel = syscall.NewLazyDLL("kernel32.dll")
var advapi = syscall.NewLazyDLL("advapi32.dll")
var shell32 = syscall.NewLazyDLL("shell32.dll")
var ole32 = syscall.NewLazyDLL("ole32.dll")
var nativeMachine = kernel.NewProc("IsWow64Process2")
var securityInfo = advapi.NewProc("GetSecurityInfo")
var getACE = advapi.NewProc("GetAce")
var convertSD = advapi.NewProc("ConvertStringSecurityDescriptorToSecurityDescriptorW")
var localFree = kernel.NewProc("LocalFree")

func nativeIdentity() (string, bool, error) {
	if runtime.GOARCH != "arm64" {
		return "", false, errors.New("ARM64 maintenance binary required")
	}
	p, err := syscall.GetCurrentProcess()
	if err != nil {
		return "", false, err
	}
	var process, native uint16
	ok, _, err := nativeMachine.Call(uintptr(p), uintptr(unsafe.Pointer(&process)), uintptr(unsafe.Pointer(&native)))
	if ok == 0 || process != 0 || native != 0xaa64 {
		return "", false, fmt.Errorf("native ARM64 identity unavailable: %v", err)
	}
	return processIdentity(p)
}

func processIdentity(p syscall.Handle) (string, bool, error) {
	var token syscall.Token
	if err := syscall.OpenProcessToken(p, syscall.TOKEN_QUERY, &token); err != nil {
		return "", false, err
	}
	defer token.Close()
	u, err := token.GetTokenUser()
	if err != nil {
		return "", false, err
	}
	sid, err := u.User.Sid.String()
	if err != nil {
		return "", false, err
	}
	var elevation, needed uint32
	if err = syscall.GetTokenInformation(token, 20, (*byte)(unsafe.Pointer(&elevation)), 4, &needed); err != nil {
		return "", false, err
	}
	return sid, elevation != 0, nil
}

func knownFolder(id syscall.GUID) (string, error) {
	var p *uint16
	hr, _, _ := shell32.NewProc("SHGetKnownFolderPath").Call(uintptr(unsafe.Pointer(&id)), 0, 0, uintptr(unsafe.Pointer(&p)))
	if int32(hr) < 0 || p == nil {
		return "", fmt.Errorf("known folder unavailable: %x", hr)
	}
	defer ole32.NewProc("CoTaskMemFree").Call(uintptr(unsafe.Pointer(p)))
	return syscall.UTF16ToString(unsafe.Slice(p, 32768)), nil
}

var programFilesID = syscall.GUID{Data1: 0x905e63b6, Data2: 0xc1bf, Data3: 0x494e, Data4: [8]byte{0xb2, 0x9c, 0x65, 0xb7, 0x32, 0xd3, 0xd2, 0x1a}}
var profileID = syscall.GUID{Data1: 0x5e6c858f, Data2: 0x0e22, Data3: 0x4760, Data4: [8]byte{0x9a, 0xfe, 0xea, 0x33, 0x17, 0xb6, 0x71, 0x73}}
var localID = syscall.GUID{Data1: 0xf1b32785, Data2: 0x6fba, Data3: 0x4fcf, Data4: [8]byte{0x9d, 0x55, 0x7b, 0x8e, 0x7f, 0x15, 0x70, 0x91}}
var roamingID = syscall.GUID{Data1: 0x3eb685db, Data2: 0x65f9, Data3: 0x4cf6, Data4: [8]byte{0xa0, 0x3a, 0xe3, 0xef, 0x65, 0x72, 0x9f, 0x3d}}

func openLocked(path string, directory bool) (*os.File, error) {
	p, err := syscall.UTF16PtrFromString(path)
	if err != nil {
		return nil, err
	}
	access := uint32(syscall.GENERIC_READ | 0x20000)
	flags := uint32(0x00200000)
	share := uint32(syscall.FILE_SHARE_READ)
	if directory {
		access = 0x20080
		flags |= 0x02000000
		share |= syscall.FILE_SHARE_WRITE
	}
	h, err := syscall.CreateFile(p, access, share, nil, syscall.OPEN_EXISTING, flags, 0)
	if err != nil {
		return nil, err
	}
	var info syscall.ByHandleFileInformation
	if err = syscall.GetFileInformationByHandle(h, &info); err != nil || info.FileAttributes&syscall.FILE_ATTRIBUTE_REPARSE_POINT != 0 {
		syscall.CloseHandle(h)
		return nil, errors.New("unavailable or reparse maintenance object")
	}
	if (info.FileAttributes&syscall.FILE_ATTRIBUTE_DIRECTORY != 0) != directory {
		syscall.CloseHandle(h)
		return nil, errors.New("maintenance object type mismatch")
	}
	return os.NewFile(uintptr(h), path), nil
}

type heldFiles struct{ files []*os.File }

func (h *heldFiles) close() {
	for i := len(h.files) - 1; i >= 0; i-- {
		h.files[i].Close()
	}
}
func (h *heldFiles) add(f *os.File) { h.files = append(h.files, f) }
func (h *heldFiles) parents(path string, protected bool) error {
	return h.parentsWithin(path, protected, "")
}
func (h *heldFiles) parentsWithin(path string, protected bool, contentRoot string) error {
	for p := filepath.Dir(path); ; p = filepath.Dir(p) {
		f, err := openLocked(p, true)
		if err != nil {
			return fmt.Errorf("lock ancestor %s: %w", p, err)
		}
		h.add(f)
		if protected {
			if err = checkACL(f, contentRoot != "" && insideDirectory(p, contentRoot)); err != nil {
				return fmt.Errorf("unsafe ancestor %s: %w", p, err)
			}
		}
		if filepath.Dir(p) == p {
			break
		}
	}
	return nil
}

func trustedSID(s string) bool {
	return s == "S-1-5-18" || s == "S-1-5-32-544" || s == "S-1-5-80-956008885-3418522649-1831038044-1853292631-2271478464"
}

type aclHeader struct {
	Revision, Reserved     byte
	Size, Count, Reserved2 uint16
}
type aceHeader struct {
	Type, Flags byte
	Size        uint16
}

func checkACL(f *os.File, content bool) error {
	// These are pointers returned by Windows, not integer handles. Preserve
	// their pointer type while the self-relative security descriptor is alive.
	var owner, dacl, sd unsafe.Pointer
	result, _, _ := securityInfo.Call(f.Fd(), 1, 5, uintptr(unsafe.Pointer(&owner)), 0, uintptr(unsafe.Pointer(&dacl)), 0, uintptr(unsafe.Pointer(&sd)))
	if result != 0 || owner == nil || dacl == nil {
		return errors.New("protected ownership/DACL unavailable")
	}
	defer localFree.Call(uintptr(sd))
	s, err := (*syscall.SID)(owner).String()
	if err != nil || !trustedSID(s) {
		return errors.New("untrusted protected object owner")
	}
	// On an ancestor, adding an unrelated sibling is harmless. Deleting the
	// protected child or changing its owner/ACL/attributes is not. Directory
	// handles additionally deny deletion/rename while maintenance is active.
	mask := mutatingAccessMask(content)
	acl := (*aclHeader)(dacl)
	for i := uint16(0); i < acl.Count; i++ {
		var ptr unsafe.Pointer
		ok, _, _ := getACE.Call(uintptr(dacl), uintptr(i), uintptr(unsafe.Pointer(&ptr)))
		if ok == 0 || ptr == nil {
			return errors.New("ACL entry unavailable")
		}
		a := (*aceHeader)(ptr)
		if a.Flags&8 != 0 || a.Type == 1 {
			continue
		}
		if a.Size < 8 {
			return errors.New("invalid ACL entry")
		}
		rights := *(*uint32)(unsafe.Add(ptr, 4))
		if rights&mask == 0 {
			continue
		}
		if a.Type != 0 {
			return errors.New("unsupported mutating ACL entry")
		}
		sid, err := (*syscall.SID)(unsafe.Add(ptr, 8)).String()
		if err != nil || !trustedSID(sid) {
			return errors.New("non-administrator can mutate protected object")
		}
	}
	return nil
}

func createProtected(path string) error {
	s, err := syscall.UTF16PtrFromString("O:BAG:BAD:P(A;OICI;FA;;;SY)(A;OICI;FA;;;BA)(A;OICI;GRGX;;;BU)")
	if err != nil {
		return err
	}
	var sd uintptr
	ok, _, err := convertSD.Call(uintptr(unsafe.Pointer(s)), 1, uintptr(unsafe.Pointer(&sd)), 0)
	if ok == 0 {
		return err
	}
	defer localFree.Call(sd)
	sa := syscall.SecurityAttributes{Length: uint32(unsafe.Sizeof(syscall.SecurityAttributes{})), SecurityDescriptor: sd}
	p, err := syscall.UTF16PtrFromString(path)
	if err != nil {
		return err
	}
	err = syscall.CreateDirectory(p, &sa)
	if err != nil && err != syscall.ERROR_ALREADY_EXISTS {
		return err
	}
	f, err := openLocked(path, true)
	if err != nil {
		return err
	}
	defer f.Close()
	return checkACL(f, true)
}

func fileDigest(f *os.File) (string, error) {
	if _, err := f.Seek(0, 0); err != nil {
		return "", err
	}
	h := sha256.New()
	_, err := io.Copy(h, f)
	if err != nil {
		return "", err
	}
	_, err = f.Seek(0, 0)
	return hex.EncodeToString(h.Sum(nil)), err
}
func copyExact(source *os.File, dest string) error {
	if _, err := source.Seek(0, 0); err != nil {
		return err
	}
	f, err := os.OpenFile(dest, os.O_CREATE|os.O_EXCL|os.O_WRONLY, 0600)
	if err != nil {
		return err
	}
	_, copyErr := io.Copy(f, source)
	closeErr := f.Close()
	if copyErr != nil {
		return copyErr
	}
	return closeErr
}

type shellExecuteInfo struct {
	Size, Mask                        uint32
	Window                            uintptr
	Verb, File, Parameters, Directory *uint16
	Show                              int32
	Instance, IDList                  uintptr
	Class                             *uint16
	ClassKey                          uintptr
	HotKey                            uint32
	Icon                              uintptr
	Process                           syscall.Handle
}

func elevate(exe, plan, action, sid string, bindParent bool) error {
	verb, _ := syscall.UTF16PtrFromString("runas")
	file, _ := syscall.UTF16PtrFromString(exe)
	args := []string{"-action", action, "-plan", plan, "-initiating-sid", sid, "-elevated"}
	if bindParent {
		process, err := syscall.GetCurrentProcess()
		if err != nil {
			return err
		}
		started, err := processStarted(process)
		if err != nil {
			return err
		}
		args = append(args, "-parent-pid", strconv.Itoa(os.Getpid()), "-parent-started", strconv.FormatUint(started, 10))
	}
	for i := range args {
		args[i] = syscall.EscapeArg(args[i])
	}
	params, _ := syscall.UTF16PtrFromString(strings.Join(args, " "))
	info := shellExecuteInfo{Mask: 0x40 | 0x100 | 0x400, Verb: verb, File: file, Parameters: params, Show: 0}
	info.Size = uint32(unsafe.Sizeof(info))
	ok, _, err := shell32.NewProc("ShellExecuteExW").Call(uintptr(unsafe.Pointer(&info)))
	if ok == 0 {
		return err
	}
	defer syscall.CloseHandle(info.Process)
	if _, err = syscall.WaitForSingleObject(info.Process, syscall.INFINITE); err != nil {
		return err
	}
	var code uint32
	if err = syscall.GetExitCodeProcess(info.Process, &code); err != nil {
		return err
	}
	if code != 0 {
		return fmt.Errorf("elevated maintenance exit %d", code)
	}
	return nil
}

func maintain(action, planPath, initiatingSID string, elevated bool, parentPID uint, parentStarted uint64) error {
	sid, admin, err := nativeIdentity()
	if err != nil {
		return err
	}
	if initiatingSID != "" && initiatingSID != sid {
		return errors.New("elevation changed initiating account")
	}
	if elevated && (!admin || initiatingSID == "") {
		return errors.New("missing same-account elevation binding")
	}
	planPath, err = filepath.Abs(planPath)
	if err != nil {
		return err
	}
	base := filepath.Dir(planPath)
	held := new(heldFiles)
	defer held.close()
	if err = held.parents(planPath, false); err != nil {
		return err
	}
	pf, err := openLocked(planPath, false)
	if err != nil {
		return err
	}
	held.add(pf)
	raw, err := io.ReadAll(io.LimitReader(pf, 4*1024*1024+1))
	if err != nil {
		return err
	}
	plan, err := parsePlan(raw, expectedPlanSHA)
	if err != nil {
		return err
	}
	names := make([]string, 0, len(plan.Files))
	for name := range plan.Files {
		names = append(names, name)
	}
	sort.Strings(names)
	sources := make(map[string]*os.File)
	for _, name := range names {
		path := filepath.Join(base, filepath.FromSlash(name))
		if err = held.parents(path, false); err != nil {
			return err
		}
		f, e := openLocked(path, false)
		if e != nil {
			return fmt.Errorf("%s: %w", name, e)
		}
		held.add(f)
		if err = verifyStream(f, plan.Files[name]); err != nil {
			return fmt.Errorf("%s: %w", name, err)
		}
		sources[name] = f
	}
	// A package shell is validated as bytes/PE only here, never executed in place.
	if err = verifyNativeShell(sources[shellMember]); err != nil {
		return err
	}
	exe, err := os.Executable()
	if err != nil {
		return err
	}
	if err = held.parents(exe, false); err != nil {
		return err
	}
	self, err := openLocked(exe, false)
	if err != nil {
		return err
	}
	held.add(self)
	selfHash, err := fileDigest(self)
	if err != nil {
		return err
	}
	bindCaller, err := rimeCallerBinding(plan, action, elevated, admin, parentPID, parentStarted)
	if err != nil {
		return err
	}
	if action == "Check" {
		fmt.Println("PASS native ARM64 maintenance: bound plan, all files and bundled ARM64 shell PE; no shell execution or product mutation")
		return nil
	}
	if !admin {
		if err = elevate(exe, planPath, action, sid, plan.Product == "rime-pime" && action == "Install"); err != nil {
			return err
		}
		if action == "Install" {
			return startInstalledRuntime(plan)
		}
		return nil
	}
	var ordinaryParent syscall.Handle
	if bindCaller {
		ordinaryParent, err = holdOrdinaryCaller(parentPID, parentStarted, sid, exe)
		if err != nil {
			return err
		}
		defer syscall.CloseHandle(ordinaryParent)
	}
	programFiles, err := knownFolder(programFilesID)
	if err != nil {
		return err
	}
	if err = held.parents(filepath.Join(programFiles, "placeholder"), true); err != nil {
		return err
	}
	cache := filepath.Join(programFiles, "Yime Maintenance")
	if err = createProtected(cache); err != nil {
		return err
	}
	cache = filepath.Join(cache, plan.Product)
	if err = createProtected(cache); err != nil {
		return err
	}
	// Protect the cache ancestry before copying; staging itself has a protected DACL.
	if err = held.parentsWithin(filepath.Join(cache, "placeholder"), true, cache); err != nil {
		return err
	}
	stage, err := publishStage(cache, expectedPlanSHA, createProtected, func(temp string) error {
		for _, name := range names {
			target := filepath.Join(temp, filepath.FromSlash(name))
			rel, err := filepath.Rel(temp, filepath.Dir(target))
			if err != nil {
				return err
			}
			parent := temp
			if rel != "." {
				for _, part := range strings.Split(rel, string(os.PathSeparator)) {
					parent = filepath.Join(parent, part)
					if err := createProtected(parent); err != nil {
						return err
					}
				}
			}
			if err := copyExact(sources[name], target); err != nil {
				return err
			}
		}
		if err := copyExact(pf, filepath.Join(temp, "maintenance-plan.json")); err != nil {
			return err
		}
		return copyExact(self, filepath.Join(temp, "YimeMaintenance.exe"))
	}, func(temp string) error {
		locks, err := holdVerifiedStage(temp, plan, selfHash)
		if locks != nil {
			locks.close()
		}
		return err
	}, renameDirectoryNoReplace)
	if err != nil {
		return err
	}
	stageHeld, err := holdVerifiedStage(stage, plan, selfHash)
	if err != nil {
		return err
	}
	defer stageHeld.close()
	shellPath := filepath.Join(stage, filepath.FromSlash(shellMember))
	profile, err := knownFolder(profileID)
	if err != nil {
		return err
	}
	local, err := knownFolder(localID)
	if err != nil {
		return err
	}
	roaming, err := knownFolder(roamingID)
	if err != nil {
		return err
	}
	systemDirectory := syscallPathSystemDirectory()
	if systemDirectory == "" {
		return errors.New("system directory unavailable")
	}
	systemRoot := filepath.Dir(systemDirectory)
	// Explicit environment: no user module path, CLR startup hooks, package
	// current directory or inherited executable search path enters elevation.
	env := maintenanceEnvironment(systemRoot, programFiles, profile, local, roaming, shellPath)
	parameters := maintenanceParameters(action, sid, stage, selfHash, expectedPlanSHA, ordinaryParent != 0)
	request := map[string]any{"script": filepath.Join(stage, "Setup.ps1"), "command": nil, "check_only": false, "parameters": parameters}
	input, err := json.Marshal(request)
	if err != nil {
		return err
	}
	cmd := exec.Command(shellPath, "-NoLogo", "-NoProfile", "-NonInteractive", "-ExecutionPolicy", "Bypass", "-File", filepath.Join(stage, "maintenance", "preflight.ps1"))
	cmd.Dir = stage
	cmd.Env = env
	cmd.Stdin = strings.NewReader(string(input))
	cmd.Stdout = os.Stdout
	cmd.Stderr = os.Stderr
	cmd.SysProcAttr = &syscall.SysProcAttr{HideWindow: true}
	if err = cmd.Run(); err != nil {
		return fmt.Errorf("protected setup: %w", err)
	}
	if ordinaryParent != 0 {
		if err = requireLiveProcess(ordinaryParent); err != nil {
			return fmt.Errorf("installation caller exited before user validation: %w", err)
		}
		fmt.Println("Protected system installation completed; mandatory Rime user registration validation remains with the original ordinary caller.")
		return nil
	}
	fmt.Println("PASS protected maintenance completed:", action, plan.Product)
	if action == "Install" {
		fmt.Println("Runtime was not started from the elevated process; the original non-administrator caller starts it after verification.")
	}
	return nil
}

func maintenanceEnvironment(systemRoot, programFiles, profile, local, roaming, shellPath string) []string {
	// Without an explicit PATHEXT, PowerShell can initialize it as .CPL and
	// reject an .exe in a pipeline as a document. All maintenance native
	// commands use explicit .exe paths; never inherit user extension handlers.
	return []string{
		"SystemRoot=" + systemRoot, "WINDIR=" + systemRoot,
		"ProgramFiles=" + programFiles, "USERPROFILE=" + profile,
		"LOCALAPPDATA=" + local, "APPDATA=" + roaming,
		"PATH=" + filepath.Join(systemRoot, "System32"), "PATHEXT=.EXE",
		"TEMP=" + filepath.Join(systemRoot, "Temp"), "TMP=" + filepath.Join(systemRoot, "Temp"),
		"PSModulePath=" + filepath.Join(filepath.Dir(shellPath), "Modules") + ";" + filepath.Join(systemRoot, "System32", "WindowsPowerShell", "v1.0", "Modules"),
	}
}

func syscallPathSystemDirectory() string {
	buf := make([]uint16, 32768)
	n, _, _ := kernel.NewProc("GetSystemDirectoryW").Call(uintptr(unsafe.Pointer(&buf[0])), uintptr(len(buf)))
	if n == 0 || n >= uintptr(len(buf)) {
		return ""
	}
	return syscall.UTF16ToString(buf[:n])
}
