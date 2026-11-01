//go:build !windows

package yimebroker

import (
	"context"
	"errors"
	"io"
)

type NamedPipeConfig struct {
	ExpectedClientProcessID uint32 // Controlled bootstrap allowlist; never taken from JSON.
	RequireSameLogon        bool
	Name                    string
	MaxConnections          int
	MaxConnectionsPerClient int
	OnConnectionError       func(error)
	OnListening             func()
	OnStopped               func()
}

func ServeNamedPipe(context.Context, *Dispatcher, NamedPipeConfig) error {
	return errors.New("Windows named pipes are unavailable on this platform")
}

func ServeNamedPipeHandler(context.Context, NamedPipeConfig, func(context.Context, io.Reader, io.Writer, TrustedClient) error) error {
	return errors.New("Windows named pipes are unavailable on this platform")
}
