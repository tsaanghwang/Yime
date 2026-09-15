//go:build windows

package yimebroker

import (
	"encoding/json"
	"os"
	"path/filepath"
	"syscall"
	"testing"
	"time"
)

func TestIndexControlStatusPreservesOldFileWhileReaderBlocksReplacement(t *testing.T) {
	for _, release := range []bool{true, false} {
		t.Run(map[bool]string{true: "reader-releases", false: "reader-stays"}[release], func(t *testing.T) {
			path := filepath.Join(t.TempDir(), "status.json")
			if err := writeIndexControlStatus(path, IndexControlStatus{RequestID: "old"}); err != nil {
				t.Fatal(err)
			}
			name, err := syscall.UTF16PtrFromString(path)
			if err != nil {
				t.Fatal(err)
			}
			handle, err := syscall.CreateFile(name, syscall.GENERIC_READ, syscall.FILE_SHARE_READ,
				nil, syscall.OPEN_EXISTING, 0, 0)
			if err != nil {
				t.Fatal(err)
			}
			defer func() {
				if handle != syscall.InvalidHandle {
					syscall.CloseHandle(handle)
				}
			}()
			done := make(chan error, 1)
			go func() { done <- writeIndexControlStatus(path, IndexControlStatus{RequestID: "new"}) }()
			select {
			case err := <-done:
				t.Fatalf("replacement returned while reader held lock: %v", err)
			case <-time.After(40 * time.Millisecond):
			}
			readID := func() string {
				data, err := os.ReadFile(path)
				if err != nil {
					t.Fatal(err)
				}
				var status IndexControlStatus
				if err := json.Unmarshal(data, &status); err != nil {
					t.Fatal(err)
				}
				return status.RequestID
			}
			if got := readID(); got != "old" {
				t.Fatalf("old status lost: %s", got)
			}
			if release {
				if err := syscall.CloseHandle(handle); err != nil {
					t.Fatal(err)
				}
				handle = syscall.InvalidHandle
			}
			select {
			case err := <-done:
				if release && err != nil {
					t.Fatal(err)
				}
				if !release && err == nil {
					t.Fatal("permanent lock accepted")
				}
			case <-time.After(2 * time.Second):
				t.Fatal("replacement retry exceeded bound")
			}
			want := "old"
			if release {
				want = "new"
			}
			if got := readID(); got != want {
				t.Fatalf("status=%s want=%s", got, want)
			}
		})
	}
}
