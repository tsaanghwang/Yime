//go:build !windows

package main

import "errors"

func maintain(action, planPath, initiatingSID string, elevated bool) error {
	return errors.New("native Windows maintenance is required")
}
