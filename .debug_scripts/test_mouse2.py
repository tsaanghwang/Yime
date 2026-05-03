import ctypes
from ctypes import wintypes
class POINT(ctypes.Structure):
    _fields_ = [("x", ctypes.c_long), ("y", ctypes.c_long)]
pt = POINT()
ctypes.windll.user32.GetCursorPos(ctypes.byref(pt))
print(pt.x, pt.y)
