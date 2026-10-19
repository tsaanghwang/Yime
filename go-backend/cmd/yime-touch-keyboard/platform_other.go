//go:build !windows

package main

import "errors"

func run(options) error { return errors.New("the desktop touch keyboard requires Windows") }

func showError(e error) {}
