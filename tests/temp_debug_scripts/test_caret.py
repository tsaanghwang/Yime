import ctypes
from ctypes import wintypes
import time

user32 = ctypes.WinDLL("user32", use_last_error=True)
class GUITHREADINFO(ctypes.Structure):
    _fields_ = [
        ("cbSize", wintypes.DWORD),
        ("flags", wintypes.DWORD),
        ("hwndActive", wintypes.HWND),
        ("hwndFocus", wintypes.HWND),
        ("hwndCapture", wintypes.HWND),
        ("hwndMenuOwner", wintypes.HWND),
        ("hwndMoveSize", wintypes.HWND),
        ("hwndCaret", wintypes.HWND),
        ("rcCaret", wintypes.RECT),
    ]

time.sleep(3)
hwnd = user32.GetForegroundWindow()
tid = user32.GetWindowThreadProcessId(hwnd, None)
gui = GUITHREADINFO(cbSize=ctypes.sizeof(GUITHREADINFO))
user32.GetGUIThreadInfo(tid, ctypes.byref(gui))

print("Focus:", gui.hwndFocus)
print("Caret:", gui.hwndCaret)
print("rcCaret:", gui.rcCaret.left, gui.rcCaret.top, gui.rcCaret.right, gui.rcCaret.bottom)
