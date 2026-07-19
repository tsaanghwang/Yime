//go:build !windows

package main

import "fmt"

func runGraphical(args []string) error {
	return fmt.Errorf("图形界面仅支持 Windows；请使用命令行子命令")
}
