//go:build !windows || !amd64

package main
func nativeJobGate()bool{return false}
