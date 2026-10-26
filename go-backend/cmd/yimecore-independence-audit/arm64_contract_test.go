package main

import (
	"encoding/json"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func arm64SpeechFixture(t *testing.T) *localSpeechFixture {
	t.Helper()
	f := newLocalSpeechFixture(t, "")
	for path, value := range f.entries {
		if strings.HasPrefix(path, "x64/") {
			delete(f.entries, path)
			value.Path = "arm64/" + strings.TrimPrefix(value.Path, "x64/")
			f.entries[strings.ToLower(value.Path)] = value
		}
	}
	editARM64Descriptor(t, f, func(d map[string]any) {
		d["package_contract"] = arm64InstallableContract
		d["scope"] = map[string]any{"computer_name": "HUASHUONOTEBOOK", "active_architectures": []string{"arm64", "x86"}, "target": "windows-arm64", "tsf64_architecture": "arm64x"}
	})
	return f
}

func editARM64Descriptor(t *testing.T, f *localSpeechFixture, edit func(map[string]any)) {
	t.Helper()
	data, err := os.ReadFile(filepath.Join(f.root, "local-product.json"))
	if err != nil {
		t.Fatal(err)
	}
	var d map[string]any
	if err := json.Unmarshal(data, &d); err != nil {
		t.Fatal(err)
	}
	edit(d)
	f.writeJSON(t, "local-product.json", d)
}

func TestARM64ProductContractAndLegacyIsolation(t *testing.T) {
	f := arm64SpeechFixture(t)
	if err := validateLocalContract(f.root, f.entries, arm64InstallableContract); err != nil {
		t.Fatal(err)
	}
	if err := validateLocalContract(f.root, f.entries, localInstallableContract); err == nil {
		t.Fatal("ARM64 descriptor entered the legacy x64 contract")
	}
	required, err := requiredFilesForContract(packageManifest{PackageContract: arm64InstallableContract, ToolVersion: "yimecore-arm64-builder-v1"})
	if err != nil {
		t.Fatal(err)
	}
	if len(required) != len(requiredLocalRuntimeFiles) {
		t.Fatal("standard resource inventory changed")
	}
	for _, path := range required {
		if strings.HasPrefix(path, "x64/") {
			t.Fatal("separate shared-view x64 payload admitted")
		}
		if _, ok := f.entries[strings.ToLower(path)]; !ok {
			t.Fatalf("missing required ARM64 member %s", path)
		}
	}
	if _, err := requiredFilesForContract(packageManifest{PackageContract: arm64InstallableContract, ToolVersion: "yimecore-local-builder-v1"}); err == nil {
		t.Fatal("legacy builder relabelled as ARM64")
	}
}

func TestARM64ProductRejectsIncompleteOrMixedContract(t *testing.T) {
	for _, scenario := range []string{"scope", "native", "target", "plain-arm64", "no-speech", "missing-speech-index", "x64-dll", "identity"} {
		t.Run(scenario, func(t *testing.T) {
			f := arm64SpeechFixture(t)
			switch scenario {
			case "missing-speech-index":
				delete(f.entries, "speech/indexes/full-stage5c.yidx")
			case "x64-dll":
				f.entries["x64/yimetextserviceexperiment.dll"] = manifestFile{Path: "x64/YimeTextServiceExperiment.dll"}
			default:
				editARM64Descriptor(t, f, func(d map[string]any) {
					s := d["scope"].(map[string]any)
					switch scenario {
					case "scope":
						s["computer_name"] = "MYCOMPUTER"
					case "native":
						s["active_architectures"] = []string{"x64", "x86"}
					case "target":
						s["target"] = "windows-amd64"
					case "plain-arm64":
						s["tsf64_architecture"] = "arm64"
					case "no-speech":
						delete(d, "speech")
					case "identity":
						d["identity"].(map[string]any)["clsid"] = "{41EC6C9B-E8D2-4E1E-9E7C-5CA3DAF0F66B}"
					}
				})
			}
			if err := validateLocalContract(f.root, f.entries, arm64InstallableContract); err == nil {
				t.Fatal("invalid/mixed platform contract admitted")
			}
		})
	}
}
