//go:build !windows

package yime

func (ime *IME) lexiconPromotionScanToolPath() string { return "" }
