//go:build !windows || (!amd64 && !arm64)

package main

import "errors"

func runInstalled18uCheck(root, anchor, evidence, confirm string) error {
	return errors.New("installed 18u verification requires native x64 or ARM64 Windows")
}
func runInstalled18uDesktop(root, anchor string, stop bool) error {
	return errors.New("installed 18u desktop requires native x64 or ARM64 Windows")
}
