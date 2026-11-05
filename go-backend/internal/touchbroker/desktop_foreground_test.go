package touchbroker

import "testing"

func TestDesktopForegroundBindsFocusedControl(t *testing.T) {
	// The focused editor belongs to the TIP thread. The top-level thread is
	// deliberately not a lease condition; only its window and PID are needed.
	current := desktopForegroundSnapshot{Window: 10, Focus: 11, Root: 10, FinalWindow: 10, WindowPID: 30, FocusPID: 30, FocusThread: 20}
	if !matchesDesktopForeground(30, 10, 11, 20, current) {
		t.Fatal("focused child control was rejected")
	}
	for _, name := range []string{"window", "focus", "root", "foreground-race", "window-process", "focus-process", "focus-thread"} {
		t.Run(name, func(t *testing.T) {
			changed := current
			switch name {
			case "window":
				changed.Window++
			case "focus":
				changed.Focus++ // Another control in the same process and thread.
			case "root":
				changed.Root++
			case "foreground-race":
				changed.FinalWindow++
			case "window-process":
				changed.WindowPID++
			case "focus-process":
				changed.FocusPID++
			case "focus-thread":
				changed.FocusThread++
			}
			if matchesDesktopForeground(30, 10, 11, 20, changed) {
				t.Fatal("changed target accepted")
			}
		})
	}
	if matchesDesktopForeground(0, 10, 11, 20, current) || matchesDesktopForeground(30, 0, 11, 20, current) ||
		matchesDesktopForeground(30, 10, 0, 20, current) || matchesDesktopForeground(30, 10, 11, 0, current) ||
		matchesDesktopForeground(30, 10, 11, 20, desktopForegroundSnapshot{}) {
		t.Fatal("incomplete foreground observation accepted")
	}
}
