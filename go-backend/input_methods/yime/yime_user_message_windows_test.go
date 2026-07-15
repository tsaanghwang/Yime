//go:build windows

package yime

import "testing"

func init() {
	showUserMessageBox = func(string, string, string) {}
}

func TestMaintenanceDialogsStayVisibleAndDefaultToCancel(t *testing.T) {
	if maintenanceDialogVisibilityFlags&mbSetForeground == 0 || maintenanceDialogVisibilityFlags&mbTopmost == 0 {
		t.Fatalf("maintenance dialogs must be foreground and topmost: flags=%#x", maintenanceDialogVisibilityFlags)
	}
	if mbDefaultButton2 != 0x100 {
		t.Fatalf("maintenance confirmation must default to Cancel, got %#x", mbDefaultButton2)
	}
}
