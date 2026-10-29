//go:build windows && (amd64 || arm64)

package main

import (
	"bytes"
	"errors"
	"testing"
	"time"
	"unsafe"

	tk "github.com/tsaanghwang/Yime/go-backend/internal/touchkeyboard"
)

func TestClickPCMRetainsWaveAcrossReturnedBuffers(t *testing.T) {
	p := newClickPCM()
	block := make([]byte, 882)
	p.fill(block)
	if !bytes.Equal(block, make([]byte, 882)) {
		t.Fatal("idle stream is not silent")
	}
	p.cursor = 0
	var got []byte
	for i := 0; i < 3; i++ {
		p.fill(block)
		got = append(got, block...)
	}
	want := makeKeyClickWave()[44:]
	if !bytes.Equal(got[:len(want)], want) || !bytes.Equal(got[len(want):], make([]byte, len(got)-len(want))) {
		t.Fatal("buffer boundaries lost/duplicated click samples")
	}
	p.cursor = 0
	p.fill(block)
	first := append([]byte(nil), block...)
	p.cursor = 0
	p.fill(block)
	if !bytes.Equal(block, first) {
		t.Fatal("new onset queued behind an old tail")
	}
}

func TestWaveOutHeaderABI(t *testing.T) {
	if unsafe.Sizeof(waveHeader{}) != 48 || unsafe.Offsetof(waveHeader{}.Flags) != 24 || unsafe.Offsetof(waveFormat{}.Extra) != 16 {
		t.Fatal("Windows wave ABI mismatch")
	}
}

func fakeWaveCalls(t *testing.T, failPrepare int, failReset bool) (waveCalls, *int) {
	t.Helper()
	var headers []*waveHeader
	prepared := 0
	reset := false
	closes := new(int)
	return waveCalls{
		open: func(h *uintptr, f *waveFormat, event uintptr) uint32 {
			if f.Rate != 44100 || f.Channels != 1 || f.Bits != 16 || f.BlockAlign != 2 || event == 0 {
				t.Fatal("invalid stream format/event")
			}
			*h = 42
			return 0
		},
		prepare: func(_ uintptr, h *waveHeader) uint32 {
			prepared++
			if prepared == failPrepare {
				return 1
			}
			if h.Flags != 0 || h.Length != 882 || h.Data == 0 {
				t.Fatal("invalid initial buffer")
			}
			headers = append(headers, h)
			h.Flags = 2
			return 0
		},
		write: func(_ uintptr, h *waveHeader) uint32 {
			if h.Flags&2 == 0 {
				t.Fatal("unprepared buffer queued")
			}
			h.Flags = 0x12
			return 0
		},
		reset: func(uintptr) uint32 {
			reset = true
			for _, h := range headers {
				h.Flags = 3
			}
			if failReset {
				return 1
			}
			return 0
		},
		unprepare: func(_ uintptr, h *waveHeader) uint32 {
			if !reset || h.Flags&1 == 0 {
				t.Fatal("buffer released before reset returned ownership")
			}
			return 0
		},
		close: func(uintptr) uint32 { *closes++; return 0 },
	}, closes
}

func TestWaveDeviceCleanupOnSuccessAndPartialPreparation(t *testing.T) {
	for _, failure := range []int{0, 2} {
		api, closes := fakeWaveCalls(t, failure, false)
		d, err := openWaveDevice(api)
		if failure == 0 {
			if err != nil {
				t.Fatal(err)
			}
			d.close()
			d.close()
		} else if err == nil {
			t.Fatal("partial prepare failure accepted")
		}
		if *closes != 1 {
			t.Fatal("device leaked or closed twice", *closes)
		}
	}
}

func TestWaveDeviceRetainsStorageWhenDriverRejectsCleanup(t *testing.T) {
	retainedAudio.Lock()
	before := len(retainedAudio.devices)
	retainedAudio.Unlock()
	api, _ := fakeWaveCalls(t, 0, true)
	d, err := openWaveDevice(api)
	if err != nil {
		t.Fatal(err)
	}
	d.close()
	retainedAudio.Lock()
	after := len(retainedAudio.devices)
	retainedAudio.Unlock()
	if after != before+1 {
		t.Fatal("driver-owned pinned buffers were released")
	}
}

type fakeClickStream struct{ plays, closes int }

func (s *fakeClickStream) play() bool { s.plays++; return true }
func (s *fakeClickStream) close()     { s.closes++ }

func TestSoundStreamReusedAndMuteClosesIt(t *testing.T) {
	a := previewUI(t)
	streams := []*fakeClickStream{}
	a.soundFactory = func() (clickSound, error) { s := &fakeClickStream{}; streams = append(streams, s); return s, nil }
	a.o.KeySound = "click"
	a.clickFeedback()
	a.clickFeedback()
	if len(streams) != 1 || streams[0].plays != 2 {
		t.Fatal("sound device reopened for each key")
	}
	a.down(1, 920, 130)
	a.up(1, 920, 130)
	a.clickFeedback()
	if a.o.KeySound != "off" || streams[0].closes != 1 || streams[0].plays != 2 {
		t.Fatal("mute left audio requests/device alive")
	}
	a.stopKeySound()
	if streams[0].closes != 1 {
		t.Fatal("duplicate close")
	}
}

func TestSoundOpenFailureDoesNotDisableInput(t *testing.T) {
	a := previewUI(t)
	a.o.KeySound = "click"
	a.soundFactory = func() (clickSound, error) { return nil, errors.New("device unavailable") }
	x, y := previewKeyPoint(t, a, func(_ tk.Key, v tk.View) bool { return v.Action.Type == "input" && v.Action.ASCII == "a" })
	a.down(1, x, y)
	a.up(1, x, y)
	if !a.soundUnavailable || a.preview.fault || a.preview.snapshot.State.RawInput != "a" {
		t.Fatal("audio failure broke input session")
	}
}

func TestAudioQueueFailureStopsWorkerAndReleasesBuffers(t *testing.T) {
	api, closes := fakeWaveCalls(t, 0, false)
	write := api.write
	writes := 0
	api.write = func(h uintptr, b *waveHeader) uint32 {
		writes++
		if writes == 4 {
			return 1
		}
		return write(h, b)
	}
	d, err := openWaveDevice(api)
	if err != nil {
		t.Fatal(err)
	}
	d.buffers[0].header.Flags = 3
	p := &waveClickStream{device: d, kick: make(chan struct{}, 1), stop: make(chan struct{}), done: make(chan struct{})}
	go p.pump()
	select {
	case <-p.done:
	case <-time.After(time.Second):
		t.Fatal("failed audio worker did not stop")
	}
	if !p.failed.Load() || p.play() || *closes != 1 {
		t.Fatal("failed queue remained available or leaked device")
	}
	p.close()
}

// A stalled audio driver must never hold the window thread in minimize/exit.
func TestAudioShutdownDoesNotWaitForDriver(t *testing.T) {
	api, _ := fakeWaveCalls(t, 0, false)
	reset := api.reset
	entered, release := make(chan struct{}), make(chan struct{})
	api.reset = func(h uintptr) uint32 { close(entered); <-release; return reset(h) }
	d, err := openWaveDevice(api)
	if err != nil {
		t.Fatal(err)
	}
	p := &waveClickStream{device: d, kick: make(chan struct{}, 1), stop: make(chan struct{}), done: make(chan struct{})}
	go p.pump()
	a := previewUI(t)
	a.soundStream = p
	returned := make(chan struct{})
	go func() { a.suspendForMinimize(); close(returned) }()
	select {
	case <-entered:
	case <-time.After(time.Second):
		close(release)
		t.Fatal("audio reset never started")
	}
	responsive := false
	select {
	case <-returned:
		responsive = true
	case <-time.After(150 * time.Millisecond):
	}
	if responsive {
		a.o.KeySound = "click"
		a.soundFactory = func() (clickSound, error) {
			t.Error("opened another device while reset was stalled")
			return &fakeClickStream{}, nil
		}
		if a.ensureKeySound() {
			t.Error("stalled audio allowed another stream")
		}
		a.stopKeySound() // Reentrant WM_SIZE / close must also return immediately.
	}
	close(release)
	select {
	case <-p.done:
	case <-time.After(time.Second):
		t.Fatal("released driver did not finish cleanup")
	}
	<-returned
	if !responsive {
		t.Fatal("minimize blocked waiting for audio driver reset")
	}
	if a.soundStream != nil || p.play() {
		t.Fatal("minimized audio still accepts clicks")
	}
	if responsive {
		replacement := &fakeClickStream{}
		a.soundFactory = func() (clickSound, error) { return replacement, nil }
		a.soundSuspended = false // Restored window; minimized windows stay silent.
		a.clickFeedback()
		if replacement.plays != 1 {
			t.Fatal("sound did not recover after cleanup completed")
		}
		a.stopKeySound()
	}
}

func TestAudioOpenDoesNotBlockWindowOrCreateMoreWorkers(t *testing.T) {
	entered, release := make(chan struct{}), make(chan struct{})
	p := startWaveClickStream(func() (*waveDevice, error) {
		close(entered)
		<-release
		return nil, errors.New("blocked test device failed to open")
	})
	<-entered
	a := previewUI(t)
	a.o.KeySound, a.soundStream = "click", p
	a.stopKeySound()
	p.close() // Idempotent while still opening.
	for i := 0; i < 20; i++ {
		if a.ensureKeySound() {
			t.Error("opening driver spawned another stream")
		}
	}
	close(release)
	select {
	case <-p.done:
	case <-time.After(time.Second):
		t.Fatal("released opener did not stop")
	}
	if !p.failed.Load() || p.play() {
		t.Fatal("failed/cancelled opener accepted audio")
	}
}
