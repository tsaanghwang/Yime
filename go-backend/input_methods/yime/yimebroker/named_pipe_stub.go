//go:build !windows

package yimebroker

import (
	"context"
	"errors"
)

type NamedPipeConfig struct {
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
