import ctypes
from ctypes import wintypes

user32 = ctypes.WinDLL("user32", use_last_error=True)
hwnd = user32.GetForegroundWindow()
text_len = user32.GetWindowTextLengthW(hwnd)
buffer = ctypes.create_unicode_buffer(text_len + 1)
user32.GetWindowTextW(hwnd, buffer, text_len + 1)
print("Title:", buffer.value)

class_buffer = ctypes.create_unicode_buffer(256)
user32.GetClassNameW(hwnd, class_buffer, 256)
print("Class:", class_buffer.value)
