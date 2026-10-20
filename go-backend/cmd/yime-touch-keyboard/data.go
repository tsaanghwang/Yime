package main

import (
	"encoding/json"
	"errors"
	"fmt"
	"os"

	"github.com/tsaanghwang/Yime/go-backend/internal/keyboardlab"
)

// checkData exercises the same runtime that serves the browser, inside this
// process. It creates no window, performs no OS input and never chooses a host.
func checkData(o options) (err error) {
	if o.DataDir == "" || o.Smoke || o.Shot != "" {
		return errors.New("--check-data requires an explicit --data-dir and cannot be combined with --self-test or --screenshot")
	}
	board, err := load(o)
	if err != nil {
		return err
	}
	runtime, err := keyboardlab.OpenRuntime(o.Root, o.DataDir)
	if err != nil {
		return err
	}
	defer func() { err = errors.Join(err, runtime.Close()) }()
	for _, mode := range keyboardlab.Modes() {
		reply := runtime.Sessions.Open(mode, runtime.LayoutID)
		state, decodeErr := reply.Decode()
		if decodeErr != nil || reply.Status != 200 || !state.OK {
			return fmt.Errorf("open %s in-process session: %s", mode, reply.Body)
		}
		for i, kind := range []string{"clear", "close"} {
			reply = runtime.Sessions.Dispatch(keyboardlab.Event{SessionID: state.SessionID, EventID: fmt.Sprintf("check-%d", i), BaseRevision: state.Revision, Type: kind})
			state, decodeErr = reply.Decode()
			if decodeErr != nil || reply.Status != 200 || !state.OK || state.Commit != "" || state.State.RawInput != "" {
				return fmt.Errorf("%s %s in-process session: %s", kind, mode, reply.Body)
			}
		}
	}
	// Close and verify cleanup before emitting a successful diagnostic report.
	if err := runtime.Close(); err != nil {
		return err
	}
	report := map[string]any{
		"scope": "desktop-in-process-data-check", "layoutId": runtime.LayoutID,
		"inputPolicy": keyboardlab.InputPolicy, "indexes": runtime.Builds,
		"boardWidthU": board.Bounds.Width, "keyCount": len(board.Keys),
		"desktopChineseUI": false, "hostInputSent": false, "hardwareAcceptance": false,
	}
	body, err := json.MarshalIndent(report, "", "  ")
	if err != nil {
		return err
	}
	body = append(body, '\n')
	if o.DataReport != "" {
		return os.WriteFile(o.DataReport, body, 0600)
	}
	_, err = os.Stdout.Write(body)
	return err
}
