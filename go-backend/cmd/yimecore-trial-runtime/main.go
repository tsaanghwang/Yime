// Command yimecore-trial-runtime keeps the independent YimeCore trial Broker
// available at its stable endpoint and owns the optional native Desktop Tools window.
package main

import (
	"encoding/json"
	"errors"
	"flag"
	"fmt"
	"io"
	"log"
	"os"
	"path/filepath"
	"strings"
	"time"

	"github.com/tsaanghwang/Yime/go-backend/input_methods/yime/layoutdesigner"
	"github.com/tsaanghwang/Yime/go-backend/input_methods/yime/toolbarstate"
)

const (
	defaultPipeName = `\\.\pipe\YimeBroker.YimeCoreTrial.v1`
	modelSourceID   = "yimecore-e6c-three-mode-trial-v1"
	statusSchema    = "yimecore-trial-runtime-v1"
)

type options struct {
	installRoot  string
	brokerPath   string
	stateRoot    string
	pipeName     string
	noToolbar    bool
	indexRoot    string
	dataDir      string
	indexVersion string
}

type runtimeStatus struct {
	SchemaVersion string `json:"schema_version"`
	State         string `json:"state"`
	UpdatedAt     string `json:"updated_at"`
	RuntimePID    int    `json:"runtime_pid"`
	BrokerPID     int    `json:"broker_pid,omitempty"`
	ToolbarPID    int    `json:"toolbar_pid,omitempty"`
	ToolbarState  string `json:"toolbar_state,omitempty"`
	ToolbarError  string `json:"toolbar_error,omitempty"`
	InstallRoot   string `json:"install_root"`
	BrokerPath    string `json:"broker_path"`
	StateRoot     string `json:"state_root"`
	PipeName      string `json:"pipe_name"`
	Restarts      int    `json:"restarts"`
	LastError     string `json:"last_error,omitempty"`
	IndexRoot     string `json:"index_root,omitempty"`
	DataDir       string `json:"data_dir,omitempty"`
	IndexVersion  string `json:"index_version,omitempty"`
}

func main() {
	installRoot := flag.String("install-root", "", "full YimeCore experimental package root")
	brokerPath := flag.String("broker", "", "optional Broker executable override")
	stateRoot := flag.String("state-root", "", "durable per-user trial state root")
	pipeName := flag.String("pipe", defaultPipeName, "local trial Broker named pipe")
	noToolbar := flag.Bool("no-toolbar", false, "do not start the native Desktop Tools window")
	stop := flag.Bool("stop", false, "stop the active trial runtime")
	status := flag.Bool("status", false, "print the last runtime status")
	flag.Parse()

	resolved, err := resolveOptions(options{
		installRoot: *installRoot, brokerPath: *brokerPath, stateRoot: *stateRoot,
		pipeName: *pipeName, noToolbar: *noToolbar,
	})
	if err != nil {
		fail(err)
	}
	statusPath := filepath.Join(resolved.stateRoot, "runtime-status.json")
	if *stop {
		if err := stopActiveRuntime(statusPath, resolved.pipeName, 5*time.Second); err != nil {
			fail(err)
		}
		return
	}
	if *status {
		data, err := os.ReadFile(statusPath)
		if err != nil {
			fail(err)
		}
		fmt.Print(string(data))
		return
	}
	if err := run(resolved, statusPath); err != nil {
		fail(err)
	}
}

func resolveOptions(value options) (options, error) {
	if strings.TrimSpace(value.installRoot) == "" {
		executable, err := os.Executable()
		if err != nil {
			return value, err
		}
		value.installRoot = filepath.Dir(filepath.Dir(executable))
	}
	root, err := filepath.Abs(value.installRoot)
	if err != nil {
		return value, err
	}
	value.installRoot = filepath.Clean(root)
	if value.brokerPath == "" {
		value.brokerPath = filepath.Join(value.installRoot, "bin", "YimeBroker.exe")
	}
	value.brokerPath, err = filepath.Abs(value.brokerPath)
	if err != nil {
		return value, err
	}
	if value.stateRoot == "" {
		local := os.Getenv("LOCALAPPDATA")
		if local == "" {
			return value, errors.New("LOCALAPPDATA is unavailable")
		}
		value.stateRoot = filepath.Join(local, "YimeCore Experimental Trial")
	}
	value.stateRoot, err = filepath.Abs(value.stateRoot)
	if err != nil {
		return value, err
	}
	if value.pipeName == "" {
		return value, errors.New("trial Broker pipe is required")
	}
	for _, required := range []string{
		value.brokerPath,
		filepath.Join(value.installRoot, "indexes", "full.yidx"),
		filepath.Join(value.installRoot, "indexes", "variable.yidx"),
		filepath.Join(value.installRoot, "indexes", "shorthand.yidx"),
		filepath.Join(value.installRoot, "data", "yime_pinyin_codes.tsv"),
	} {
		if info, statErr := os.Stat(required); statErr != nil || info.IsDir() {
			return value, fmt.Errorf("required trial file is unavailable: %s", required)
		}
	}
	value.indexRoot = filepath.Join(value.installRoot, "indexes")
	value.dataDir = filepath.Join(value.installRoot, "data")
	value.indexVersion = "installed-v1"
	if generation, loadErr := layoutdesigner.LoadTrialLayoutGeneration(value.stateRoot); loadErr == nil {
		value.indexRoot = generation.IndexRoot
		value.dataDir = generation.DataDir
		value.indexVersion = generation.Version
	} else if !errors.Is(loadErr, os.ErrNotExist) {
		return value, fmt.Errorf("load Trial layout generation: %w", loadErr)
	}
	if !value.noToolbar {
		for _, tool := range []string{inputToolbarPath(value.installRoot), trainerPath(value.installRoot), toolCenterPath(value.installRoot)} {
			if info, statErr := os.Stat(tool); statErr != nil || info.IsDir() {
				return value, fmt.Errorf("required native Trial tool is unavailable: %s", tool)
			}
		}
	}
	return value, nil
}

func run(config options, statusPath string) error {
	if err := os.MkdirAll(filepath.Join(config.stateRoot, "logs"), 0o755); err != nil {
		return err
	}
	instance, alreadyRunning, err := acquireRuntimeInstance(config.pipeName)
	if err != nil {
		return err
	}
	if alreadyRunning {
		return nil
	}
	defer instance.Close()
	stopEvent, err := createRuntimeStopEvent(config.pipeName)
	if err != nil {
		return err
	}
	defer stopEvent.Close()
	logFile, err := os.OpenFile(filepath.Join(config.stateRoot, "logs", "runtime.log"), os.O_CREATE|os.O_APPEND|os.O_WRONLY, 0o600)
	if err != nil {
		return err
	}
	defer logFile.Close()
	logger := log.New(logFile, "", log.LstdFlags|log.Lmicroseconds|log.LUTC)
	logger.Printf("runtime starting install_root=%q broker=%q", config.installRoot, config.brokerPath)
	children, err := createChildProcessJob()
	if err != nil {
		return fmt.Errorf("create child process job: %w", err)
	}
	defer children.Close()

	toolbar, toolbarWait, toolbarErr := startToolbar(config, logger, children)
	toolbarPID := processID(toolbar)
	toolbarState := "running"
	toolbarError := ""
	if config.noToolbar {
		toolbarState = "disabled"
	} else if toolbarErr != nil {
		toolbarState = "unavailable"
		toolbarError = toolbarErr.Error()
	}
	restarts := 0
	failures := make([]time.Time, 0, 8)
	for {
		broker, wait, startErr := startBroker(config, logger, children)
		if startErr != nil {
			writeRuntimeStatus(statusPath, withToolbarStatus(statusFor(config, "failed", 0, toolbarPID, restarts, startErr), toolbarState, toolbarError))
			return startErr
		}
		writeRuntimeStatus(statusPath, withToolbarStatus(statusFor(config, "running", broker.PID(), toolbarPID, restarts, nil), toolbarState, toolbarError))
		logger.Printf("Broker started pid=%d restart=%d", broker.PID(), restarts)
		for {
			if stopEvent.Wait(200 * time.Millisecond) {
				_ = broker.Kill()
				<-wait
				stopProcess(toolbar)
				writeRuntimeStatus(statusPath, statusFor(config, "stopped", 0, 0, restarts, nil))
				logger.Printf("runtime stopped")
				return nil
			}
			select {
			case waitErr := <-toolbarWait:
				toolbarWait = nil
				toolbar = nil
				toolbarPID = 0
				toolbarState = "exited"
				toolbarError = fmt.Sprint(waitErr)
				logger.Printf("optional toolbar exited err=%v", waitErr)
				writeRuntimeStatus(statusPath, withToolbarStatus(statusFor(config, "running", broker.PID(), 0, restarts, nil), toolbarState, toolbarError))
			case waitErr := <-wait:
				now := time.Now()
				failures = append(failures, now)
				cutoff := now.Add(-30 * time.Second)
				kept := failures[:0]
				for _, failure := range failures {
					if failure.After(cutoff) {
						kept = append(kept, failure)
					}
				}
				failures = kept
				logger.Printf("Broker exited err=%v failures_30s=%d", waitErr, len(failures))
				if len(failures) >= 5 {
					err := fmt.Errorf("Broker exited five times within 30 seconds: %w", waitErr)
					writeRuntimeStatus(statusPath, withToolbarStatus(statusFor(config, "failed", 0, toolbarPID, restarts, err), toolbarState, toolbarError))
					stopProcess(toolbar)
					return err
				}
				restarts++
				time.Sleep(time.Duration(restarts) * 200 * time.Millisecond)
				goto restart
			default:
			}
		}
	restart:
	}
}

func startBroker(config options, logger *log.Logger, children *runtimeHandle) (*runtimeProcess, <-chan error, error) {
	modelRoot := trialModelRoot(config)
	controlRoot := filepath.Join(config.stateRoot, "index-control")
	if err := os.MkdirAll(modelRoot, 0o755); err != nil {
		return nil, nil, err
	}
	if err := os.MkdirAll(controlRoot, 0o755); err != nil {
		return nil, nil, err
	}
	brokerLog, err := os.OpenFile(filepath.Join(config.stateRoot, "logs", "broker.log"), os.O_CREATE|os.O_APPEND|os.O_WRONLY, 0o600)
	if err != nil {
		return nil, nil, err
	}
	process, err := startProcessInJob(config.brokerPath, brokerArguments(config), brokerLog, children)
	if err != nil {
		_ = brokerLog.Close()
		return nil, nil, err
	}
	wait := make(chan error, 1)
	go func() {
		wait <- process.Wait()
		_ = brokerLog.Close()
	}()
	return process, wait, nil
}

func brokerArguments(config options) []string {
	modelRoot := trialModelRoot(config)
	controlRoot := filepath.Join(config.stateRoot, "index-control")
	return []string{
		"-index-root", trialIndexRoot(config),
		"-default-mode", "variable",
		"-annotation-data-dir", trialDataDir(config),
		"-user-lexicon-dir", config.stateRoot,
		"-user-blocklist", filepath.Join(config.stateRoot, "yime_blocklist.txt"),
		"-learning-config", filepath.Join(config.stateRoot, "learning.json"),
		"-professional-root", filepath.Join(config.installRoot, "professional-lexicons"),
		"-professional-state", filepath.Join(config.stateRoot, "professional-lexicons.json"),
		"-named-pipe", config.pipeName,
		"-user-model-snapshot", filepath.Join(modelRoot, "user-model.json"),
		"-user-model-journal", filepath.Join(modelRoot, "user-model.journal"),
		"-user-model-source-id", modelSourceID + ":" + trialIndexVersion(config),
		"-user-model-checkpoint-every", "256",
		"-user-model-compact-every", "4096",
		"-index-version", trialIndexVersion(config),
		"-index-control-manifest", filepath.Join(controlRoot, "request.json"),
		"-index-control-status", filepath.Join(controlRoot, "status.json"),
	}
}

func trialIndexRoot(config options) string {
	if config.indexRoot != "" {
		return config.indexRoot
	}
	return filepath.Join(config.installRoot, "indexes")
}

func trialDataDir(config options) string {
	if config.dataDir != "" {
		return config.dataDir
	}
	return filepath.Join(config.installRoot, "data")
}

func trialIndexVersion(config options) string {
	if config.indexVersion != "" {
		return config.indexVersion
	}
	return "installed-v1"
}

func trialModelRoot(config options) string {
	return filepath.Join(config.stateRoot, "user-model", trialIndexVersion(config))
}

func startToolbar(config options, logger *log.Logger, children *runtimeHandle) (*runtimeProcess, <-chan error, error) {
	if config.noToolbar {
		return nil, nil, nil
	}
	toolbarLog, err := os.OpenFile(filepath.Join(config.stateRoot, "logs", "toolbar.log"), os.O_CREATE|os.O_APPEND|os.O_WRONLY, 0o600)
	if err != nil {
		logger.Printf("open toolbar log: %v", err)
		return nil, nil, err
	}
	process, err := startProcessInJob(inputToolbarPath(config.installRoot), inputToolbarArguments(config), toolbarLog, children)
	if err != nil {
		logger.Printf("start toolbar: %v", err)
		_ = toolbarLog.Close()
		return nil, nil, err
	}
	wait := make(chan error, 1)
	go func() {
		wait <- process.Wait()
		_ = toolbarLog.Close()
	}()
	return process, wait, nil
}

func inputToolbarPath(installRoot string) string {
	return filepath.Join(installRoot, "bin", "YimeCoreInputToolbar.exe")
}

func settingsToolPath(installRoot string) string {
	return filepath.Join(installRoot, "bin", "YimeCoreSettingsTool.exe")
}

func trainerPath(installRoot string) string {
	return filepath.Join(installRoot, "bin", "YimeCoreTrainer.exe")
}

func toolCenterPath(installRoot string) string {
	return filepath.Join(installRoot, "bin", "YimeCoreToolCenter.exe")
}

func inputToolbarArguments(config options) []string {
	return []string{
		"-StatePath", filepath.Join(config.stateRoot, toolbarstate.ExperimentFileName),
		"-SettingsTool", settingsToolPath(config.installRoot),
		"-TrainerTool", trainerPath(config.installRoot),
		"-ToolCenterTool", toolCenterPath(config.installRoot),
		"-SharedDir", filepath.Join(config.installRoot, "data"),
		"-UserDir", config.stateRoot,
		"-HelpDir", filepath.Join(config.installRoot, "help"),
		"-LogDir", filepath.Join(config.stateRoot, "logs"),
		"-Experimental",
	}
}

func statusFor(config options, state string, brokerPID, toolbarPID, restarts int, statusErr error) runtimeStatus {
	value := runtimeStatus{
		SchemaVersion: statusSchema, State: state, UpdatedAt: time.Now().UTC().Format(time.RFC3339Nano),
		RuntimePID: os.Getpid(), BrokerPID: brokerPID, ToolbarPID: toolbarPID, InstallRoot: config.installRoot,
		BrokerPath: config.brokerPath, StateRoot: config.stateRoot, PipeName: config.pipeName, Restarts: restarts,
		IndexRoot: trialIndexRoot(config), DataDir: trialDataDir(config), IndexVersion: trialIndexVersion(config),
	}
	if statusErr != nil {
		value.LastError = statusErr.Error()
	}
	return value
}

func withToolbarStatus(status runtimeStatus, state, toolbarError string) runtimeStatus {
	status.ToolbarState = state
	status.ToolbarError = toolbarError
	return status
}

func writeRuntimeStatus(path string, status runtimeStatus) {
	data, err := json.MarshalIndent(status, "", "  ")
	if err != nil {
		return
	}
	data = append(data, '\n')
	_ = os.MkdirAll(filepath.Dir(path), 0o755)
	temporary, err := os.CreateTemp(filepath.Dir(path), ".runtime-status-*.tmp")
	if err != nil {
		return
	}
	temporaryPath := temporary.Name()
	defer os.Remove(temporaryPath)
	if _, err := temporary.Write(data); err != nil {
		_ = temporary.Close()
		return
	}
	_ = temporary.Sync()
	_ = temporary.Close()
	if err := os.Rename(temporaryPath, path); err != nil {
		_ = os.Remove(path)
		_ = os.Rename(temporaryPath, path)
	}
}

func stopActiveRuntime(statusPath, pipeName string, timeout time.Duration) error {
	status, _ := readRuntimeStatus(statusPath)
	if err := signalRuntimeStop(pipeName); err != nil {
		if status.RuntimePID == 0 || !processRunning(status.RuntimePID) {
			return nil
		}
		return err
	}
	deadline := time.Now().Add(timeout)
	for time.Now().Before(deadline) {
		if status.RuntimePID == 0 || !processRunning(status.RuntimePID) {
			return nil
		}
		time.Sleep(50 * time.Millisecond)
	}
	return errors.New("trial runtime did not stop within timeout")
}

func readRuntimeStatus(path string) (runtimeStatus, error) {
	data, err := os.ReadFile(path)
	if err != nil {
		return runtimeStatus{}, err
	}
	var status runtimeStatus
	err = json.Unmarshal(data, &status)
	return status, err
}

func processID(process *runtimeProcess) int {
	if process == nil {
		return 0
	}
	return process.PID()
}

func stopProcess(process *runtimeProcess) {
	if process != nil {
		_ = process.Kill()
	}
}

func fail(err error) {
	if !errors.Is(err, io.EOF) {
		fmt.Fprintln(os.Stderr, err)
	}
	os.Exit(1)
}
