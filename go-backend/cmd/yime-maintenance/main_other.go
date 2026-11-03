//go:build !windows

package main

import "errors"

func maintain(action, planPath, initiatingSID string, elevated bool, parentPID uint, parentStarted uint64) error {
	return errors.New("native Windows maintenance is required")
}
