//go:build !windows

package yime

func (ime *IME) MaintenanceReadiness() (bool, string) { return false, "" }
