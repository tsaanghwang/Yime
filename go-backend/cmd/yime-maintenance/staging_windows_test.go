//go:build windows

package main

import (
	"encoding/binary"
	"os"
	"path/filepath"
	"testing"
)

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
