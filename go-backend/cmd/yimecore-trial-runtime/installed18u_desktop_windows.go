//go:build windows && (amd64 || arm64)

package main

import (
	"bufio"
	"context"
	"errors"
	"fmt"
	"io"
	"os"
	"path/filepath"
	"strconv"
	"strings"
	"sync"
	"time"

	"github.com/tsaanghwang/Yime/go-backend/internal/installed18uhost"
	"github.com/tsaanghwang/Yime/go-backend/internal/touchbroker"
	"github.com/tsaanghwang/Yime/go-backend/internal/touchdiagnostic"
)

// Desktop lifetime belongs to one initiating-user process and its kill-on-close
// Job. Closing the keyboard or stopping this runtime terminates only its own
// children; the standard YimeCore and Rime/PIME runtimes are never enumerated.
func runInstalled18uDesktop(root, anchor string, stop bool) error {
	if !nativeInstalled18u() {
		return errors.New("matching native x64 or ARM64 Windows required; no emulation")
	}
	_, err := installed18uhost.VerifyDesktopInstallation(root, anchor)
	if err != nil {
		return err
	}
	executable, err := os.Executable()
	if err != nil {
		return err
	}
	actual, err := filepath.EvalSymlinks(executable)
	if err != nil {
		return err
	}
	expected, err := filepath.EvalSymlinks(filepath.Join(root, filepath.FromSlash(installed18uhost.ControllerPath)))
	if err != nil || !strings.EqualFold(actual, expected) {
		return errors.New("runtime must be the installed 18u payload")
	}
	name, err := touchbroker.DesktopPipeName()
	if err != nil {
		return err
	}
	if stop {
		return signalRuntimeStop(name)
	}
	instance, already, err := acquireRuntimeInstance(name)
	if err != nil {
		return err
	}
	if already {
		return nil
	}
	defer instance.Close()
	stopEvent, err := createRuntimeStopEvent(name)
	if err != nil {
		return err
	}
	defer stopEvent.Close()
	job, err := createChildProcessJob()
	if err != nil {
		return err
	}
	var closeOnce sync.Once
	var jobMu sync.Mutex
	stopJob := func() { closeOnce.Do(func() { jobMu.Lock(); defer jobMu.Unlock(); _ = job.Close() }) }
	defer stopJob()
	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()
	start := installedStart(job, &jobMu, stopJob)
	diagnosticDir, diagnosticErr := touchdiagnostic.DefaultDirectory()
	recorder := touchdiagnostic.OpenRecorder(diagnosticDir, diagnosticErr)
	defer recorder.Close()
	broker, err := startDesktopDiagnosticChild(start, recorder, ctx, filepath.Join(root, filepath.FromSlash(installed18uhost.BrokerPath)), []string{"--installed-desktop", "--install-root", root, "--manifest-sha256", anchor}, root)
	if err != nil {
		return err
	}
	defer broker.Stop()
	brokerExit := make(chan error, 1)
	go func() { brokerExit <- broker.Wait() }()
	ready := make(chan error, 1)
	go func() {
		r := bufio.NewReaderSize(broker.Output(), 4096)
		line, e := r.ReadString('\n')
		if e == nil && strings.TrimSpace(line) != "READY yimebroker-18u-desktop" {
			e = errors.New("unexpected installed Broker readiness")
		}
		ready <- e
		if e == nil {
			_, _ = io.Copy(io.Discard, r)
		}
	}()
	select {
	case err = <-ready:
		if err != nil {
			return fmt.Errorf("installed Broker readiness: %w", err)
		}
	case err = <-brokerExit:
		return fmt.Errorf("installed Broker exited before readiness: %v", err)
	case <-time.After(120 * time.Second):
		return errors.New("installed Broker readiness timed out")
	}
	gui, err := startDesktopDiagnosticChild(start, recorder, ctx, filepath.Join(root, filepath.FromSlash(installed18uhost.FrontendPath)), []string{"--installed-tsf", "--install-root", root, "--manifest-sha256", anchor, "--broker-pid", strconv.Itoa(broker.PID()), "--touch-ui"}, root)
	if err != nil {
		return err
	}
	defer gui.Stop()
	go forwardDiagnosticHealth(ctx, recorder, gui.Input())
	go func() { _, _ = io.Copy(io.Discard, gui.Output()) }()
	guiExit := make(chan error, 1)
	go func() { guiExit <- gui.Wait() }()
	ticker := time.NewTicker(200 * time.Millisecond)
	defer ticker.Stop()
	for {
		select {
		case err = <-guiExit:
			return err
		case err = <-brokerExit:
			return fmt.Errorf("installed Broker exited; keyboard stopped without replay: %v", err)
		case <-ticker.C:
			if stopEvent.Wait(0) {
				return nil
			}
		}
	}
}
