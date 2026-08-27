// Command yimebroker is the standalone YimeCore trial Broker. It is not wired
// into PIME, the production Rime path, or default startup registration.
package main

import (
	"bufio"
	"context"
	"flag"
	"fmt"
	"os"
	"os/signal"
	"path/filepath"
	"time"

	"github.com/tsaanghwang/Yime/go-backend/input_methods/yime/candidateannotation"
	"github.com/tsaanghwang/Yime/go-backend/input_methods/yime/candidatefilter"
	"github.com/tsaanghwang/Yime/go-backend/input_methods/yime/engineapi"
	"github.com/tsaanghwang/Yime/go-backend/input_methods/yime/learningconfig"
	"github.com/tsaanghwang/Yime/go-backend/input_methods/yime/professionallexicon"
	"github.com/tsaanghwang/Yime/go-backend/input_methods/yime/yimebroker"
	"github.com/tsaanghwang/Yime/go-backend/input_methods/yime/yimecore"
)

func main() {
	indexPath := flag.String("index", "", "validated YimeCore index")
	mode := flag.String("mode", "", "full, variable or shorthand")
	indexRoot := flag.String("index-root", "", "directory containing full.yidx, variable.yidx and shorthand.yidx")
	defaultMode := flag.String("default-mode", "variable", "default mode for multi-index session opens")
	trustedClientID := flag.String("trusted-client-id", "", "identity bound by the launching transport adapter")
	namedPipe := flag.String("named-pipe", "", "E6-A local Windows named pipe path")
	pipeMaxConnections := flag.Int("pipe-max-connections", 64, "maximum concurrent named pipe connections")
	pipeMaxConnectionsPerClient := flag.Int("pipe-max-connections-per-client", 8, "maximum concurrent named pipe connections per authenticated process")
	userSnapshot := flag.String("user-model-snapshot", "", "optional durable user model snapshot")
	userJournal := flag.String("user-model-journal", "", "optional durable write-ahead journal")
	userModelSourceID := flag.String("user-model-source-id", "", "stable user-model namespace across compatible index generations")
	checkpointEvery := flag.Int("user-model-checkpoint-every", 256, "durable mutations between background snapshots")
	compactEvery := flag.Int("user-model-compact-every", 4096, "durable mutations between atomic journal compactions")
	rollbackSnapshot := flag.String("user-model-rollback-snapshot", "", "optional E5-F-compatible v1 rollback snapshot")
	indexVersion := flag.String("index-version", "", "initial managed index version")
	indexSHA256 := flag.String("index-sha256", "", "initial managed index file SHA-256")
	indexControlManifest := flag.String("index-control-manifest", "", "optional watched index control manifest")
	indexControlStatus := flag.String("index-control-status", "", "status file for watched index control")
	annotationDataDir := flag.String("annotation-data-dir", "", "optional reviewed runtime data for candidate encoding annotations")
	userLexiconDir := flag.String("user-lexicon-dir", "", "optional trial-private generated user lexicon directory")
	userBlocklist := flag.String("user-blocklist", "", "optional trial-private candidate blocklist")
	learningConfig := flag.String("learning-config", "", "optional trial-private learning configuration")
	professionalRoot := flag.String("professional-root", "", "optional installed professional lexicon catalog root")
	professionalState := flag.String("professional-state", "", "optional trial-private professional lexicon selection")
	exitBeforeRequest := flag.Int("experiment-exit-before-request", 0, "E5-B fault injection only")
	hangBeforeRequest := flag.Int("experiment-hang-before-request", 0, "E5-B fault injection only")
	exitAfterRequest := flag.Int("experiment-exit-after-request", 0, "E5-F fault injection after durable handling but before response")
	exitCompactionStage := flag.String("experiment-exit-compaction-stage", "", "E5-G fault injection at a named compaction stage")
	flag.Parse()
	if *indexRoot != "" {
		if *indexPath != "" || *mode != "" {
			fail(fmt.Errorf("index-root cannot be combined with index or mode"))
		}
		if *indexSHA256 != "" {
			fail(fmt.Errorf("multi-index mode derives one verified SHA-256 per mode; index-sha256 is single-index only"))
		}
		if *exitBeforeRequest != 0 || *hangBeforeRequest != 0 || *exitAfterRequest != 0 || *exitCompactionStage != "" {
			fail(fmt.Errorf("single-process fault injection is not available in multi-index trial mode"))
		}
		runMultiMode(multiModeConfig{
			indexRoot: *indexRoot, defaultMode: *defaultMode, annotationDataDir: *annotationDataDir,
			userLexiconDir: *userLexiconDir, userBlocklist: *userBlocklist, learningConfig: *learningConfig,
			professionalRoot: *professionalRoot, professionalState: *professionalState,
			namedPipe: *namedPipe, trustedClientID: *trustedClientID,
			pipeMaxConnections: *pipeMaxConnections, pipeMaxConnectionsPerClient: *pipeMaxConnectionsPerClient,
			userSnapshot: *userSnapshot, userJournal: *userJournal, userModelSourceID: *userModelSourceID,
			checkpointEvery: *checkpointEvery, compactEvery: *compactEvery, rollbackSnapshot: *rollbackSnapshot,
			indexVersion: *indexVersion, indexControlManifest: *indexControlManifest, indexControlStatus: *indexControlStatus,
		})
		return
	}
	if *indexPath == "" || *mode == "" {
		fail(fmt.Errorf("index and mode are required"))
	}
	if (*namedPipe == "") == (*trustedClientID == "") {
		fail(fmt.Errorf("supply exactly one of named-pipe or trusted-client-id"))
	}
	if *namedPipe != "" && (*exitBeforeRequest != 0 || *hangBeforeRequest != 0 || *exitAfterRequest != 0) {
		fail(fmt.Errorf("anonymous-pipe fault injection cannot be combined with named-pipe transport"))
	}
	index, err := yimecore.OpenFileIndex(*indexPath)
	if err != nil {
		fail(err)
	}
	defer index.Close()
	if index.Mode() != *mode {
		fail(fmt.Errorf("index mode %q does not match %q", index.Mode(), *mode))
	}
	var annotationResolver *candidateannotation.Resolver
	if *annotationDataDir != "" {
		annotationResolver, err = candidateannotation.Load(*annotationDataDir, *mode)
		if err != nil {
			fail(fmt.Errorf("load candidate annotations: %w", err))
		}
	}
	decorate := func(engine engineapi.Engine, buildErr error) (engineapi.Engine, error) {
		if buildErr != nil || annotationResolver == nil {
			return engine, buildErr
		}
		return candidateannotation.Wrap(engine, annotationResolver)
	}
	var durable *yimebroker.DurableUserModel
	if (*userSnapshot == "") != (*userJournal == "") {
		fail(fmt.Errorf("user-model-snapshot and user-model-journal must be supplied together"))
	}
	if *userModelSourceID != "" && *userSnapshot == "" {
		fail(fmt.Errorf("user-model-source-id requires durable user-model paths"))
	}
	if *exitCompactionStage != "" && *userSnapshot == "" {
		fail(fmt.Errorf("experiment-exit-compaction-stage requires durable user-model paths"))
	}
	var builder yimebroker.IndexEngineBuilder
	if *userSnapshot != "" {
		modelSourceID := *userModelSourceID
		if modelSourceID == "" {
			modelSourceID = index.SourceID()
		}
		var compactionHook func(yimebroker.CompactionStage)
		if *exitCompactionStage != "" {
			validStage := false
			for _, stage := range []yimebroker.CompactionStage{yimebroker.CompactionAfterSnapshot, yimebroker.CompactionAfterJournalClose, yimebroker.CompactionAfterJournalReplace} {
				if string(stage) == *exitCompactionStage {
					validStage = true
				}
			}
			if !validStage {
				fail(fmt.Errorf("unknown compaction stage %q", *exitCompactionStage))
			}
			compactionHook = func(stage yimebroker.CompactionStage) {
				if string(stage) == *exitCompactionStage {
					os.Exit(88)
				}
			}
		}
		durable, err = yimebroker.OpenDurableUserModel(yimebroker.DurableUserModelConfig{
			SnapshotPath: *userSnapshot, JournalPath: *userJournal, RollbackSnapshotPath: *rollbackSnapshot, SourceID: modelSourceID,
			CheckpointEvery: *checkpointEvery, CompactEvery: *compactEvery, CompactionStageHook: compactionHook,
		})
		if err != nil {
			fail(err)
		}
		defer func() {
			if err := durable.Close(); err != nil {
				fmt.Fprintln(os.Stderr, err)
			}
		}()
		builder = func(target *yimecore.FileIndex) (engineapi.Engine, error) {
			model, configErr := enabledUserModel(*learningConfig, durable.Model())
			if configErr != nil {
				return nil, configErr
			}
			if model == nil {
				return decorate(yimecore.NewFileEngine(target, 9))
			}
			return decorate(yimecore.NewFileEngineWithUserModel(target, 9, model))
		}
	} else {
		builder = func(target *yimecore.FileIndex) (engineapi.Engine, error) {
			return decorate(yimecore.NewFileEngine(target, 9))
		}
	}
	var factory yimebroker.EngineFactory = func() (engineapi.Engine, error) { return builder(index) }
	var manager *yimebroker.IndexManager
	controlEnabled := *indexControlManifest != "" || *indexControlStatus != "" || *indexVersion != "" || *indexSHA256 != ""
	if controlEnabled {
		if *indexControlManifest == "" || *indexControlStatus == "" || *indexVersion == "" || *indexSHA256 == "" {
			fail(fmt.Errorf("managed index requires version, SHA-256, control manifest and status paths"))
		}
		manager, err = yimebroker.OpenIndexManager(yimebroker.IndexSpec{
			Version: *indexVersion, Mode: *mode, Path: *indexPath, ExpectedSHA256: *indexSHA256,
		}, builder, nil)
		if err != nil {
			fail(err)
		}
		defer manager.Close()
		factory = manager.NewEngine
	}
	dispatcher, err := yimebroker.NewDispatcher(factory, yimebroker.Config{})
	if err != nil {
		fail(err)
	}
	serveContext, stopSignals := signal.NotifyContext(context.Background(), os.Interrupt)
	defer stopSignals()
	serveContext, cancel := context.WithCancel(serveContext)
	defer cancel()
	if manager != nil {
		go func() {
			if watchErr := yimebroker.WatchIndexControl(serveContext, *indexControlManifest, *indexControlStatus, manager, 50*time.Millisecond); watchErr != nil {
				fmt.Fprintln(os.Stderr, watchErr)
				cancel()
			}
		}()
	}
	if *namedPipe != "" {
		err = yimebroker.ServeNamedPipe(serveContext, dispatcher, yimebroker.NamedPipeConfig{
			Name: *namedPipe, MaxConnections: *pipeMaxConnections, MaxConnectionsPerClient: *pipeMaxConnectionsPerClient,
			OnConnectionError: func(connectionErr error) { fmt.Fprintln(os.Stderr, connectionErr) },
		})
	} else {
		client := yimebroker.TrustedClient{ID: *trustedClientID}
		if *exitBeforeRequest == 0 && *hangBeforeRequest == 0 && *exitAfterRequest == 0 {
			err = yimebroker.ServeLines(serveContext, os.Stdin, os.Stdout, dispatcher, client)
		} else {
			err = serveFaultExperiment(serveContext, dispatcher, client, *exitBeforeRequest, *hangBeforeRequest, *exitAfterRequest)
		}
	}
	if err != nil {
		fail(err)
	}
}

type multiModeConfig struct {
	indexRoot                   string
	defaultMode                 string
	annotationDataDir           string
	userLexiconDir              string
	userBlocklist               string
	learningConfig              string
	professionalRoot            string
	professionalState           string
	namedPipe                   string
	trustedClientID             string
	pipeMaxConnections          int
	pipeMaxConnectionsPerClient int
	userSnapshot                string
	userJournal                 string
	userModelSourceID           string
	checkpointEvery             int
	compactEvery                int
	rollbackSnapshot            string
	indexVersion                string
	indexControlManifest        string
	indexControlStatus          string
}

func runMultiMode(config multiModeConfig) {
	if (config.namedPipe == "") == (config.trustedClientID == "") {
		fail(fmt.Errorf("supply exactly one of named-pipe or trusted-client-id"))
	}
	modes := []string{"full", "variable", "shorthand"}
	resolvers := make(map[string]*candidateannotation.Resolver, len(modes))
	for _, mode := range modes {
		if config.annotationDataDir != "" {
			resolver, err := candidateannotation.Load(config.annotationDataDir, mode)
			if err != nil {
				fail(fmt.Errorf("load %s candidate annotations: %w", mode, err))
			}
			resolvers[mode] = resolver
		}
	}
	if (config.userSnapshot == "") != (config.userJournal == "") {
		fail(fmt.Errorf("user-model-snapshot and user-model-journal must be supplied together"))
	}
	if config.userSnapshot != "" && config.userModelSourceID == "" {
		fail(fmt.Errorf("multi-index durable learning requires a stable user-model-source-id"))
	}
	var professional *professionallexicon.Set
	if config.professionalRoot != "" || config.professionalState != "" {
		if config.professionalRoot == "" || config.professionalState == "" {
			fail(fmt.Errorf("professional-root and professional-state must be supplied together"))
		}
		var err error
		professional, err = professionallexicon.OpenSelected(config.professionalRoot, config.professionalState)
		if err != nil {
			fail(err)
		}
		defer professional.Close()
	}
	var durable *yimebroker.DurableUserModel
	if config.userSnapshot != "" {
		var err error
		durable, err = yimebroker.OpenDurableUserModel(yimebroker.DurableUserModelConfig{
			SnapshotPath: config.userSnapshot, JournalPath: config.userJournal,
			RollbackSnapshotPath: config.rollbackSnapshot, SourceID: config.userModelSourceID,
			CheckpointEvery: config.checkpointEvery, CompactEvery: config.compactEvery,
		})
		if err != nil {
			fail(err)
		}
		defer func() {
			if err := durable.Close(); err != nil {
				fmt.Fprintln(os.Stderr, err)
			}
		}()
	}
	builder := func(mode string, index *yimecore.FileIndex) (engineapi.Engine, error) {
		var engine engineapi.Engine
		var err error
		var model *yimecore.UserModel
		if durable != nil {
			model, err = enabledUserModel(config.learningConfig, durable.Model())
			if err != nil {
				return nil, err
			}
		}
		modules := professional.Modules(mode)
		if len(modules) > 0 {
			bundle, bundleErr := yimecore.NewBundleIndex(index, modules)
			if bundleErr != nil {
				return nil, bundleErr
			}
			if config.userLexiconDir != "" {
				engine, err = yimecore.NewBundleEngineWithUserLexicon(
					bundle, 9, filepath.Join(config.userLexiconDir, "custom_phrase_"+mode+".txt"), model)
			} else if model != nil {
				engine, err = yimecore.NewBundleEngineWithUserModel(bundle, 9, model)
			} else {
				engine, err = yimecore.NewBundleEngine(bundle, 9)
			}
		} else if config.userLexiconDir != "" {
			engine, err = yimecore.NewFileEngineWithUserLexicon(index, 9,
				filepath.Join(config.userLexiconDir, "custom_phrase_"+mode+".txt"), model)
		} else if model != nil {
			engine, err = yimecore.NewFileEngineWithUserModel(index, 9, model)
		} else {
			engine, err = yimecore.NewFileEngine(index, 9)
		}
		if err != nil {
			return engine, err
		}
		if resolvers[mode] != nil {
			engine, err = candidateannotation.Wrap(engine, resolvers[mode])
			if err != nil {
				return nil, err
			}
		}
		if config.userBlocklist != "" {
			engine, err = candidatefilter.Wrap(engine, config.userBlocklist)
		}
		return engine, err
	}
	controlEnabled := config.indexControlManifest != "" || config.indexControlStatus != "" || config.indexVersion != ""
	if controlEnabled && (config.indexControlManifest == "" || config.indexControlStatus == "" || config.indexVersion == "") {
		fail(fmt.Errorf("managed multi-index mode requires version, control manifest and status paths"))
	}
	initialVersion := config.indexVersion
	if initialVersion == "" {
		initialVersion = "trial-initial"
	}
	initial := make(map[string]yimebroker.IndexSpec, len(modes))
	for _, mode := range modes {
		path := filepath.Join(config.indexRoot, mode+".yidx")
		hash, err := yimebroker.IndexFileSHA256(path)
		if err != nil {
			fail(fmt.Errorf("hash %s index: %w", mode, err))
		}
		initial[mode] = yimebroker.IndexSpec{Version: initialVersion, Mode: mode, Path: path, ExpectedSHA256: hash}
	}
	// The multi-index YimeCore trial deliberately loads all three system
	// dictionaries once at Broker startup. This is isolated from the legacy
	// single-index experiment and from production Rime/PIME.
	managers, err := yimebroker.OpenResidentModeIndexManager(initial, builder, nil)
	if err != nil {
		fail(err)
	}
	defer managers.Close()
	dispatcher, err := yimebroker.NewModeDispatcher(config.defaultMode, managers.NewEngine, yimebroker.Config{})
	if err != nil {
		fail(err)
	}
	serveContext, stopSignals := signal.NotifyContext(context.Background(), os.Interrupt)
	defer stopSignals()
	serveContext, cancel := context.WithCancel(serveContext)
	defer cancel()
	if controlEnabled {
		go func() {
			if watchErr := yimebroker.WatchModeIndexControl(serveContext, config.indexControlManifest, config.indexControlStatus, managers, 50*time.Millisecond); watchErr != nil {
				fmt.Fprintln(os.Stderr, watchErr)
				cancel()
			}
		}()
	}
	if config.namedPipe != "" {
		err = yimebroker.ServeNamedPipe(serveContext, dispatcher, yimebroker.NamedPipeConfig{
			Name: config.namedPipe, MaxConnections: config.pipeMaxConnections, MaxConnectionsPerClient: config.pipeMaxConnectionsPerClient,
			OnConnectionError: func(connectionErr error) { fmt.Fprintln(os.Stderr, connectionErr) },
		})
	} else {
		err = yimebroker.ServeLines(serveContext, os.Stdin, os.Stdout, dispatcher, yimebroker.TrustedClient{ID: config.trustedClientID})
	}
	if err != nil {
		fail(err)
	}
}

func enabledUserModel(configPath string, model *yimecore.UserModel) (*yimecore.UserModel, error) {
	if model == nil || configPath == "" {
		return model, nil
	}
	config, err := learningconfig.Load(configPath)
	if err != nil {
		return nil, fmt.Errorf("load learning configuration: %w", err)
	}
	if !config.Enabled {
		return nil, nil
	}
	return model, nil
}

func serveFaultExperiment(ctx context.Context, dispatcher *yimebroker.Dispatcher, client yimebroker.TrustedClient, exitBefore, hangBefore, exitAfter int) error {
	scanner := bufio.NewScanner(os.Stdin)
	scanner.Buffer(make([]byte, 4096), yimebroker.MaxMessageBytes+1)
	writer := bufio.NewWriter(os.Stdout)
	requestNumber := 0
	for scanner.Scan() {
		if len(scanner.Bytes()) > yimebroker.MaxMessageBytes {
			return fmt.Errorf("broker request exceeds %d bytes", yimebroker.MaxMessageBytes)
		}
		requestNumber++
		if requestNumber == exitBefore {
			os.Exit(86)
		}
		if requestNumber == hangBefore {
			for {
				time.Sleep(time.Hour)
			}
		}
		response := dispatcher.HandleJSON(ctx, client, append([]byte(nil), scanner.Bytes()...))
		if requestNumber == exitAfter {
			os.Exit(87)
		}
		if _, err := writer.Write(response); err != nil {
			return err
		}
		if err := writer.WriteByte('\n'); err != nil {
			return err
		}
		if err := writer.Flush(); err != nil {
			return err
		}
	}
	return scanner.Err()
}

func fail(err error) {
	fmt.Fprintln(os.Stderr, err)
	os.Exit(1)
}
