//go:build windows && (amd64 || arm64)

package main

import (
	"context"
	"github.com/tsaanghwang/Yime/go-backend/internal/installed18uhost"
	"github.com/tsaanghwang/Yime/go-backend/internal/touchdiagnostic"
	"io"
)

// Shared by the normal installed entry and its real child-process tests.
func startDesktopDiagnosticChild(start installed18uhost.StartFunc, recorder *touchdiagnostic.Recorder, ctx context.Context, path string, args []string, dir string) (installed18uhost.Child, error) {
	return start(ctx, path, args, dir, recorder.Stream())
}

// The status writer is independent of stderr draining. Closing the child input
// releases a blocked write. There is no input command or retry on this channel.
func forwardDiagnosticHealth(ctx context.Context, recorder *touchdiagnostic.Recorder, output io.Writer) {
	for {
		if touchdiagnostic.WriteHealth(output, recorder.Health()) != nil {
			return
		}
		select {
		case <-ctx.Done():
			return
		case <-recorder.Changed():
		}
	}
}
