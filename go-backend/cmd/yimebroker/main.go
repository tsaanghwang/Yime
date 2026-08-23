// Command yimebroker is the E5-B standalone process experiment. It is not
// wired into PIME, TSF, installation, startup registration, or production.
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
	"github.com/tsaanghwang/Yime/go-backend/input_methods/yime/engineapi"
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
	exitBeforeRequest := flag.Int("experiment-exit-before-request", 0, "E5-B fault injection only")
	hangBeforeRequest := flag.Int("experiment-hang-before-request", 0, "E5-B fault injection only")
	exitAfterRequest := flag.Int("experiment-exit-after-request", 0, "E5-F fault injection after durable handling but before response")
	exitCompactionStage := flag.String("experiment-exit-compaction-stage", "", "E5-G fault injection at a named compaction stage")
	flag.Parse()
	if *indexRoot != "" {
		if *indexPath != "" || *mode != "" {
			fail(fmt.Errorf("index-root cannot be combined with index or mode"))
		}
		if *userSnapshot != "" || *userJournal != "" || *indexControlManifest != "" || *indexControlStatus != "" || *indexVersion != "" || *indexSHA256 != "" {
			fail(fmt.Errorf("multi-index mode does not yet combine with durable learning or index-control switching"))
		}
		runMultiMode(*indexRoot, *defaultMode, *annotationDataDir, *namedPipe, *trustedClientID,
			*pipeMaxConnections, *pipeMaxConnectionsPerClient)
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
			return decorate(yimecore.NewFileEngineWithUserModel(target, 9, durable.Model()))
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

func runMultiMode(indexRoot, defaultMode, annotationDataDir, namedPipe, trustedClientID string,
	pipeMaxConnections, pipeMaxConnectionsPerClient int) {
	if (namedPipe == "") == (trustedClientID == "") {
		fail(fmt.Errorf("supply exactly one of named-pipe or trusted-client-id"))
	}
	modes := []string{"full", "variable", "shorthand"}
	indices := make(map[string]*yimecore.FileIndex, len(modes))
	resolvers := make(map[string]*candidateannotation.Resolver, len(modes))
	for _, mode := range modes {
		index, err := yimecore.OpenFileIndex(filepath.Join(indexRoot, mode+".yidx"))
		if err != nil {
			fail(fmt.Errorf("open %s index: %w", mode, err))
		}
		if index.Mode() != mode {
			_ = index.Close()
			fail(fmt.Errorf("index file for %s reports mode %q", mode, index.Mode()))
		}
		indices[mode] = index
		if annotationDataDir != "" {
			resolver, err := candidateannotation.Load(annotationDataDir, mode)
			if err != nil {
				closeIndices(indices)
				fail(fmt.Errorf("load %s candidate annotations: %w", mode, err))
			}
			resolvers[mode] = resolver
		}
	}
	defer closeIndices(indices)
	factory := func(mode string) (engineapi.Engine, error) {
		index := indices[mode]
		if index == nil {
			return nil, fmt.Errorf("unsupported session mode %q", mode)
		}
		engine, err := yimecore.NewFileEngine(index, 9)
		if err != nil || resolvers[mode] == nil {
			return engine, err
		}
		return candidateannotation.Wrap(engine, resolvers[mode])
	}
	dispatcher, err := yimebroker.NewModeDispatcher(defaultMode, factory, yimebroker.Config{})
	if err != nil {
		fail(err)
	}
	serveContext, stopSignals := signal.NotifyContext(context.Background(), os.Interrupt)
	defer stopSignals()
	if namedPipe != "" {
		err = yimebroker.ServeNamedPipe(serveContext, dispatcher, yimebroker.NamedPipeConfig{
			Name: namedPipe, MaxConnections: pipeMaxConnections, MaxConnectionsPerClient: pipeMaxConnectionsPerClient,
			OnConnectionError: func(connectionErr error) { fmt.Fprintln(os.Stderr, connectionErr) },
		})
	} else {
		err = yimebroker.ServeLines(serveContext, os.Stdin, os.Stdout, dispatcher, yimebroker.TrustedClient{ID: trustedClientID})
	}
	if err != nil {
		fail(err)
	}
}

func closeIndices(indices map[string]*yimecore.FileIndex) {
	for _, index := range indices {
		_ = index.Close()
	}
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
