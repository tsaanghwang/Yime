//go:build !windows

package yime

func platformInputToolbarVisible() bool {
	return false
}

func platformToggleInputToolbar(*IME) error {
	return nil
}
