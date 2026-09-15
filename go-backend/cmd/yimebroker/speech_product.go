package main

import (
	"errors"
	"fmt"
	"path/filepath"
	"strings"

	"github.com/tsaanghwang/Yime/go-backend/input_methods/yime/candidateannotation"
	"github.com/tsaanghwang/Yime/go-backend/input_methods/yime/candidatefilter"
	"github.com/tsaanghwang/Yime/go-backend/input_methods/yime/engineapi"
	"github.com/tsaanghwang/Yime/go-backend/input_methods/yime/speechruntime"
	"github.com/tsaanghwang/Yime/go-backend/input_methods/yime/yimecore"
)

var speechProductFlags = []string{"speech-product-root", "speech-product-manifest", "speech-product-sha256", "speech-settings"}

func speechProductRequested(visited []string) bool {
	for _, name := range visited {
		for _, required := range speechProductFlags {
			if name == required {
				return true
			}
		}
	}
	return false
}

func validateSpeechProductFlags(visited []string, indexRoot, root, manifest, hash, settings string) error {
	seen := map[string]bool{}
	for _, name := range visited {
		seen[name] = true
		if strings.HasPrefix(name, "speech-experiment-") {
			return errors.New("product and experiment speech entries cannot be combined")
		}
	}
	for _, name := range speechProductFlags {
		if !seen[name] {
			return errors.New("complete explicit product speech flags required")
		}
	}
	if indexRoot == "" || !filepath.IsAbs(root) || manifest != speechruntime.ProductManifestPath || len(hash) != 64 || !filepath.IsAbs(settings) || filepath.Base(settings) != "speech.json" {
		return errors.New("product speech requires normal multi-mode and pinned capability/settings paths")
	}
	return nil
}

type brokerSpeechProduct struct {
	product             *speechruntime.Product
	settingsPath        string
	dataDir             string
	annotationLayoutSHA string
}

func openBrokerSpeechProduct(config multiModeConfig) (*brokerSpeechProduct, error) {
	if config.speechProductRoot == "" && config.speechProductManifest == "" && config.speechProductSHA == "" && config.speechSettings == "" {
		return nil, nil
	}
	if err := validateSpeechProductFlags(speechProductFlags, config.indexRoot, config.speechProductRoot, config.speechProductManifest, config.speechProductSHA, config.speechSettings); err != nil {
		return nil, err
	}
	if config.userModelSourceID == speechruntime.ModelNamespace {
		return nil, errors.New("experiment learning namespace forbidden in product speech")
	}
	capability, err := speechruntime.LoadCapability(config.speechProductRoot)
	if err != nil {
		return nil, err
	}
	if capability == nil || capability.Product.Path != config.speechProductManifest || capability.Product.SHA256 != config.speechProductSHA {
		return nil, errors.New("speech flags do not match owning product capability")
	}
	settings, err := speechruntime.LoadSettings(config.speechSettings)
	if err != nil {
		return nil, err
	}
	product, err := speechruntime.OpenProduct(config.speechProductRoot, capability.Product.Path, capability.Product.SHA256)
	if err != nil {
		return nil, err
	}
	result := &brokerSpeechProduct{product: product, settingsPath: config.speechSettings, dataDir: config.annotationDataDir}
	if config.annotationDataDir != "" {
		result.annotationLayoutSHA, err = speechruntime.HashFile(filepath.Join(config.annotationDataDir, "yime_yinyuan_layout.json"))
		if err != nil {
			_ = result.Close()
			return nil, err
		}
	}
	if settings.Enabled {
		if err = product.ValidateIndexes(config.indexRoot, config.annotationDataDir); err != nil {
			_ = result.Close()
			return nil, err
		}
	}
	return result, nil
}

func (p *brokerSpeechProduct) Close() error {
	if p == nil {
		return nil
	}
	return p.product.Close()
}

// Resolve the pinned record bytes before durable state opens. The mapping is
// intentionally independent of enabled: disabling removes static lookup paths,
// not canonical annotation evidence for retained learned aliases.
func (p *brokerSpeechProduct) BindAnnotations(resolvers map[string]*candidateannotation.Resolver) error {
	if p == nil {
		return nil
	}
	admitted, err := candidateannotation.DecodeAdmittedRecords(p.product.AdmittedRecords())
	if err != nil {
		return err
	}
	if admitted.InputSHA256["layout"] != p.product.LayoutSHA256() {
		return errors.New("admitted annotation records do not match product layout receipt")
	}
	for _, mode := range []string{"full", "variable", "shorthand"} {
		resolver := resolvers[mode]
		if resolver == nil {
			return errors.New("product speech requires all three annotation resolvers")
		}
		resolvers[mode], err = resolver.WithAdmittedRecords(admitted, p.annotationLayoutSHA == p.product.LayoutSHA256())
		if err != nil {
			return err
		}
	}
	return nil
}

// Each new engine/session reads one explicit settings snapshot. Existing
// engines keep their own BundleIndex and are never silently changed mid-input.
func (p *brokerSpeechProduct) Modules(mode string, core *yimecore.FileIndex) ([]yimecore.BundleModule, error) {
	if p == nil {
		return nil, nil
	}
	settings, err := speechruntime.LoadSettings(p.settingsPath)
	if err != nil {
		return nil, err
	}
	if !settings.Enabled {
		return nil, nil
	}
	if p.annotationLayoutSHA != p.product.LayoutSHA256() {
		return nil, errors.New("loaded annotations do not match admitted speech layout")
	}
	if err = p.product.ValidateLayout(p.dataDir); err != nil {
		return nil, err
	}
	return p.product.Modules(mode, core)
}

// The ordinary multi-mode builder composes professional and speech modules,
// user lexicon, existing learning, annotations and blocklist in the same order.
func buildMultiModeEngine(config multiModeConfig, mode string, index *yimecore.FileIndex, modules []yimecore.BundleModule, model *yimecore.UserModel, resolver *candidateannotation.Resolver) (engineapi.Engine, error) {
	var engine engineapi.Engine
	var err error
	if len(modules) > 0 {
		bundle, bundleErr := yimecore.NewBundleIndex(index, modules)
		if bundleErr != nil {
			return nil, bundleErr
		}
		if config.userLexiconDir != "" {
			engine, err = yimecore.NewBundleEngineWithUserLexicon(bundle, 9, filepath.Join(config.userLexiconDir, "custom_phrase_"+mode+".txt"), model)
		} else if model != nil {
			engine, err = yimecore.NewBundleEngineWithUserModel(bundle, 9, model)
		} else {
			engine, err = yimecore.NewBundleEngine(bundle, 9)
		}
	} else if config.userLexiconDir != "" {
		engine, err = yimecore.NewFileEngineWithUserLexicon(index, 9, filepath.Join(config.userLexiconDir, "custom_phrase_"+mode+".txt"), model)
	} else if model != nil {
		engine, err = yimecore.NewFileEngineWithUserModel(index, 9, model)
	} else {
		engine, err = yimecore.NewFileEngine(index, 9)
	}
	if err != nil {
		return engine, err
	}
	if resolver != nil {
		engine, err = candidateannotation.Wrap(engine, resolver)
		if err != nil {
			return nil, err
		}
	}
	if config.userBlocklist != "" {
		engine, err = candidatefilter.Wrap(engine, config.userBlocklist)
	}
	if err != nil {
		return nil, fmt.Errorf("normal product engine decoration: %w", err)
	}
	return engine, nil
}
