//go:build !windows || (!amd64 && !arm64)

package tsffrontend

import "errors"

func Dial(pid, thread uint32, window, focus uint64) (*Client, error) {
	return nil, ValidateNativeHost()
}

func ValidateNativeHost() error {
	return errors.New("installed TSF frontend requires native Windows x64 or ARM64")
}
