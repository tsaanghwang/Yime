//go:build !windows || !amd64
package main
import "errors"
func runInstalled18uCheck(root,anchor,evidence,confirm string)error{return errors.New("installed 18u verification requires native x64 Windows")}
