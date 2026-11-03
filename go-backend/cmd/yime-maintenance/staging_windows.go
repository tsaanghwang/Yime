//go:build windows

package main

import (
	"errors"
	"fmt"
	"io/fs"
	"os"
	"os/exec"
	"path/filepath"
	"sort"
	"strings"
	"syscall"
	"unsafe"
)

func renameDirectoryNoReplace(source, destination string) error {
	src, err := syscall.UTF16PtrFromString(source)
	if err != nil {
		return err
	}
	dst, err := syscall.UTF16PtrFromString(destination)
	if err != nil {
		return err
	}
	ok, _, err := kernel.NewProc("MoveFileExW").Call(uintptr(unsafe.Pointer(src)), uintptr(unsafe.Pointer(dst)), 0)
	if ok == 0 {
		return err
	}
	return nil
}

// Keep every byte and its ancestor directories locked through shell execution.
// Unlike ordinary ancestors, every stage directory forbids adding children.
func holdVerifiedStage(stage string, plan maintenancePlan, selfHash string) (held *heldFiles, err error) {
	held = new(heldFiles)
	locks := held
	defer func() {
		if err != nil {
			locks.close()
			held = nil
		}
	}()
	expected := make(map[string]bool, len(plan.Files)+2)
	names := make([]string, 0, len(plan.Files)+2)
	for name := range plan.Files {
		names = append(names, name)
	}
	names = append(names, "maintenance-plan.json", "YimeMaintenance.exe")
	sort.Strings(names)
	for _, name := range names {
		expected[name] = true
		path := filepath.Join(stage, filepath.FromSlash(name))
		if err = held.parentsWithin(path, true, stage); err != nil {
			return nil, err
		}
		var f *os.File
		f, err = openLocked(path, false)
		if err != nil {
			return nil, err
		}
		held.add(f)
		if err = checkACL(f, true); err != nil {
			return nil, err
		}
		if row, ok := plan.Files[name]; ok {
			if err = verifyStream(f, row); err != nil {
				return nil, fmt.Errorf("stage %s: %w", name, err)
			}
		} else {
			var digest string
			digest, err = fileDigest(f)
			if err != nil {
				return nil, err
			}
			wanted := expectedPlanSHA
			if name == "YimeMaintenance.exe" {
				wanted = selfHash
			}
			if digest != wanted {
				return nil, errors.New("protected entry or plan changed")
			}
		}
		if name == shellMember {
			if err = verifyNativeShell(f); err != nil {
				return nil, err
			}
		}
	}
	// A complete official shell tree is bound by inventory, including its modules
	// and runtime configuration. Unknown files must not become executable input.
	err = filepath.WalkDir(stage, func(path string, entry fs.DirEntry, walkErr error) error {
		if walkErr != nil {
			return walkErr
		}
		if entry.Type()&os.ModeSymlink != 0 {
			return errors.New("linked stage entry")
		}
		if entry.IsDir() {
			f, e := openLocked(path, true)
			if e != nil {
				return e
			}
			held.add(f)
			return checkACL(f, true)
		}
		rel, e := filepath.Rel(stage, path)
		if e != nil {
			return e
		}
		if !expected[filepath.ToSlash(rel)] {
			return fmt.Errorf("unbound stage member: %s", rel)
		}
		return nil
	})
	if err != nil {
		return nil, err
	}
	return held, nil
}

// Only the original unelevated caller reaches this function after successful
// elevation. The exact installed payload is checked before starting its runtime.
func startInstalledRuntime(plan maintenancePlan) error {
	_, admin, err := nativeIdentity()
	if err != nil {
		return err
	}
	if admin {
		return errors.New("never start a product runtime with an elevated token")
	}
	spec, err := productRuntime(plan.Product)
	if err != nil {
		return err
	}
	programFiles, err := knownFolder(programFilesID)
	if err != nil {
		return err
	}
	root := filepath.Join(programFiles, spec.directory)
	held := new(heldFiles)
	defer held.close()
	var args []string
	return completeInstalledStartup(plan, root, func() error {
		var verifyErr error
		args, verifyErr = verifyInstalledRuntime(plan, root, spec, held)
		return verifyErr
	}, func(path string, arguments []string) error {
		fmt.Printf("Verify installed Rime registration as original ordinary caller: %s %s\n", path, strings.Join(arguments, " "))
		cmd := exec.Command(path, arguments...)
		cmd.Dir = root
		cmd.Stdout, cmd.Stderr = os.Stdout, os.Stderr
		cmd.SysProcAttr = &syscall.SysProcAttr{HideWindow: true}
		return cmd.Run()
	}, func() error {
		cmd := exec.Command(filepath.Join(root, filepath.FromSlash(spec.executable)), args...)
		cmd.Dir = root
		cmd.SysProcAttr = &syscall.SysProcAttr{HideWindow: true}
		if err := cmd.Start(); err != nil {
			return fmt.Errorf("installed but runtime start failed: %w", err)
		}
		pid := cmd.Process.Pid
		if err := cmd.Process.Release(); err != nil {
			return err
		}
		fmt.Printf("Started installed %s runtime as the original non-administrator account; pid=%d. Input acceptance is separate.\n", plan.Product, pid)
		return nil
	})
}

func verifyInstalledRuntime(plan maintenancePlan, root string, spec runtimeSpec, held *heldFiles) ([]string, error) {
	return verifyInstalledRuntimePayload(plan, root, spec, func(rel string, row fileRecord) error {
		path := filepath.Join(root, filepath.FromSlash(rel))
		if err := held.parentsWithin(path, true, root); err != nil {
			return err
		}
		f, e := openLocked(path, false)
		if e != nil {
			return e
		}
		held.add(f)
		if err := checkACL(f, true); err != nil {
			return err
		}
		return verifyStream(f, row)
	})
}
