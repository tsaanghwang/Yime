package main

import (
	"crypto/sha256"
	"encoding/hex"
	"errors"
	"os"
	"path/filepath"
	"reflect"
	"strings"
	"testing"
)

func TestRimeCallerBindingAndStageParameters(t *testing.T) {
	valid := maintenancePlan{Product: "rime-pime", Target: "windows-arm64"}
	for _, tc := range []struct {
		name, product, target, action string
		elevated, admin               bool
		pid                           uint
		started                       uint64
		want, fail                    bool
	}{
		{"ordinary-parent", valid.Product, valid.Target, "Install", true, true, 12, 34, true, false},
		{"direct-admin", valid.Product, valid.Target, "Install", false, true, 0, 0, false, false},
		{"internal-flag-without-parent", valid.Product, valid.Target, "Install", true, true, 0, 0, false, false},
		{"no-elevation", valid.Product, valid.Target, "Install", false, true, 12, 34, false, true},
		{"no-admin-token", valid.Product, valid.Target, "Install", true, false, 12, 34, false, true},
		{"missing-time", valid.Product, valid.Target, "Install", true, true, 12, 0, false, true},
		{"missing-pid", valid.Product, valid.Target, "Install", true, true, 0, 34, false, true},
		{"uninstall", valid.Product, valid.Target, "Uninstall", true, true, 12, 34, false, true},
		{"check", valid.Product, valid.Target, "Check", true, true, 12, 34, false, true},
		{"18u", "yimecore-18u", valid.Target, "Install", true, true, 12, 34, false, true},
		{"legacy", valid.Product, "windows-amd64", "Install", true, true, 12, 34, false, true},
	} {
		t.Run(tc.name, func(t *testing.T) {
			got, err := rimeCallerBinding(maintenancePlan{Product: tc.product, Target: tc.target}, tc.action, tc.elevated, tc.admin, tc.pid, tc.started)
			if got != tc.want || (err != nil) != tc.fail {
				t.Fatalf("binding=%v err=%v", got, err)
			}
		})
	}
	for _, deferred := range []bool{false, true} {
		p := maintenanceParameters("Install", "same-sid", "protected stage", "entry-hash", "plan-hash", deferred)
		if p["Action"] != "Install" || p["InitiatingSid"] != "same-sid" || p["NativeMaintenanceRoot"] != "protected stage" || p["NativeMaintenanceSHA256"] != "entry-hash" || p["NativeMaintenancePlanSHA256"] != "plan-hash" || p["Silent"] != true {
			t.Fatalf("stage identity lost: %v", p)
		}
		if got, exists := p["NativeRimeValidationDeferred"]; exists != deferred || (deferred && got != true) {
			t.Fatalf("direct-admin/parent handoff mixed: %v", p)
		}
	}
}

func TestOrdinaryCallerIdentityRejectsMismatchedContext(t *testing.T) {
	actual := ordinaryCallerIdentity{started: 42, sid: "same-sid", image: filepath.Join("package", "YimeMaintenance.exe")}
	if err := validateOrdinaryCaller(actual, 42, actual.sid, strings.ToUpper(actual.image)); err != nil {
		t.Fatal(err)
	}
	for _, change := range []func(*ordinaryCallerIdentity){
		func(p *ordinaryCallerIdentity) { p.started++ },
		func(p *ordinaryCallerIdentity) { p.sid = "another-sid" },
		func(p *ordinaryCallerIdentity) { p.elevated = true },
		func(p *ordinaryCallerIdentity) { p.image = filepath.Join("another-package", "YimeMaintenance.exe") },
	} {
		bad := actual
		change(&bad)
		if err := validateOrdinaryCaller(bad, 42, actual.sid, actual.image); err == nil {
			t.Fatalf("accepted mismatched parent: %+v", bad)
		}
	}
	if err := validateOrdinaryCaller(actual, 0, actual.sid, actual.image); err == nil {
		t.Fatal("accepted missing creation time")
	}
}

func TestRimeInstalledValidationPrecedesRuntimeAndFailsClosed(t *testing.T) {
	for _, scenario := range []string{"success", "x86-failure", "arm64-failure", "probe-start-error", "missing-plan-probe", "missing-installed-probe", "tampered-probe", "tampered-other-payload", "tampered-installed-manifest", "runtime-start-error", "18u"} {
		t.Run(scenario, func(t *testing.T) {
			root := filepath.Join(t.TempDir(), "installed product with spaces")
			plan := maintenancePlan{Product: "rime-pime", Target: "windows-arm64", Files: make(map[string]fileRecord)}
			names := []string{"x86/PIMERegistrationStatus.exe", "arm64/PIMERegistrationStatus.exe", "PIMELauncher.exe", "data/owned.txt", ".setup/product-package.json"}
			for _, name := range names {
				path := filepath.Join(root, filepath.FromSlash(name))
				if err := os.MkdirAll(filepath.Dir(path), 0700); err != nil {
					t.Fatal(err)
				}
				data := []byte("inert fixture bytes: " + name)
				if err := os.WriteFile(path, data, 0600); err != nil {
					t.Fatal(err)
				}
				sum := sha256.Sum256(data)
				key := "payload/" + name
				if name == ".setup/product-package.json" {
					key = "product-package.json"
				}
				plan.Files[key] = fileRecord{Bytes: int64(len(data)), SHA256: hex.EncodeToString(sum[:])}
			}
			switch scenario {
			case "missing-plan-probe":
				delete(plan.Files, "payload/arm64/PIMERegistrationStatus.exe")
			case "missing-installed-probe":
				if err := os.Remove(filepath.Join(root, "arm64", "PIMERegistrationStatus.exe")); err != nil {
					t.Fatal(err)
				}
			case "tampered-probe", "tampered-other-payload", "tampered-installed-manifest":
				name := "arm64/PIMERegistrationStatus.exe"
				if scenario == "tampered-other-payload" {
					name = "data/owned.txt"
				}
				if scenario == "tampered-installed-manifest" {
					name = ".setup/product-package.json"
				}
				path := filepath.Join(root, filepath.FromSlash(name))
				data, err := os.ReadFile(path)
				if err != nil {
					t.Fatal(err)
				}
				data[0] ^= 1 // Same-size replacement must still be rejected.
				if err = os.WriteFile(path, data, 0600); err != nil {
					t.Fatal(err)
				}
			case "18u":
				plan.Product = "yimecore-18u"
			}
			var events []string
			verify := func() error {
				events = append(events, "verify")
				_, err := verifyInstalledRuntimePayload(plan, root, runtimeSpec{executable: "PIMELauncher.exe"}, func(rel string, row fileRecord) error {
					f, err := os.Open(filepath.Join(root, filepath.FromSlash(rel)))
					if err != nil {
						return err
					}
					defer f.Close()
					return verifyStream(f, row)
				})
				return err
			}
			probe := func(path string, arguments []string) error {
				rel, err := filepath.Rel(root, path)
				if err != nil {
					return err
				}
				arch := filepath.Dir(rel)
				if path != filepath.Join(root, arch, "PIMERegistrationStatus.exe") || !reflect.DeepEqual(arguments, []string{"verify-present"}) {
					t.Fatalf("unexpected command: %s %v", path, arguments)
				}
				events = append(events, arch)
				if scenario == arch+"-failure" || scenario == "probe-start-error" {
					return errors.New("injected probe failure")
				}
				return nil
			}
			launch := func() error {
				events = append(events, "launch")
				if scenario == "runtime-start-error" {
					return errors.New("injected launch failure")
				}
				return nil
			}
			err := completeInstalledStartup(plan, root, verify, probe, launch)
			want := []string{"verify"}
			switch scenario {
			case "success", "runtime-start-error":
				want = []string{"verify", "x86", "arm64", "launch"}
			case "x86-failure", "probe-start-error":
				want = []string{"verify", "x86"}
			case "arm64-failure":
				want = []string{"verify", "x86", "arm64"}
			case "missing-plan-probe":
				want = nil
			case "18u":
				want = []string{"verify", "launch"}
			}
			if !reflect.DeepEqual(events, want) || (err == nil) != (scenario == "success" || scenario == "18u") {
				t.Fatalf("events=%v want=%v err=%v", events, want, err)
			}
		})
	}
}
