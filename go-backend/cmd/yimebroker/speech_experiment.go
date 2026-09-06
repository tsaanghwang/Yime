package main

import (
	"context"
	"errors"
	"os"

	"github.com/tsaanghwang/Yime/go-backend/input_methods/yime/engineapi"
	"github.com/tsaanghwang/Yime/go-backend/input_methods/yime/speechruntime"
	"github.com/tsaanghwang/Yime/go-backend/input_methods/yime/yimebroker"
	"github.com/tsaanghwang/Yime/go-backend/input_methods/yime/yimecore"
)

// Only validation/staging before durable state opens can return this outcome.
var errSpeechAdmissionRejected = errors.New("isolated speech admission rejected")

const speechAdmissionRejectedExitCode = 42

func validateSpeechExperimentFlags(visited []string, root, manifest, hash, client string) error {
	if root == "" || manifest == "" || len(hash) != 64 || client != "speech-isolated-fixture" {
		return errors.New("speech experiment requires an explicit root, manifest, SHA-256 and fixture transport identity")
	}
	allowed := map[string]bool{"speech-experiment-root": true, "speech-experiment-manifest": true, "speech-experiment-sha256": true, "trusted-client-id": true}
	for _, name := range visited {
		if !allowed[name] {
			return errors.New("speech experiment cannot mix with installed, named-pipe, index-control, user-data or other Broker flags")
		}
	}
	return nil
}

func speechExperimentRequested(visited []string) bool {
	for _, name := range visited {
		if name == "speech-experiment-root" || name == "speech-experiment-manifest" || name == "speech-experiment-sha256" {
			return true
		}
	}
	return false
}

func runSpeechExperiment(root, manifestPath, hash, client string) (resultErr error) {
	manifest, err := speechruntime.Load(root, manifestPath, hash)
	if err != nil {
		return errors.Join(errSpeechAdmissionRejected, err)
	}
	// Stage every immutable core/module index before opening any durable state.
	var model *yimecore.UserModel
	manager, err := yimebroker.OpenBundleGenerationManager(manifest.EffectiveGeneration(),
		func(_ string, bundle *yimecore.BundleIndex) (engineapi.Engine, error) {
			if model == nil {
				return yimecore.NewBundleEngine(bundle, 9)
			}
			return yimecore.NewBundleEngineWithUserModel(bundle, 9, model)
		}, nil)
	if err != nil {
		return errors.Join(errSpeechAdmissionRejected, err)
	}
	defer func() { resultErr = errors.Join(resultErr, manager.Close()) }()
	state, err := speechruntime.Child(root, "state")
	if err != nil {
		return err
	}
	if err := os.MkdirAll(state, 0700); err != nil {
		return err
	}
	snapshot, err := speechruntime.Child(root, "state/model.json")
	if err != nil {
		return err
	}
	journal, err := speechruntime.Child(root, "state/model.journal")
	if err != nil {
		return err
	}
	durable, err := yimebroker.OpenDurableUserModel(yimebroker.DurableUserModelConfig{
		SnapshotPath: snapshot, JournalPath: journal, SourceID: speechruntime.ModelNamespace, CheckpointEvery: 256,
	})
	if err != nil {
		return err
	}
	defer func() { resultErr = errors.Join(resultErr, durable.Close()) }()
	model = durable.Model()
	dispatcher, err := yimebroker.NewModeDispatcher("variable", manager.NewEngine, yimebroker.Config{})
	if err != nil {
		return err
	}
	// The caller owns this anonymous-pipe child. EOF releases only its sessions
	// and a clean return checkpoints this trial's store. No live TIP is involved.
	return yimebroker.ServeLines(context.Background(), os.Stdin, os.Stdout, dispatcher, yimebroker.TrustedClient{ID: client})
}
