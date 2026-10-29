//go:build windows && (amd64 || arm64)

package main

import (
	"fmt"
	"runtime"
	"sync"
	"sync/atomic"
	"syscall"
	"unsafe"
)

type clickSound interface {
	play() bool
	close()
}
type waveFormat struct {
	Tag, Channels           uint16
	Rate, BytesPerSecond    uint32
	BlockAlign, Bits, Extra uint16
}
type waveHeader struct {
	Data             uintptr
	Length, Recorded uint32
	User             uintptr
	Flags, Loops     uint32
	Next, Reserved   uintptr
}
type waveCalls struct {
	open                      func(*uintptr, *waveFormat, uintptr) uint32
	prepare, write, unprepare func(uintptr, *waveHeader) uint32
	reset, close              func(uintptr) uint32
}

var audioKernel = syscall.NewLazyDLL("kernel32.dll")
var audioMM = syscall.NewLazyDLL("winmm.dll")
var audioWait = audioKernel.NewProc("WaitForSingleObject")
var audioCreateEvent = audioKernel.NewProc("CreateEventW")
var audioCloseEvent = audioKernel.NewProc("CloseHandle")
var waveProcedures = map[string]*syscall.LazyProc{
	"waveOutOpen":            audioMM.NewProc("waveOutOpen"),
	"waveOutPrepareHeader":   audioMM.NewProc("waveOutPrepareHeader"),
	"waveOutWrite":           audioMM.NewProc("waveOutWrite"),
	"waveOutReset":           audioMM.NewProc("waveOutReset"),
	"waveOutUnprepareHeader": audioMM.NewProc("waveOutUnprepareHeader"),
	"waveOutClose":           audioMM.NewProc("waveOutClose"),
}

func waveCall(name string, args ...uintptr) uint32 {
	p := waveProcedures[name]
	if p == nil || p.Find() != nil {
		return 1
	}
	r, _, _ := p.Call(args...)
	return uint32(r)
}
func systemWaveCalls() waveCalls {
	header := func(name string) func(uintptr, *waveHeader) uint32 {
		return func(h uintptr, b *waveHeader) uint32 {
			return waveCall(name, h, uintptr(unsafe.Pointer(b)), unsafe.Sizeof(*b))
		}
	}
	return waveCalls{
		open: func(h *uintptr, f *waveFormat, event uintptr) uint32 {
			return waveCall("waveOutOpen", uintptr(unsafe.Pointer(h)), uintptr(^uint32(0)), uintptr(unsafe.Pointer(f)), event, 0, 0x50000)
		},
		prepare: header("waveOutPrepareHeader"), write: header("waveOutWrite"), unprepare: header("waveOutUnprepareHeader"),
		reset: func(h uintptr) uint32 { return waveCall("waveOutReset", h) },
		close: func(h uintptr) uint32 { return waveCall("waveOutClose", h) },
	}
}

type waveBuffer struct {
	header   waveHeader
	data     []byte
	pin      runtime.Pinner
	prepared bool
}
type waveDevice struct {
	handle, event uintptr
	api           waveCalls
	buffers       [3]waveBuffer // Three continuously refilled 10ms PCM buffers.
	once          sync.Once
}

// A driver that refuses cleanup must not retain pointers to freed Go storage.
// Keep its pinned buffers and callback event alive until process exit.
var retainedAudio struct {
	sync.Mutex
	devices []*waveDevice
}

func openWaveDevice(api waveCalls) (*waveDevice, error) {
	d := &waveDevice{api: api}
	d.event, _, _ = audioCreateEvent.Call(0, 0, 0, 0)
	if d.event == 0 {
		return nil, fmt.Errorf("audio event unavailable")
	}
	f := waveFormat{Tag: 1, Channels: 1, Rate: 44100, BytesPerSecond: 88200, BlockAlign: 2, Bits: 16}
	if result := api.open(&d.handle, &f, d.event); result != 0 {
		d.close()
		return nil, fmt.Errorf("waveOutOpen: %d", result)
	}
	for i := range d.buffers {
		b := &d.buffers[i]
		b.data = make([]byte, 882)
		b.header.Data, b.header.Length = uintptr(unsafe.Pointer(&b.data[0])), uint32(len(b.data))
		b.pin.Pin(&b.header)
		b.pin.Pin(&b.data[0])
		if result := api.prepare(d.handle, &b.header); result != 0 {
			d.close()
			return nil, fmt.Errorf("waveOutPrepareHeader: %d", result)
		}
		b.prepared = true
		if result := api.write(d.handle, &b.header); result != 0 {
			d.close()
			return nil, fmt.Errorf("waveOutWrite: %d", result)
		}
	}
	return d, nil
}
func (d *waveDevice) close() {
	d.once.Do(func() {
		safe := true
		if d.handle != 0 {
			if d.api.reset(d.handle) != 0 {
				safe = false
			}
			for i := range d.buffers {
				b := &d.buffers[i]
				if b.prepared && d.api.unprepare(d.handle, &b.header) != 0 {
					safe = false
				}
			}
			if d.api.close(d.handle) != 0 {
				safe = false
			}
		}
		if !safe {
			retainedAudio.Lock()
			retainedAudio.devices = append(retainedAudio.devices, d)
			retainedAudio.Unlock()
			return
		}
		for i := range d.buffers {
			d.buffers[i].pin.Unpin()
		}
		if d.event != 0 {
			audioCloseEvent.Call(d.event)
		}
	})
}

type clickPCM struct {
	data   []byte
	cursor int
}

func newClickPCM() clickPCM {
	data := makeKeyClickWave()[44:]
	return clickPCM{data: data, cursor: len(data)}
}
func (p *clickPCM) fill(dst []byte) { clear(dst); p.cursor += copy(dst, p.data[p.cursor:]) }

type waveClickStream struct {
	device                 *waveDevice
	openDevice             func() (*waveDevice, error)
	kick                   chan struct{}
	stop, done             chan struct{}
	failed, closed         atomic.Bool
	ready                  atomic.Bool
	refills, signalBuffers atomic.Uint64
	failureDetail          atomic.Value
	once                   sync.Once
}

func newWaveClickStream() (clickSound, error) {
	return startWaveClickStream(func() (*waveDevice, error) { return openWaveDevice(systemWaveCalls()) }), nil
}
func startWaveClickStream(open func() (*waveDevice, error)) *waveClickStream {
	p := &waveClickStream{openDevice: open, kick: make(chan struct{}, 1), stop: make(chan struct{}), done: make(chan struct{})}
	go p.pump()
	return p
}
func (p *waveClickStream) play() bool {
	if p.closed.Load() || p.failed.Load() {
		return false
	}
	select {
	case p.kick <- struct{}{}:
	default:
	} // Do not accumulate delayed clicks.
	return true
}
func (p *waveClickStream) close() {
	p.once.Do(func() { p.closed.Store(true); close(p.stop) })
}
func (p *waveClickStream) shutdownDone() <-chan struct{} { return p.done }
func (p *waveClickStream) playbackFailed() bool          { return p.failed.Load() }
func (p *waveClickStream) diagnostics() map[string]any {
	result := map[string]any{"ready": p.ready.Load(), "failed": p.failed.Load(), "closed": p.closed.Load(), "refills": p.refills.Load(), "signalBuffers": p.signalBuffers.Load()}
	if detail := p.failureDetail.Load(); detail != nil {
		result["error"] = detail
	}
	return result
}
func (p *waveClickStream) pump() {
	// All driver calls belong to this worker, never the window thread. A driver
	// can stall in open/reset/close; the UI must still minimize, restore or exit.
	runtime.LockOSThread()
	defer runtime.UnlockOSThread()
	defer close(p.done)
	select {
	case <-p.stop:
		if p.device != nil {
			p.device.close()
		}
		return
	default:
	}
	if p.device == nil {
		d, err := p.openDevice()
		if err != nil {
			p.failureDetail.Store(err.Error())
			p.failed.Store(true)
			return
		}
		p.device = d
	}
	defer p.device.close()
	p.ready.Store(true)
	pcm := newClickPCM()
	for {
		select {
		case <-p.stop:
			return
		default:
		}
		select {
		case <-p.kick:
			pcm.cursor = 0
		default:
		}
		for i := range p.device.buffers {
			b := &p.device.buffers[i]
			if b.header.Flags&1 == 0 {
				continue
			} // WHDR_DONE: driver returned ownership.
			signal := pcm.cursor < len(pcm.data)
			pcm.fill(b.data)
			if result := p.device.api.write(p.device.handle, &b.header); result != 0 {
				p.failureDetail.Store(fmt.Sprintf("waveOutWrite: %d", result))
				p.failed.Store(true)
				return
			}
			p.refills.Add(1)
			if signal {
				p.signalBuffers.Add(1)
			}
		}
		result, _, _ := audioWait.Call(p.device.event, 20)
		if result == 0xffffffff {
			p.failureDetail.Store("audio callback wait failed")
			p.failed.Store(true)
			return
		}
	}
}
