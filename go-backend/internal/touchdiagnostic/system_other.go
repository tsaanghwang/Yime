//go:build !windows

package touchdiagnostic

// Unix errno values must not be relabelled as Windows errors by offline tests.
func win32FromError(error) *uint32 { return nil }
