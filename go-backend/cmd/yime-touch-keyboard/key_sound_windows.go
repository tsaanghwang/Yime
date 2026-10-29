//go:build windows && (amd64 || arm64)

package main

import (
	tk "github.com/tsaanghwang/Yime/go-backend/internal/touchkeyboard"
	"time"
)

const wmKeySoundReady = 0x8041
const keySoundTimer = 0x5949

func (a *ui) soundAllowed() bool {
	return a.o.KeySound == "click" && !a.soundSuspended && a.o.Shot == "" && !a.o.Smoke && !a.o.HostSmoke
}

func (a *ui) ensureKeySound() bool {
	if !a.soundAllowed() {
		return false
	}
	if a.soundPlayer != nil {
		return true
	}
	if a.soundStream != nil {
		if status, ok := a.soundStream.(interface{ playbackFailed() bool }); ok && status.playbackFailed() {
			a.stopKeySound()
			a.soundUnavailable = true
			a.soundRetryAfter = time.Now().Add(time.Second)
		}
	}
	if a.soundWindowReady && a.h != 0 && !a.soundTimerActive {
		id, _, _ := U("SetTimer").Call(a.h, keySoundTimer, 250, 0)
		a.soundTimerActive = id != 0
	}
	if a.soundStream != nil {
		return true
	}
	if a.soundRetiring != nil {
		select {
		case <-a.soundRetiring:
			a.soundRetiring = nil
		default:
			// Do not open more streams while a stalled driver still owns one.
			return false
		}
	}
	if time.Now().Before(a.soundRetryAfter) {
		return false
	}
	factory := a.soundFactory
	if factory == nil {
		factory = newWaveClickStream
	}
	stream, err := factory()
	if err != nil {
		a.soundUnavailable = true
		a.soundRetryAfter = time.Now().Add(time.Second)
		return false
	}
	a.soundStream = stream
	return true
}

func (a *ui) stopKeySound() {
	if a.soundTimerActive {
		U("KillTimer").Call(a.h, keySoundTimer)
		a.soundTimerActive = false
	}
	if a.soundStream != nil {
		stream := a.soundStream
		a.soundStream = nil
		if draining, ok := stream.(interface{ shutdownDone() <-chan struct{} }); ok {
			a.soundRetiring = draining.shutdownDone()
		}
		stream.close()
	}
}

func (a *ui) clickFeedback() {
	if !a.soundAllowed() {
		return
	}
	if a.soundPlayer != nil {
		a.soundUnavailable = !a.soundPlayer()
		return
	}
	if a.ensureKeySound() {
		a.soundUnavailable = !a.soundStream.play()
	}
}

func localKeyState(s *tk.State) [6]bool {
	return [6]bool{s.Shift, s.Ctrl, s.Alt, s.Original, s.Number["left"], s.Number["right"]}
}
