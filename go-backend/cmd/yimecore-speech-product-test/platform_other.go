//go:build !windows

package main

import (
	"errors"
	"os"
	"os/exec"
)

var errForeignPipe = errors.New("Windows-only private named pipe")

type processHandle struct{ evidence processEvidence }

func (*processHandle) alive() bool           { return false }
func (*processHandle) close()                {}
func hideProcess(*exec.Cmd)                  {}
func windowsDirectory() (string, error)      { return "", errForeignPipe }
func actualProfile() (string, string, error) { return "", "", errForeignPipe }
func plainPath(string) error                 { return errForeignPipe }
func bindProcess(uint32, string, uint32, uint64, string) (*processHandle, error) {
	return nil, errForeignPipe
}
func openOwnedPipe(string, uint32) (*os.File, error) { return nil, errForeignPipe }
