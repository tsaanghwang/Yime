package main

import (
	"errors"
	"os"
	"path/filepath"
	"reflect"
	"strings"
	"testing"
)

func TestInterruptedStagingCanRetrySamePlan(t *testing.T) {
	cache := t.TempDir()
	id := strings.Repeat("a", 64)
	create := func(p string) error { return os.Mkdir(p, 0700) }
	verify := func(p string) error {
		b, err := os.ReadFile(filepath.Join(p, "complete"))
		if err != nil {
			return err
		}
		if string(b) != "complete bytes" {
			return errors.New("wrong staged bytes")
		}
		return nil
	}
	fill := func(p string) error {
		return os.WriteFile(filepath.Join(p, "complete"), []byte("complete bytes"), 0600)
	}
	if _, err := publishStage(cache, id, create, func(p string) error {
		if err := os.WriteFile(filepath.Join(p, "partial"), []byte("partial"), 0600); err != nil {
			return err
		}
		return errors.New("simulated interrupted copy")
	}, verify, os.Rename); err == nil {
		t.Fatal("accepted interrupted stage")
	}
	if _, err := os.Stat(filepath.Join(cache, id)); !os.IsNotExist(err) {
		t.Fatal("partial final cache was published")
	}
	final, err := publishStage(cache, id, create, fill, verify, os.Rename)
	if err != nil {
		t.Fatal(err)
	}
	if err := verify(final); err != nil {
		t.Fatal(err)
	}
	kept, err := filepath.Glob(filepath.Join(cache, id+".staging-*"))
	if err != nil || len(kept) != 1 {
		t.Fatalf("failed evidence lost: %v %v", kept, err)
	}
	if _, err = os.Stat(filepath.Join(kept[0], "partial")); err != nil {
		t.Fatal(err)
	}
	called := false
	again, err := publishStage(cache, id, create, func(string) error { called = true; return nil }, verify, os.Rename)
	if err != nil || again != final || called {
		t.Fatalf("repeat replaced published cache: %s %v", again, err)
	}
}

func TestUnverifiedStageNeverPublished(t *testing.T) {
	cache := t.TempDir()
	id := strings.Repeat("b", 64)
	_, err := publishStage(cache, id, func(p string) error { return os.Mkdir(p, 0700) },
		func(string) error { return nil }, func(string) error { return errors.New("bad hash or ACL") },
		func(string, string) error { t.Fatal("unverified bytes reached publication"); return nil })
	if err == nil {
		t.Fatal("accepted invalid stage")
	}
	if _, err := os.Stat(filepath.Join(cache, id)); !os.IsNotExist(err) {
		t.Fatal("invalid final cache exists")
	}
}

func TestProtectedContentAndOrdinaryAncestorACLPolicy(t *testing.T) {
	if mutatingAccessMask(false)&6 != 0 {
		t.Fatal("ordinary ancestor cannot add unrelated siblings")
	}
	if mutatingAccessMask(true)&6 != 6 {
		t.Fatal("runtime/stage directory allows unbound child creation")
	}
	for _, content := range []bool{false, true} {
		if mutatingAccessMask(content)&0x40 == 0 {
			t.Fatal("ancestor permits deleting protected child")
		}
	}
	root := filepath.Join(t.TempDir(), "stage")
	if !insideDirectory(filepath.Join(root, "maintenance", "powershell"), root) || !insideDirectory(root, root) || insideDirectory(root+"-peer", root) {
		t.Fatal("directory boundary confused stage with sibling")
	}
}

func TestRuntimeLaunchArgumentsStayProductSpecific(t *testing.T) {
	spec, err := productRuntime("yimecore-18u")
	if err != nil {
		t.Fatal(err)
	}
	if _, err = runtimeArguments(spec, "root", ""); err == nil {
		t.Fatal("18u accepted unchecked manifest")
	}
	hash := strings.Repeat("c", 64)
	args, err := runtimeArguments(spec, "root with spaces", hash)
	want := []string{"--installed-18u-run", "--install-root", "root with spaces", "--manifest-sha256", hash}
	if err != nil || !reflect.DeepEqual(args, want) {
		t.Fatalf("wrong 18u args: %v %v", args, err)
	}
	rime, err := productRuntime("rime-pime")
	if err != nil {
		t.Fatal(err)
	}
	args, err = runtimeArguments(rime, "root", "")
	if err != nil || len(args) != 0 || rime.executable != "PIMELauncher.exe" {
		t.Fatal("Rime runtime launch mixed product arguments")
	}
	if _, err = productRuntime("yimecore"); err == nil {
		t.Fatal("standard product entered unrelated native maintenance lane")
	}
}
