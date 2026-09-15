//go:build !windows

package main

import "github.com/tsaanghwang/Yime/go-backend/input_methods/yime/speechruntime"

func packagePlainPath(path string) error { return speechruntime.PlainPath(path) }
