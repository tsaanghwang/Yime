package main

import (
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"os"
	"path/filepath"
	"reflect"
	"strings"
	"testing"

	"github.com/tsaanghwang/Yime/go-backend/internal/symlinkfixture"
)

func TestLocalMaintenanceHealthDescriptorOptionalAndStrict(t *testing.T) {
	if value, err := decodeLocalMaintenanceHealthDescriptor(localDescriptorFixture(t)); err != nil || value != nil {
		t.Fatalf("historical descriptor acquired health requirements: %+v %v", value, err)
	}
	good := `{"maintenance_health":{"protocol":"yimecore-maintenance-health-v1","required_on_start":true}}`
	if value, err := decodeLocalMaintenanceHealthDescriptor([]byte(good)); err != nil || value == nil {
		t.Fatalf("current fixed declaration rejected: %v", err)
	}
	for name, raw := range map[string]string{
		"null":             `{"maintenance_health":null}`,
		"array":            `{"maintenance_health":[]}`,
		"singleton_array":  `{"maintenance_health":[{"protocol":"yimecore-maintenance-health-v1","required_on_start":true}]}`,
		"scalar":           `{"maintenance_health":true}`,
		"empty":            `{"maintenance_health":{}}`,
		"missing_protocol": `{"maintenance_health":{"required_on_start":true}}`,
		"missing_required": `{"maintenance_health":{"protocol":"yimecore-maintenance-health-v1"}}`,
		"false":            strings.Replace(good, "true", "false", 1),
		"null_required":    strings.Replace(good, "true", "null", 1),
		"string_required":  strings.Replace(good, "true", `"true"`, 1),
		"number_required":  strings.Replace(good, "true", "1", 1),
		"array_required":   strings.Replace(good, "true", "[true]", 1),
		"unknown_protocol": strings.Replace(good, "health-v1", "health-v2", 1),
		"null_protocol":    strings.Replace(good, `"yimecore-maintenance-health-v1"`, "null", 1),
		"array_protocol":   strings.Replace(good, `"yimecore-maintenance-health-v1"`, `["yimecore-maintenance-health-v1"]`, 1),
		"outer_case":       strings.Replace(good, "maintenance_health", "Maintenance_Health", 1),
		"inner_case":       strings.Replace(good, "required_on_start", "Required_On_Start", 1),
		"unknown_field":    strings.Replace(good, `"required_on_start":true`, `"required_on_start":true,"optional":true`, 1),
		"duplicate_inner":  strings.Replace(good, `"required_on_start":true`, `"required_on_start":false,"required_on_start":true`, 1),
		"duplicate_outer":  `{"maintenance_health":null,` + good[1:],
		"trailing":         good + `{}`,
	} {
		t.Run(name, func(t *testing.T) {
			if _, err := decodeLocalMaintenanceHealthDescriptor([]byte(raw)); err == nil {
				t.Fatal("invalid health declaration accepted")
			}
		})
	}
}

func localMaintenanceHealthFixture(t *testing.T) (string, map[string]manifestFile) {
	t.Helper()
	root := t.TempDir()
	entries := map[string]manifestFile{}
	for _, path := range requiredLocalMaintenanceHealthFiles {
		full := filepath.Join(root, filepath.FromSlash(path))
		if err := os.MkdirAll(filepath.Dir(full), 0700); err != nil {
			t.Fatal(err)
		}
		data := []byte("private nonexecuted health helper fixture: " + path)
		if err := os.WriteFile(full, data, 0600); err != nil {
			t.Fatal(err)
		}
		hash := sha256.Sum256(data)
		entries[strings.ToLower(path)] = manifestFile{Path: path, Bytes: int64(len(data)), SHA256: hex.EncodeToString(hash[:])}
	}
	var descriptor map[string]any
	if err := json.Unmarshal(localDescriptorFixture(t), &descriptor); err != nil {
		t.Fatal(err)
	}
	descriptor["package_contract"] = localInstallableContract
	descriptor["installable"] = true
	descriptor["maintenance_health"] = map[string]any{"protocol": localMaintenanceHealthProtocol, "required_on_start": true}
	data, err := json.Marshal(descriptor)
	if err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(root, "local-product.json"), data, 0600); err != nil {
		t.Fatal(err)
	}
	return root, entries
}

func TestLocalMaintenanceHealthRequiresEveryPackageOwnedHelper(t *testing.T) {
	root, entries := localMaintenanceHealthFixture(t)
	if err := validateLocalContract(root, entries, localInstallableContract); err != nil {
		t.Fatalf("self-contained health declaration rejected: %v", err)
	}
	for _, path := range requiredLocalMaintenanceHealthFiles {
		t.Run(path, func(t *testing.T) {
			for _, failure := range []string{"unlisted", "missing", "bytes", "hash", "case", "directory", "empty"} {
				t.Run(failure, func(t *testing.T) {
					root, entries := localMaintenanceHealthFixture(t)
					key := strings.ToLower(path)
					entry := entries[key]
					full := filepath.Join(root, filepath.FromSlash(path))
					switch failure {
					case "unlisted":
						delete(entries, key)
					case "missing":
						if err := os.Remove(full); err != nil {
							t.Fatal(err)
						}
					case "bytes":
						entry.Bytes++
						entries[key] = entry
					case "hash":
						entry.SHA256 = strings.Repeat("0", 64)
						entries[key] = entry
					case "case":
						entry.Path = strings.ToUpper(path)
						entries[key] = entry
					case "directory", "empty":
						if err := os.Remove(full); err != nil {
							t.Fatal(err)
						}
						if failure == "directory" {
							if err := os.Mkdir(full, 0700); err != nil {
								t.Fatal(err)
							}
						} else if err := os.WriteFile(full, nil, 0600); err != nil {
							t.Fatal(err)
						} else {
							emptyHash := sha256.Sum256(nil)
							entry.Bytes, entry.SHA256 = 0, hex.EncodeToString(emptyHash[:])
							entries[key] = entry
						}
					}
					if err := validateLocalContract(root, entries, localInstallableContract); err == nil {
						t.Fatal("incomplete or changed health helper accepted")
					}
				})
			}
		})
	}
}

func TestLocalMaintenanceHealthRefusesRuntimeBundleAndUndeclaredPayload(t *testing.T) {
	root, entries := localMaintenanceHealthFixture(t)
	if err := validateLocalContract(root, entries, localRuntimeContract); err == nil {
		t.Fatal("runtime-only bundle acquired installable maintenance capability")
	}
	data := strings.Replace(string(localDescriptorFixture(t)), localRuntimeContract, localInstallableContract, 1)
	data = strings.Replace(data, `"installable":false`, `"installable":true`, 1)
	if err := os.WriteFile(filepath.Join(root, "local-product.json"), []byte(data), 0600); err != nil {
		t.Fatal(err)
	}
	if err := validateLocalContract(root, entries, localInstallableContract); err == nil {
		t.Fatal("undeclared new helpers were accepted as the historical catalog")
	}
}

func TestLocalMaintenanceHealthRejectsIndirectHelper(t *testing.T) {
	root, entries := localMaintenanceHealthFixture(t)
	path := requiredLocalMaintenanceHealthFiles[3]
	full := filepath.Join(root, filepath.FromSlash(path))
	foreign := filepath.Join(t.TempDir(), "owned-symlink-target.cs")
	data, err := os.ReadFile(full)
	if err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(foreign, data, 0600); err != nil {
		t.Fatal(err)
	}
	if err := os.Remove(full); err != nil {
		t.Fatal(err)
	}
	symlinkfixture.Create(t, foreign, full)
	if err := validateLocalContract(root, entries, localInstallableContract); err == nil {
		t.Fatal("out-of-package helper was accepted")
	}
}

func TestLocalMaintenanceHealthCatalogMatchesCurrentDescriptor(t *testing.T) {
	data, err := os.ReadFile(filepath.Join("..", "..", "..", "tools", "yimecore", "local-product.json"))
	if err != nil {
		t.Fatal(err)
	}
	health, err := decodeLocalMaintenanceHealthDescriptor(data)
	if err != nil || health == nil {
		t.Fatalf("current builder declaration unavailable: %v", err)
	}
	var descriptor struct {
		Maintenance []struct{ Source, Path string } `json:"maintenance_assets"`
	}
	if err := json.Unmarshal(data, &descriptor); err != nil {
		t.Fatal(err)
	}
	want := map[string]string{
		"maintenance/local-product-runtime.ps1":           "tools/yimecore/local-product-runtime.ps1",
		"maintenance/native-maintenance-processes.psm1":   "tools/yimecore/native-maintenance-processes.psm1",
		"maintenance/native-maintenance-process-facts.cs": "tools/yimecore/native-maintenance-process-facts.cs",
		"dual-product/rime-pime-dp1u-native-facts.cs":     "tools/dual-product/rime-pime-dp1u-native-facts.cs",
		"maintenance/native-maintenance-health.psm1":      "tools/yimecore/native-maintenance-health.psm1",
		"maintenance/native-maintenance-health-client.cs": "tools/yimecore/native-maintenance-health-client.cs",
	}
	got := map[string]string{}
	for _, asset := range descriptor.Maintenance {
		if _, exists := want[asset.Path]; exists {
			if _, duplicate := got[asset.Path]; duplicate {
				t.Fatalf("duplicate health helper: %s", asset.Path)
			}
			got[asset.Path] = asset.Source
		}
	}
	if !reflect.DeepEqual(want, got) || len(requiredLocalMaintenanceHealthFiles) != 6 {
		t.Fatalf("health helper mapping differs: %v", got)
	}
	for _, path := range requiredLocalMaintenanceHealthFiles {
		if _, exists := got[path]; !exists {
			t.Fatalf("auditor's health helper is not packaged: %s", path)
		}
	}
}
