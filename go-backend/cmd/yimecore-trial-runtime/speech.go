package main

import (
	"fmt"
	"path/filepath"

	"github.com/tsaanghwang/Yime/go-backend/input_methods/yime/speechruntime"
)

// Discovery is read-only and precedes runtime state/log creation. An old package
// has no capability and continues along its original core-only launch path.
func resolveSpeechOptions(config *options) error {
	config.speechManifest, config.speechSHA256 = "", ""
	capability, err := speechruntime.LoadCapability(config.installRoot)
	if err != nil {
		return fmt.Errorf("load speech capability: %w", err)
	}
	if capability == nil {
		return nil
	}
	product, err := speechruntime.OpenProduct(config.installRoot, capability.Product.Path, capability.Product.SHA256)
	if err != nil {
		return fmt.Errorf("validate speech product: %w", err)
	}
	defer product.Close()
	settings, err := speechruntime.LoadSettings(filepath.Join(config.stateRoot, "speech.json"))
	if err != nil {
		return fmt.Errorf("load speech settings: %w", err)
	}
	if settings.Enabled {
		if err := product.ValidateIndexes(trialIndexRoot(*config), trialDataDir(*config)); err != nil {
			return fmt.Errorf("enabled speech does not match the current index/layout generation: %w", err)
		}
	}
	config.speechManifest, config.speechSHA256 = capability.Product.Path, capability.Product.SHA256
	return nil
}
