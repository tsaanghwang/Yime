//go:build !windows

package touchbroker

import (
	"context"
	"errors"
)

func ServeDesktop(context.Context, string, string, func()) error {
	return errors.New("Windows required")
}
