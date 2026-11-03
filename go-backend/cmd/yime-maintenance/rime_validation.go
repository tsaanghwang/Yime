package main

import (
	"errors"
	"fmt"
	"path/filepath"
	"strings"
)

func maintenanceParameters(action, sid, stage, selfHash, planHash string, deferRimeValidation bool) map[string]any {
	parameters := map[string]any{"Action": action, "Silent": true, "InitiatingSid": sid, "NativeMaintenanceRoot": stage, "NativeMaintenanceSHA256": selfHash, "NativeMaintenancePlanSHA256": planHash}
	if deferRimeValidation {
		parameters["NativeRimeValidationDeferred"] = true
	}
	return parameters
}

func rimeCallerBinding(plan maintenancePlan, action string, elevated, admin bool, pid uint, started uint64) (bool, error) {
	if pid == 0 && started == 0 {
		return false, nil // Direct administrator entry retains its original checks.
	}
	if !elevated || !admin || pid == 0 || started == 0 || action != "Install" ||
		plan.Product != "rime-pime" || plan.Target != "windows-arm64" {
		return false, errors.New("ordinary caller binding requires elevated native ARM64 Rime installation")
	}
	return true, nil
}

// The ordinary caller retains the installed-file locks through both probes and
// runtime creation. No polling or reduced registration predicate is used here.
func completeInstalledStartup(plan maintenancePlan, root string, verify func() error, probe func(string, []string) error, launch func() error) error {
	var probes []string
	if plan.Product == "rime-pime" {
		if plan.Target != "windows-arm64" {
			return errors.New("Rime user validation requires the native ARM64 contract")
		}
		probes = []string{"x86/PIMERegistrationStatus.exe", "arm64/PIMERegistrationStatus.exe"}
		for _, rel := range probes {
			if _, ok := plan.Files["payload/"+rel]; !ok {
				return fmt.Errorf("required installed registration probe is not bound: %s", rel)
			}
		}
	}
	if err := verify(); err != nil {
		return err
	}
	for _, rel := range probes {
		if err := probe(filepath.Join(root, filepath.FromSlash(rel)), []string{"verify-present"}); err != nil {
			return fmt.Errorf("installed Rime user registration validation failed (%s): %w", rel, err)
		}
	}
	return launch()
}

// The platform callback locks and validates each file before returning. Keeping
// inventory selection here also exercises the real startup inventory in tests.
func verifyInstalledRuntimePayload(plan maintenancePlan, root string, spec runtimeSpec, verifyMember func(string, fileRecord) error) ([]string, error) {
	var manifestHash string
	runtimePresent := false
	for name, row := range plan.Files {
		if !strings.HasPrefix(name, "payload/") {
			continue
		}
		rel := strings.TrimPrefix(name, "payload/")
		if err := verifyMember(rel, row); err != nil {
			return nil, fmt.Errorf("installed %s: %w", rel, err)
		}
		if rel == spec.executable {
			runtimePresent = true
		}
		if rel == spec.manifest {
			manifestHash = row.SHA256
		}
	}
	if !runtimePresent {
		return nil, errors.New("installed runtime is absent from the bound payload")
	}
	// This binds the installed maintenance identity to the selected package.
	if err := verifyMember(".setup/product-package.json", plan.Files["product-package.json"]); err != nil {
		return nil, err
	}
	return runtimeArguments(spec, root, manifestHash)
}

type ordinaryCallerIdentity struct {
	started    uint64
	sid, image string
	elevated   bool
}

func sameWindowsPath(left, right string) bool {
	return strings.EqualFold(filepath.Clean(left), filepath.Clean(right))
}

func validateOrdinaryCaller(actual ordinaryCallerIdentity, started uint64, sid, image string) error {
	if started == 0 || actual.started != started || actual.sid != sid || actual.elevated ||
		!sameWindowsPath(actual.image, image) {
		return errors.New("installation caller identity differs from the original ordinary helper")
	}
	return nil
}
