package touchbroker

// A desktop lease names the actual focused control, whose thread may differ
// from the foreground top-level window's thread (for example, tabbed hosts).
// Keep both windows and their process owners: accepting only a matching PID
// would let an old lease follow a different control in the same application.
type desktopForegroundSnapshot struct {
	Window, Focus, Root, FinalWindow uint64
	WindowPID, FocusPID, FocusThread uint32
}

func matchesDesktopForeground(pid uint32, window, focus uint64, thread uint32, current desktopForegroundSnapshot) bool {
	return pid != 0 && window != 0 && focus != 0 && thread != 0 &&
		current.Window == window && current.FinalWindow == window &&
		current.Focus == focus && current.Root == window &&
		current.WindowPID == pid && current.FocusPID == pid && current.FocusThread == thread
}
