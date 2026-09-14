//go:build windows

package main

import (
	"os"
	"testing"
	"time"
)

func TestRuntimeJobKillsAssignedChildWhenOwnerCloses(t *testing.T) {
	if os.Getenv("YIME_RUNTIME_JOB_HELPER") == "1" {
		for {
			time.Sleep(time.Second)
		}
	}
	job, err := createChildProcessJob()
	if err != nil {
		t.Fatal(err)
	}
	previous := os.Getenv("YIME_RUNTIME_JOB_HELPER")
	if err := os.Setenv("YIME_RUNTIME_JOB_HELPER", "1"); err != nil {
		job.Close()
		t.Fatal(err)
	}
	defer os.Setenv("YIME_RUNTIME_JOB_HELPER", previous)
	output, err := os.OpenFile(os.DevNull, os.O_WRONLY, 0)
	if err != nil {
		job.Close()
		t.Fatal(err)
	}
	defer output.Close()
	process, err := startProcessInJob(os.Args[0], []string{"-test.run=TestRuntimeJobKillsAssignedChildWhenOwnerCloses"}, output, job)
	if err != nil {
		job.Close()
		t.Fatal(err)
	}
	if err := job.Close(); err != nil {
		t.Fatal(err)
	}
	done := make(chan error, 1)
	go func() { done <- process.Wait() }()
	select {
	case <-done:
	case <-time.After(5 * time.Second):
		_ = process.Kill()
		t.Fatal("closing the runtime Job Object did not terminate its child")
	}
}
