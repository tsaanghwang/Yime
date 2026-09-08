package main

import (
	"context"
	"errors"
	"sync/atomic"

	"github.com/tsaanghwang/Yime/go-backend/input_methods/yime/yimebroker"
)

func validateHealthPipe(base, health string) error {
	if health == "" {
		return nil
	}
	expected, err := yimebroker.HealthPipeName(base, yimebroker.HealthRoleBroker)
	if err != nil || health != expected {
		return errors.New("health-pipe must be the named-pipe plus its fixed health suffix")
	}
	return nil
}

// Only the named-pipe lifetime is observed. This callback never creates an
// engine, acquires a session/operation slot, or reads learning/configuration.
func serveBrokerPipe(ctx context.Context, dispatcher *yimebroker.Dispatcher, config yimebroker.NamedPipeConfig, healthName string) error {
	if err := validateHealthPipe(config.Name, healthName); err != nil {
		return err
	}
	if healthName == "" {
		return yimebroker.ServeNamedPipe(ctx, dispatcher, config)
	}
	var listening atomic.Bool
	health, err := yimebroker.StartHealthServer(ctx, yimebroker.HealthConfig{
		Name: config.Name, Role: yimebroker.HealthRoleBroker,
		Snapshot: func() yimebroker.HealthSnapshot {
			state := yimebroker.HealthStateStarting
			if listening.Load() {
				state = yimebroker.HealthStateServing
			}
			return yimebroker.HealthSnapshot{State: state}
		},
	})
	if err != nil {
		return err
	}
	defer health.Close()
	config.OnListening = func() { listening.Store(true) }
	config.OnStopped = func() { listening.Store(false) }
	return yimebroker.ServeNamedPipe(ctx, dispatcher, config)
}
