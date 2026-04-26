import ctypes
import time

user32 = ctypes.windll.user32
imm32 = ctypes.windll.imm32

print("Switch to a window, toggle Chinese IME, and wait...")
for _ in range(10):
    time.sleep(1)
    hwnd = user32.GetForegroundWindow()
    thread_id = user32.GetWindowThreadProcessId(hwnd, None)
    hkl = user32.GetKeyboardLayout(thread_id)
    language_id = hkl & 0xFFFF
    
    himc = imm32.ImmGetContext(hwnd)
    is_open = False
    if himc:
        is_open = imm32.ImmGetOpenStatus(himc)
        imm32.ImmReleaseContext(hwnd, himc)
        
    print(f"HKL: {hex(hkl)}, Lang: {hex(language_id)}, IME Open: {bool(is_open)}")
