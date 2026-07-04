//go:build !windows

package yime

func newNativeBackend() rimeBackend {
	return nil
}
