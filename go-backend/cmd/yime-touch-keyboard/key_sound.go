package main

import (
	"encoding/binary"
	"math"
)

// A short, quiet decaying impact, synthesized locally rather than read from a
// user path or a system sound scheme. PCM peak stays below full scale.
func makeKeyClickWave() []byte {
	const rate, frames = 44100, 1058 // 24ms, mono signed 16-bit PCM.
	wave := make([]byte, 44+frames*2)
	copy(wave, "RIFF")
	binary.LittleEndian.PutUint32(wave[4:], uint32(len(wave)-8))
	copy(wave[8:], "WAVEfmt ")
	binary.LittleEndian.PutUint32(wave[16:], 16)
	binary.LittleEndian.PutUint16(wave[20:], 1)
	binary.LittleEndian.PutUint16(wave[22:], 1)
	binary.LittleEndian.PutUint32(wave[24:], rate)
	binary.LittleEndian.PutUint32(wave[28:], rate*2)
	binary.LittleEndian.PutUint16(wave[32:], 2)
	binary.LittleEndian.PutUint16(wave[34:], 16)
	copy(wave[36:], "data")
	binary.LittleEndian.PutUint32(wave[40:], frames*2)
	noise := uint32(0x79696d65)
	for i := 0; i < frames; i++ {
		noise = noise*1664525 + 1013904223
		n := float64(noise>>8)/float64(1<<23) - 1
		t := float64(i) / rate
		attack := math.Min(1, float64(i)/44)
		taper := 1 - float64(i)/float64(frames-1)
		sample := 3 * attack * taper * (0.13*n*math.Exp(-350*t) +
			0.075*math.Sin(2*math.Pi*1800*t)*math.Exp(-240*t) +
			0.045*math.Sin(2*math.Pi*650*t)*math.Exp(-120*t))
		binary.LittleEndian.PutUint16(wave[44+i*2:], uint16(int16(sample*32767)))
	}
	return wave
}
