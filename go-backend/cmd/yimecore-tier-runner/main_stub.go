//go:build !windows

package main

import "fmt"

func main() {
	fmt.Println("yimecore-tier-runner requires Windows Job Objects")
}
