//go:build windows

package main

import (
	"encoding/binary"
	"io"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"syscall"
	"testing"
)

func TestOrdinaryCallerHandleRequiresLiveMatchingProcess(t *testing.T) {
	self, err := syscall.GetCurrentProcess()
	if err != nil {
		t.Fatal(err)
	}
	started, err := processStarted(self)
	if err != nil {
		t.Fatal(err)
	}
	sid, elevated, err := processIdentity(self)
	if err != nil {
		t.Fatal(err)
	}
	image, err := os.Executable()
	if err != nil {
		t.Fatal(err)
	}
	h, err := holdOrdinaryCaller(uint(os.Getpid()), started, sid, image)
	if elevated {
		if err == nil {
			syscall.CloseHandle(h)
			t.Fatal("accepted elevated caller")
		}
	} else {
		if err != nil {
			t.Fatal(err)
		}
		if err = requireLiveProcess(h); err != nil {
			t.Fatal(err)
		}
		syscall.CloseHandle(h)
	}
	for _, tc := range []struct {
		pid        uint
		time       uint64
		sid, image string
	}{
		{0, started, sid, image}, {uint(os.Getpid()), 0, sid, image},
		{uint(os.Getpid()), started + 1, sid, image},
		{uint(os.Getpid()), started, "another-sid", image},
		{uint(os.Getpid()), started, sid, image + ".foreign"},
	} {
		if h, err := holdOrdinaryCaller(tc.pid, tc.time, tc.sid, tc.image); err == nil {
			syscall.CloseHandle(h)
			t.Fatalf("accepted mismatched caller: %+v", tc)
		}
	}
	// An isolated copy of this test process exits without any product operation.
	cmd := exec.Command(image, "-test.run=^TestOrdinaryCallerExitFixture$")
	cmd.Env = append(os.Environ(), "YIME_CALLER_EXIT_FIXTURE=1")
	cmd.SysProcAttr = &syscall.SysProcAttr{HideWindow: true}
	input, err := cmd.StdinPipe()
	if err != nil {
		t.Fatal(err)
	}
	if err := cmd.Start(); err != nil {
		input.Close()
		t.Fatal(err)
	}
	dead, err := syscall.OpenProcess(syscall.SYNCHRONIZE, false, uint32(cmd.Process.Pid))
	// EOF explicitly releases the fixture only after its handle has been opened.
	input.Close()
	if err != nil {
		cmd.Wait()
		t.Fatal(err)
	}
	defer syscall.CloseHandle(dead)
	if err := cmd.Wait(); err != nil {
		t.Fatal(err)
	}
	if err := requireLiveProcess(dead); err == nil {
		t.Fatal("accepted an exited parent handle")
	}
}

func TestOrdinaryCallerExitFixture(t *testing.T) {
	if os.Getenv("YIME_CALLER_EXIT_FIXTURE") == "1" {
		_, _ = io.Copy(io.Discard, os.Stdin)
		os.Exit(0)
	}
}

func TestMaintenanceEnvironmentKeepsExecutablePipelineAndIsolation(t *testing.T) {
	// Parent-supplied values must never replace the elevated allowlist.
	t.Setenv("PATHEXT", ".CPL;.PS1;.UNTRUSTED")
	t.Setenv("PATH", `C:\untrusted\bin`)
	t.Setenv("PSModulePath", `C:\untrusted\modules`)
	t.Setenv("DOTNET_STARTUP_HOOKS", `C:\untrusted\hook.dll`)
	env := maintenanceEnvironment(`C:\Windows`, `C:\Program Files`, `C:\Users\tester`,
		`C:\Users\tester\AppData\Local`, `C:\Users\tester\AppData\Roaming`,
		`C:\Program Files\Yime Maintenance\owned\maintenance\powershell\pwsh.exe`)
	values := make(map[string]string)
	for _, entry := range env {
		name, value, ok := strings.Cut(entry, "=")
		key := strings.ToUpper(name)
		if !ok || values[key] != "" {
			t.Fatalf("invalid or duplicate environment entry: %q", entry)
		}
		values[key] = value
		if strings.Contains(strings.ToLower(value), "untrusted") {
			t.Fatalf("inherited user environment entered maintenance: %q", entry)
		}
	}
	if values["PATHEXT"] != ".EXE" {
		t.Fatalf("native .exe pipeline requires the fixed extension: %q", values["PATHEXT"])
	}
	if values["PATH"] != `C:\Windows\System32` || values["DOTNET_STARTUP_HOOKS"] != "" {
		t.Fatal("maintenance executable search or CLR isolation changed")
	}
	wantModules := `C:\Program Files\Yime Maintenance\owned\maintenance\powershell\Modules;C:\Windows\System32\WindowsPowerShell\v1.0\Modules`
	if values["PSMODULEPATH"] != wantModules || len(values) != 11 {
		t.Fatalf("maintenance allowlist changed: %v", values)
	}
}

func TestLockedFilesAndAncestorsDenyReplacement(t *testing.T) {
	root := t.TempDir()
	dir := filepath.Join(root, "entry")
	if err := os.Mkdir(dir, 0700); err != nil {
		t.Fatal(err)
	}
	path := filepath.Join(dir, "runtime.bin")
	if err := os.WriteFile(path, []byte("checked"), 0600); err != nil {
		t.Fatal(err)
	}
	h := new(heldFiles)
	if err := h.parents(path, false); err != nil {
		t.Fatal(err)
	}
	f, err := openLocked(path, false)
	if err != nil {
		h.close()
		t.Fatal(err)
	}
	h.add(f)
	defer h.close()
	if err := os.WriteFile(path, []byte("changed"), 0600); err == nil {
		t.Fatal("locked bytes could be overwritten")
	}
	if err := os.Rename(path, path+".old"); err == nil {
		t.Fatal("locked entry could be renamed")
	}
	if err := os.Rename(dir, dir+".old"); err == nil {
		t.Fatal("locked executable ancestor could be renamed")
	}
	h.close()
	h.files = nil
	if err := os.Rename(dir, dir+".old"); err != nil {
		t.Fatalf("released ancestors remain locked: %v", err)
	}
}

func TestAtomicPublicationNeverReplacesExistingDirectory(t *testing.T) {
	root := t.TempDir()
	src, dst := filepath.Join(root, "complete"), filepath.Join(root, "published")
	for _, p := range []string{src, dst} {
		if err := os.Mkdir(p, 0700); err != nil {
			t.Fatal(err)
		}
	}
	if err := os.WriteFile(filepath.Join(src, "file"), []byte("new"), 0600); err != nil {
		t.Fatal(err)
	}
	if err := renameDirectoryNoReplace(src, dst); err == nil {
		t.Fatal("atomic publication replaced existing cache")
	}
	if err := os.Remove(dst); err != nil {
		t.Fatal(err)
	}
	if err := renameDirectoryNoReplace(src, dst); err != nil {
		t.Fatal(err)
	}
	if data, err := os.ReadFile(filepath.Join(dst, "file")); err != nil || string(data) != "new" {
		t.Fatalf("publication lost complete bytes: %q %v", data, err)
	}
}

func TestBundledShellPEMustBeARM64(t *testing.T) {
	const offset = 0x80
	data := make([]byte, offset+24+240)
	copy(data, "MZ")
	binary.LittleEndian.PutUint32(data[0x3c:], offset)
	copy(data[offset:], "PE\x00\x00")
	binary.LittleEndian.PutUint16(data[offset+20:], 240)
	binary.LittleEndian.PutUint16(data[offset+22:], 2)
	binary.LittleEndian.PutUint16(data[offset+24:], 0x20b)
	binary.LittleEndian.PutUint32(data[offset+24+108:], 16)
	path := filepath.Join(t.TempDir(), "pwsh.exe")
	check := func(wantPass bool) {
		t.Helper()
		if err := os.WriteFile(path, data, 0600); err != nil {
			t.Fatal(err)
		}
		f, err := os.Open(path)
		if err != nil {
			t.Fatal(err)
		}
		err = verifyNativeShell(f)
		f.Close()
		if (err == nil) != wantPass {
			t.Fatalf("PE acceptance=%v, wanted %v: %v", err == nil, wantPass, err)
		}
	}
	// Synthetic PE32+ headers; never execute fixtures or inherit test-host bitness.
	binary.LittleEndian.PutUint16(data[offset+4:], 0xaa64)
	check(true)
	binary.LittleEndian.PutUint16(data[offset+4:], 0x8664)
	check(false)
	binary.LittleEndian.PutUint16(data[offset+4:], 0xaa64)
	binary.LittleEndian.PutUint16(data[offset+22:], 0x2002)
	check(false)
	data[0] = 0
	check(false)
}
