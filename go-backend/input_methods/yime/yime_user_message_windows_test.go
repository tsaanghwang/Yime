//go:build windows

package yime

func init() {
	showUserMessageBox = func(string, string, string) {}
}
