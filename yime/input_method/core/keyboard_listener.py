"""键盘监听模块。"""

import ctypes
import threading
import time
from typing import Any, Callable, Dict, Optional


# 尝试导入pywin32
try:
    import win32con
    import win32api
    import win32gui
    import win32event
    import win32clipboard
    import win32process
    import win32console
    import win32ui
    import win32file
    import win32com
    import win32com.client
    import win32com.server
    import win32com.shell
    import win32com.shell.shell
    import win32com.shell.shellcon
    import win32com.taskscheduler
    import win32timezone
    import win32evtlog
    import win32evtlogutil
    import win32evtlog
    import win32evtlogutil
    import win32security
    import win32ts
    import win32wnet
    import pythoncom
    HAS_WIN32 = True
except ImportError:
    HAS_WIN32 = False

# 尝试导入pyHook
try:
    import pyHook
    HAS_PYHOOK = True
except ImportError:
    HAS_PYHOOK = False

# 尝试导入pynput
try:
    from pynput import keyboard
    HAS_PYPUT = True
except ImportError:
    HAS_PYPUT = False


class KeyboardListener:
    """
    键盘监听器

    支持两种监听方式：
    1. pyHook - Windows全局钩子（推荐）
    2. pynput - 跨平台监听（备选）
    """

    _SPECIAL_VK_NAMES = {
        0x08: "Backspace",
        0x09: "Tab",
        0x0D: "Return",
        0x1B: "Escape",
        0x20: "Space",
        0x25: "Left",
        0x26: "Up",
        0x27: "Right",
        0x28: "Down",
        0x2E: "Delete",
    }

    _OEM_CHAR_BY_VK = {
        0xBA: ";",
        0xBB: "=",
        0xBC: ",",
        0xBD: "-",
        0xBE: ".",
        0xBF: "/",
        0xC0: "`",
        0xDB: "[",
        0xDC: "\\",
        0xDD: "]",
        0xDE: "'",
    }

    _MODIFIER_VK_CODES = {
        "shift": (0x10,),
        "ctrl": (0x11,),
        "alt": (0x12,),
        "alt_r": (0xA5,),
        "win": (0x5B, 0x5C),
    }

    def __init__(
        self,
        on_key_press: Callable[[Dict[str, Any]], bool],
        on_key_release: Optional[Callable[[Dict[str, Any]], bool]] = None,
    ) -> None:
        """
        初始化键盘监听器

        Args:
            on_key_press: 按键回调函数，返回True继续传递，False拦截
            on_key_release: 释放键回调函数（可选）
        """
        self.on_key_press = on_key_press
        self.on_key_release = on_key_release
        self.is_running = False
        self._listener = None
        self._backend = None
        self._win32_hook = None
        self._win32_callback = None
        self._win32_ready = threading.Event()
        self._win32_error: Optional[str] = None
        self._win32_hook_installed = False
        self._win32_thread_id: Optional[int] = None

        # 检查可用的监听方式
        if not HAS_WIN32 and not HAS_PYHOOK and not HAS_PYPUT:
            raise RuntimeError(
                "需要安装 pywin32、pyHook 或 pynput。\n"
                "安装方法：\n"
                "  pip install pywin32\n"
                "  或\n"
                "  pip install pyHook-1.5.1-cp310-cp310-win_amd64.whl\n"
                "  或\n"
                "  pip install pynput"
            )

        self._select_backend()

    def _select_backend(self) -> None:
        """按优先级选择可用监听后端。"""
        if HAS_WIN32:
            print("使用 pywin32 进行全局键盘钩子监听")
            try:
                self._init_win32hook()
                self._backend = "win32"
                return
            except Exception as exc:
                print(f"[Win32Hook] 安装失败: {exc}")

        if HAS_PYHOOK:
            print("使用 pyHook 进行键盘监听")
            self._init_pyhook()
            self._backend = "pyhook"
            return

        if HAS_PYPUT:
            print("Win32键盘钩子安装失败，将回退到 pynput 监听")
            self._init_pynput()
            self._backend = "pynput"
            return

        raise RuntimeError("没有可用的键盘监听后端")

    def _init_win32hook(self) -> None:
        """使用 pywin32 初始化全局键盘钩子"""
        self._win32_ready.clear()
        self._win32_error = None
        self._win32_hook_installed = False
        self._win32_thread = threading.Thread(
            target=self._run_win32_message_loop,
            daemon=True,
        )
        self._win32_thread.start()
        self._win32_ready.wait(timeout=1.0)
        if not self._win32_hook_installed:
            raise RuntimeError(self._win32_error or "未知错误")

    def _run_win32_message_loop(self) -> None:
        try:
            self._win32_message_loop()
        except Exception as exc:
            self._win32_error = str(exc)
            self._win32_ready.set()

    def _normalize_win32_key_info(
        self,
        vk_code: int,
        scan_code: int,
        flags: int,
        modifiers: Dict[str, bool],
        resolve_key_name: Callable[[int, int, int], str],
        resolve_text: Callable[[int, int, Dict[str, bool]], str],
    ) -> Dict[str, Any]:
        key_name = self._SPECIAL_VK_NAMES.get(vk_code)
        ascii_code: Optional[int] = None
        text_value = resolve_text(vk_code, scan_code, modifiers)

        if key_name is None and 0x30 <= vk_code <= 0x39:
            key_name = chr(vk_code)
            ascii_code = vk_code
        elif key_name is None and 0x41 <= vk_code <= 0x5A:
            key_name = chr(vk_code + 32)
            ascii_code = ord(key_name)
        elif key_name is None and vk_code in self._OEM_CHAR_BY_VK:
            key_name = self._OEM_CHAR_BY_VK[vk_code]
            ascii_code = ord(key_name)
        elif key_name == "Space":
            ascii_code = ord(" ")

        if key_name is None:
            key_name = resolve_key_name(vk_code, scan_code, flags)

        if text_value and len(text_value) == 1:
            ascii_code = ord(text_value)

        return {
            "key": key_name,
            "text": text_value,
            "ascii": ascii_code,
            "scan_code": scan_code,
            "vk_code": vk_code,
            "flags": flags,
            "modifiers": modifiers,
            "is_injected": bool(flags & 0x10),
            "time": time.time(),
        }

    def _win32_message_loop(self):
        import ctypes.wintypes as wintypes
        import win32con

        user32 = ctypes.WinDLL("user32", use_last_error=True)
        kernel32 = ctypes.WinDLL("kernel32", use_last_error=True)

        lresult_type = getattr(wintypes, "LRESULT", ctypes.c_ssize_t)
        ulong_ptr_type = getattr(wintypes, "ULONG_PTR", ctypes.c_size_t)

        hook_proc_type = ctypes.WINFUNCTYPE(
            lresult_type,
            ctypes.c_int,
            wintypes.WPARAM,
            wintypes.LPARAM,
        )

        kernel32.GetModuleHandleW.argtypes = [wintypes.LPCWSTR]
        kernel32.GetModuleHandleW.restype = wintypes.HMODULE

        user32.SetWindowsHookExW.argtypes = [
            ctypes.c_int,
            hook_proc_type,
            wintypes.HINSTANCE,
            wintypes.DWORD,
        ]
        user32.SetWindowsHookExW.restype = wintypes.HHOOK

        user32.CallNextHookEx.argtypes = [
            wintypes.HHOOK,
            ctypes.c_int,
            wintypes.WPARAM,
            wintypes.LPARAM,
        ]
        user32.CallNextHookEx.restype = lresult_type

        user32.GetMessageW.argtypes = [
            ctypes.POINTER(wintypes.MSG),
            wintypes.HWND,
            wintypes.UINT,
            wintypes.UINT,
        ]
        user32.GetMessageW.restype = wintypes.BOOL

        user32.TranslateMessage.argtypes = [ctypes.POINTER(wintypes.MSG)]
        user32.TranslateMessage.restype = wintypes.BOOL

        user32.DispatchMessageW.argtypes = [ctypes.POINTER(wintypes.MSG)]
        user32.DispatchMessageW.restype = lresult_type

        user32.GetKeyNameTextW.argtypes = [
            wintypes.LONG,
            wintypes.LPWSTR,
            ctypes.c_int,
        ]
        user32.GetKeyNameTextW.restype = ctypes.c_int

        user32.GetAsyncKeyState.argtypes = [ctypes.c_int]
        user32.GetAsyncKeyState.restype = ctypes.c_short

        user32.GetForegroundWindow.argtypes = []
        user32.GetForegroundWindow.restype = wintypes.HWND

        user32.GetWindowThreadProcessId.argtypes = [wintypes.HWND, ctypes.POINTER(wintypes.DWORD)]
        user32.GetWindowThreadProcessId.restype = wintypes.DWORD

        user32.GetKeyboardLayout.argtypes = [wintypes.DWORD]
        user32.GetKeyboardLayout.restype = wintypes.HKL

        user32.ToUnicodeEx.argtypes = [
            wintypes.UINT,
            wintypes.UINT,
            ctypes.POINTER(ctypes.c_ubyte),
            wintypes.LPWSTR,
            ctypes.c_int,
            wintypes.UINT,
            wintypes.HKL,
        ]
        user32.ToUnicodeEx.restype = ctypes.c_int

        kernel32.GetCurrentThreadId.argtypes = []
        kernel32.GetCurrentThreadId.restype = wintypes.DWORD

        user32.PostThreadMessageW.argtypes = [
            wintypes.DWORD,
            wintypes.UINT,
            wintypes.WPARAM,
            wintypes.LPARAM,
        ]
        user32.PostThreadMessageW.restype = wintypes.BOOL

        # 按键消息处理
        class KBDLLHOOKSTRUCT(ctypes.Structure):
            _fields_ = [
                ("vkCode", wintypes.DWORD),
                ("scanCode", wintypes.DWORD),
                ("flags", wintypes.DWORD),
                ("time", wintypes.DWORD),
                ("dwExtraInfo", ulong_ptr_type),
            ]

        def resolve_key_name(vk_code: int, scan_code: int, flags: int) -> str:
            lparam_value = scan_code << 16
            if flags & win32con.LLKHF_EXTENDED:
                lparam_value |= 1 << 24

            buffer = ctypes.create_unicode_buffer(64)
            length = user32.GetKeyNameTextW(lparam_value, buffer, len(buffer))
            if length > 0:
                return buffer.value
            return str(vk_code)

        def get_modifier_state(vk_code: int) -> Dict[str, bool]:
            states: Dict[str, bool] = {}
            for name, codes in self._MODIFIER_VK_CODES.items():
                states[name] = any(bool(user32.GetAsyncKeyState(code) & 0x8000) for code in codes)

            # On Windows, AltGr is commonly surfaced as Right Alt plus Ctrl.
            # Some keyboards expose the same layer only through a Ctrl+Alt chord,
            # so treat either form as AltGr for printable layout characters.
            states["alt_gr"] = bool(states.get("ctrl") and (states.get("alt_r") or states.get("alt")))

            if vk_code == 0x10:
                states["shift"] = True
            elif vk_code == 0x11:
                states["ctrl"] = True
            elif vk_code == 0x12:
                states["alt"] = True
            elif vk_code in (0x5B, 0x5C):
                states["win"] = True

            return states

        def resolve_text(vk_code: int, scan_code: int, modifiers: Dict[str, bool]) -> str:
            if modifiers.get("win"):
                return ""

            if modifiers.get("ctrl") and not modifiers.get("alt_gr"):
                return ""

            if modifiers.get("alt") and not modifiers.get("alt_gr"):
                return ""

            keyboard_state = (ctypes.c_ubyte * 256)()
            for code in range(256):
                if user32.GetAsyncKeyState(code) & 0x8000:
                    keyboard_state[code] |= 0x80

            def mark_pressed(*virtual_keys: int) -> None:
                for virtual_key in virtual_keys:
                    keyboard_state[virtual_key] |= 0x80

            # 低层钩子回调触发得很早，GetAsyncKeyState 对当前组合键有时还没完全稳定。
            # 这里根据解析出的修饰键显式补齐状态，确保 ToUnicodeEx 能命中 AltGr/Ctrl+Alt 层。
            if modifiers.get("shift"):
                mark_pressed(0x10, 0xA0, 0xA1)

            if modifiers.get("ctrl") or modifiers.get("alt_gr"):
                mark_pressed(0x11, 0xA2, 0xA3)

            if modifiers.get("alt") or modifiers.get("alt_gr"):
                mark_pressed(0x12, 0xA4, 0xA5)

            if modifiers.get("alt_r") or modifiers.get("alt_gr"):
                mark_pressed(0xA5)

            mark_pressed(vk_code)

            foreground_hwnd = user32.GetForegroundWindow()
            thread_id = wintypes.DWORD(0)
            layout_thread_id = 0
            if foreground_hwnd:
                layout_thread_id = int(user32.GetWindowThreadProcessId(foreground_hwnd, ctypes.byref(thread_id)))

            keyboard_layout = user32.GetKeyboardLayout(layout_thread_id)
            text_buffer = ctypes.create_unicode_buffer(8)
            translated_length = user32.ToUnicodeEx(
                vk_code,
                scan_code,
                keyboard_state,
                text_buffer,
                len(text_buffer),
                0,
                keyboard_layout,
            )

            if translated_length > 0:
                return text_buffer.value[:translated_length]

            return ""

        def low_level_keyboard_proc(nCode, wParam, lParam):
            try:
                if nCode == win32con.HC_ACTION:
                    kb_struct = ctypes.cast(
                        lParam,
                        ctypes.POINTER(KBDLLHOOKSTRUCT),
                    ).contents
                    vk_code = kb_struct.vkCode
                    scan_code = kb_struct.scanCode
                    flags = kb_struct.flags
                    if flags & win32con.LLKHF_INJECTED:
                        return user32.CallNextHookEx(None, nCode, wParam, lParam)
                    # 0x100: WM_KEYDOWN, 0x101: WM_KEYUP
                    if wParam == win32con.WM_KEYDOWN or wParam == win32con.WM_SYSKEYDOWN:
                        modifiers = get_modifier_state(vk_code)
                        key_info = self._normalize_win32_key_info(
                            vk_code,
                            scan_code,
                            flags,
                            modifiers,
                            resolve_key_name,
                            resolve_text,
                        )
                        # 调用回调，返回False则拦截
                        if self.on_key_press and self.on_key_press(key_info) is False:
                            return 1  # 拦截
            except Exception as exc:
                print(f"Win32键盘回调出错: {exc}")
            return user32.CallNextHookEx(None, nCode, wParam, lParam)

        # 设置钩子，持久化回调实例，防止被回收
        self._win32_callback = hook_proc_type(low_level_keyboard_proc)
        self._win32_thread_id = int(kernel32.GetCurrentThreadId())
        module_handle = kernel32.GetModuleHandleW(None)
        self._win32_hook = user32.SetWindowsHookExW(
            win32con.WH_KEYBOARD_LL,
            self._win32_callback,
            module_handle,
            0
        )
        if not self._win32_hook:
            error_code = ctypes.get_last_error()
            self._win32_error = (
                f"错误码 {error_code}，module_handle={hex(module_handle) if module_handle else '0x0'}"
            )
            self._win32_ready.set()
            return
        self._win32_hook_installed = True
        self._win32_ready.set()
        print("[Win32Hook] 全局键盘钩子已安装")
        # 消息循环
        msg = wintypes.MSG()
        while True:
            if user32.GetMessageW(ctypes.byref(msg), 0, 0, 0) == 0:
                break
            user32.TranslateMessage(ctypes.byref(msg))
            user32.DispatchMessageW(ctypes.byref(msg))

    def _init_pyhook(self) -> None:
        """使用pyHook初始化"""
        self._hook_manager = pyHook.HookManager()
        self._hook_manager.KeyDown = self._pyhook_key_down
        self._hook_manager.KeyUp = self._pyhook_key_up

    def _init_pynput(self) -> None:
        """使用pynput初始化"""
        self._listener = keyboard.Listener(
            on_press=self._pynput_key_press,
            on_release=self._pynput_key_release,
        )

    def _pyhook_key_down(self, event) -> bool:
        """
        pyHook按键事件处理

        Args:
            event: pyHook事件对象

        Returns:
            True继续传递按键，False拦截
        """
        try:
            # 转换为统一格式
            key_info = {
                'key': event.Key,
                'text': chr(event.Ascii) if event.Ascii > 0 else '',
                'ascii': event.Ascii if event.Ascii > 0 else None,
                'scan_code': event.ScanCode,
                'is_extended': event.IsExtended,
                'is_injected': event.Injected,
                'time': time.time(),
                'window': event.Window,
                'window_name': event.WindowName,
            }

            # 调用回调
            if self.on_key_press:
                return self.on_key_press(key_info)
            return True
        except Exception as e:
            print(f"处理按键事件出错: {e}")
            return True  # 出错时继续传递

    def _pyhook_key_up(self, event) -> bool:
        """
        pyHook释放键事件处理

        Args:
            event: pyHook事件对象

        Returns:
            True继续传递按键，False拦截
        """
        try:
            if self.on_key_release:
                key_info = {
                    'key': event.Key,
                    'text': chr(event.Ascii) if event.Ascii > 0 else '',
                    'ascii': event.Ascii if event.Ascii > 0 else None,
                    'time': time.time(),
                }
                return self.on_key_release(key_info)
            return True
        except Exception as e:
            print(f"处理释放键事件出错: {e}")
            return True

    def _pynput_key_press(self, key) -> None:
        """
        pynput按键事件处理

        Args:
            key: pynput按键对象
        """
        try:
            # 转换为统一格式
            key_info = {
                'key': self._pynput_key_to_string(key),
                'text': getattr(key, 'char', '') or '',
                'ascii': getattr(key, 'char', None),
                'time': time.time(),
            }

            # 调用回调
            if self.on_key_press:
                # pynput不支持拦截，所以总是返回True
                self.on_key_press(key_info)
        except Exception as e:
            print(f"处理按键事件出错: {e}")

    def _pynput_key_release(self, key) -> None:
        """
        pynput释放键事件处理

        Args:
            key: pynput按键对象
        """
        try:
            if self.on_key_release:
                key_info = {
                    'key': self._pynput_key_to_string(key),
                    'time': time.time(),
                }
                self.on_key_release(key_info)
        except Exception as e:
            print(f"处理释放键事件出错: {e}")

    def _pynput_key_to_string(self, key) -> str:
        """
        将pynput按键对象转换为字符串

        Args:
            key: pynput按键对象

        Returns:
            按键字符串
        """
        try:
            if isinstance(key, keyboard.KeyCode):
                return key.char if key.char else str(key)
            elif isinstance(key, keyboard.Key):
                return key.name
            else:
                return str(key)
        except:
            return str(key)

    def start(self) -> None:
        """开始监听键盘"""
        if self.is_running:
            print("键盘监听已在运行")
            return

        print("启动键盘监听...")

        if self._backend == "win32":
            self.is_running = self._win32_hook_installed
            if self.is_running:
                print("Win32键盘钩子已运行")
            else:
                raise RuntimeError(self._win32_error or "Win32 键盘钩子未启动")
        elif self._backend == "pyhook":
            # pyHook需要消息循环
            self._hook_manager.HookKeyboard()
            self.is_running = True
            print("pyHook键盘钩子已安装")
            # 注意：pythoncom.PumpMessages()会阻塞
            # 在实际应用中，应该在单独的线程中运行
        elif self._backend == "pynput":
            # pynput在后台线程运行
            if self._listener:
                self._listener.start()
                self.is_running = True
                print("pynput监听器已启动")
            else:
                raise RuntimeError("pynput 监听器初始化失败")
        else:
            raise RuntimeError("没有可启动的键盘监听后端")

    def stop(self) -> None:
        """停止监听键盘"""
        if not self.is_running:
            return

        print("停止键盘监听...")
        self.is_running = False

        if self._backend == "win32":
            try:
                if hasattr(self, '_win32_hook') and self._win32_hook:
                    import ctypes
                    ctypes.windll.user32.UnhookWindowsHookEx(self._win32_hook)
                    self._win32_hook = None
                    print("Win32键盘钩子已卸载")
                if self._win32_thread_id:
                    ctypes.windll.user32.PostThreadMessageW(
                        self._win32_thread_id,
                        0x0012,
                        0,
                        0,
                    )
                    self._win32_thread_id = None
                if hasattr(self, '_win32_thread') and self._win32_thread.is_alive():
                    self._win32_thread.join(timeout=0.5)
            except Exception as e:
                print(f"卸载Win32钩子出错: {e}")
        elif self._backend == "pyhook":
            try:
                self._hook_manager.UnhookKeyboard()
                print("pyHook键盘钩子已卸载")
            except Exception as e:
                print(f"卸载pyHook钩子出错: {e}")
        elif self._backend == "pynput":
            try:
                if self._listener:
                    self._listener.stop()
                    print("pynput监听器已停止")
            except Exception as e:
                print(f"停止pynput监听器出错: {e}")

    def is_active(self) -> bool:
        """
        检查是否正在监听

        Returns:
            True如果正在监听，False否则
        """
        return self.is_running

    def pump_messages(self) -> None:
        """
        处理消息循环（仅pyHook需要）

        注意：这个方法会阻塞，应该在单独的线程中调用
        """
        if HAS_PYHOOK and self.is_running:
            print("开始处理消息循环...")
            pythoncom.PumpMessages()
