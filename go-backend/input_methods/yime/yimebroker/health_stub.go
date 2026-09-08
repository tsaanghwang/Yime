//go:build !windows

package yimebroker

import (
	"context"
	"errors"
)

type HealthServer struct{}

func StartHealthServer(context.Context, HealthConfig) (*HealthServer, error) {
	return nil, errors.New("Windows health named pipes are unavailable on this platform")
}

func (*HealthServer) Close() error { return nil }
