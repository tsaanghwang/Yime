//go:build !windows || !amd64

package tsffrontend

import "errors"

func Dial(pid, thread uint32, window uint64) (*Client, error) {
	return nil, errors.New("installed TSF frontend requires native Windows x64")
}
