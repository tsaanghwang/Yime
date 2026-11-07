package main

import (
	"context"
	"fmt"
	"io"
	"os"
	"strings"

	"github.com/tsaanghwang/Yime/go-backend/input_methods/yime/yimebroker"
	"github.com/tsaanghwang/Yime/go-backend/internal/touchbroker"
)

type brokerOptions struct {
	root, data, pipe string
	pid              uint64
}

// The command always supplies the compiled platform and real dependencies.
// This private seam lets offline tests observe startup without opening a pipe.
type brokerDependencies struct {
	native     func() error
	production func(string, string) (*touchbroker.Service, error)
	serve      func(context.Context, yimebroker.NamedPipeConfig, func(context.Context, io.Reader, io.Writer, yimebroker.TrustedClient) error) error
	ready      io.Writer
}

func productionBrokerDependencies() brokerDependencies {
	return brokerDependencies{
		native: requireNativeArchitecture, production: touchbroker.NewProduction,
		serve: yimebroker.ServeNamedPipeHandler, ready: os.Stdout,
	}
}

func runBroker(ctx context.Context, options brokerOptions, goos, goarch string, deps brokerDependencies) error {
	if e := requireBrokerPlatform(goos, goarch); e != nil {
		return e
	}
	const prefix = `\\.\pipe\YimeBroker.18uTouch.v1.`
	if !strings.HasPrefix(options.pipe, prefix) || len(options.pipe) <= len(prefix) || options.pid == 0 || options.pid > 0xffffffff {
		return fmt.Errorf("dedicated endpoint and explicit TIP host PID required")
	}
	if e := deps.native(); e != nil {
		return e
	}
	service, e := deps.production(options.root, options.data)
	if e != nil {
		return e
	}
	// READY retains the existing transport-startup meaning. NewProduction has
	// checked the product/resource descriptor; dictionary bytes are still loaded
	// and checked by the independent first-open contract, not this callback.
	return deps.serve(ctx, yimebroker.NamedPipeConfig{
		Name: options.pipe, MaxConnections: 2, MaxConnectionsPerClient: 2,
		RequireSameLogon: true, ExpectedClientProcessID: uint32(options.pid),
		OnListening: func() { fmt.Fprintln(deps.ready, "READY yimebroker-18u") },
	}, service.ServeConnection)
}
