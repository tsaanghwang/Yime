package main

import (
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func TestResolveSpeechOptionsAbsentCapabilityLeavesCoreOnly(t *testing.T) {
	root := t.TempDir()
	config := options{installRoot: filepath.Join(root, "package"), stateRoot: filepath.Join(root, "private-state")}
	if err := os.Mkdir(config.installRoot, 0700); err != nil {
		t.Fatal(err)
	}
	if err := resolveSpeechOptions(&config); err != nil {
		t.Fatal(err)
	}
	if config.speechManifest != "" || config.speechSHA256 != "" {
		t.Fatal("old package acquired a speech capability")
	}
	if _, err := os.Stat(config.stateRoot); !os.IsNotExist(err) {
		t.Fatal("capability discovery created state")
	}
	for _, arg := range brokerArguments(config) {
		if strings.HasPrefix(arg, "-speech-") {
			t.Fatal("core-only launch added a speech argument")
		}
	}
}

func TestResolveSpeechOptionsRejectsBadCapabilityBeforeState(t *testing.T) {
	for _, data := range []string{`{`, `{"schema_version":"unknown"}`, `{"schema_version":"yimecore-speech-capability-v1","product":{"path":"../other/product.json","sha256":"bad"},"default_enabled":false}`} {
		t.Run(data, func(t *testing.T) {
			root := t.TempDir()
			config := options{installRoot: filepath.Join(root, "package"), stateRoot: filepath.Join(root, "private-state")}
			if err := os.Mkdir(config.installRoot, 0700); err != nil {
				t.Fatal(err)
			}
			if err := os.WriteFile(filepath.Join(config.installRoot, "speech-capability.json"), []byte(data), 0600); err != nil {
				t.Fatal(err)
			}
			if err := resolveSpeechOptions(&config); err == nil {
				t.Fatal("bad capability accepted")
			}
			if _, err := os.Stat(config.stateRoot); !os.IsNotExist(err) {
				t.Fatal("rejected capability opened state")
			}
		})
	}
}

func TestBrokerArgumentsAddProductSpeechWithoutChangingLearningNamespace(t *testing.T) {
	config := options{installRoot: filepath.Join(t.TempDir(), "package"), stateRoot: filepath.Join(t.TempDir(), "state"), pipeName: defaultPipeName,
		speechManifest: "speech/product.json", speechSHA256: strings.Repeat("a", 64)}
	args := brokerArguments(config)
	values := map[string]string{}
	for i := 0; i+1 < len(args); i += 2 {
		values[args[i]] = args[i+1]
	}
	for flag, expected := range map[string]string{
		"-speech-product-root":     config.installRoot,
		"-speech-product-manifest": config.speechManifest,
		"-speech-product-sha256":   config.speechSHA256,
		"-speech-settings":         filepath.Join(config.stateRoot, "speech.json"),
		"-user-model-source-id":    modelSourceID + ":installed-v1",
		"-named-pipe":              defaultPipeName,
	} {
		if values[flag] != expected {
			t.Fatalf("%s not pinned to its normal product value", flag)
		}
	}
	for _, arg := range args {
		if strings.Contains(arg, "speech-experiment") || strings.Contains(arg, "speech-stage5c-isolated") || arg == "-trusted-client-id" {
			t.Fatal("runtime used a fixture-only launch contract")
		}
	}
}

func TestSpeechDamageDoesNotBlockExistingStopOrStatusResolution(t *testing.T) {
	root := t.TempDir()
	for _, relative := range []string{"bin/YimeBroker.exe", "indexes/full.yidx", "indexes/variable.yidx", "indexes/shorthand.yidx", "data/yime_pinyin_codes.tsv", "speech-capability.json"} {
		path := filepath.Join(root, filepath.FromSlash(relative))
		if err := os.MkdirAll(filepath.Dir(path), 0700); err != nil {
			t.Fatal(err)
		}
		if err := os.WriteFile(path, []byte("invalid speech fixture; ordinary files satisfy existing resolution"), 0600); err != nil {
			t.Fatal(err)
		}
	}
	config := options{installRoot: root, stateRoot: filepath.Join(root, "private-state"), pipeName: defaultPipeName, noToolbar: true}
	if _, err := resolveOptions(config); err == nil {
		t.Fatal("damaged speech capability allowed startup")
	}
	config.maintenanceQuery = true
	if _, err := resolveOptions(config); err != nil {
		t.Fatalf("speech damage blocked stop/status resolution: %v", err)
	}
	if _, err := os.Stat(config.stateRoot); !os.IsNotExist(err) {
		t.Fatal("read-only resolution created state")
	}
}
