"""
候选框几何计算模块
负责计算候选框的激活坐标、边界约束、双屏DPI换算、以及记录坐标以方便切换形态。
"""
import ctypes
import tkinter as tk
from typing import Optional, Tuple

from yime.input_method.utils.window_manager import WindowManager

class CandidateWindowGeometry:
    def __init__(self, root: tk.Tk):
        self.root = root
        self._last_main_geometry: Optional[Tuple[int, int, int, int]] = None
        self._user32 = None
        self.debug_ui = False

    def _get_user32(self):
        if self._user32 is None:
            self._user32 = ctypes.windll.user32
        return self._user32

    def resolve_activation_anchor(
        self,
        width: int,
        height: int,
        anchor_hwnd: Optional[int] = None,
        allow_pointer_heuristic: bool = True,
    ) -> Tuple[int, int]:
        foreground = anchor_hwnd or WindowManager.get_foreground_window()
        own_hwnd = self.root.winfo_id()
        if foreground and foreground != own_hwnd:
            input_rect = WindowManager.get_input_anchor_rect(foreground)
            if input_rect is not None:
                input_width = max(0, input_rect[2] - input_rect[0])
                input_height = max(0, input_rect[3] - input_rect[1])

                # 如果无法拿到真实的文字光标坐标（由于外部窗口未提供），则使用鼠标光标代替，真正跟随不同的输入点
                if (input_width <= 2 and input_height <= 2) or input_width > 100 or input_height > 100:
                    if allow_pointer_heuristic:
                        if self.debug_ui:
                            print(f"[Geometry.anchor] non-caret rect {input_rect} -> pointer heuristic")
                        pt_x, pt_y = WindowManager.get_cursor_position()
                        return pt_x + 12, pt_y + 24
                    elif self._last_main_geometry:
                        return self._last_main_geometry[0], self._last_main_geometry[1]

                left, top, right, bottom = input_rect
                return (
                    right + min(24, max(12, width // 8)),
                    bottom + min(24, max(12, height // 6)),
                )

            # 没有提取到任何光标边界，也默认回归鼠标位置
            if allow_pointer_heuristic:
                if self.debug_ui:
                    print("[Geometry.anchor] no input rect -> pointer heuristic")
                pt_x, pt_y = WindowManager.get_cursor_position()
                return pt_x + 12, pt_y + 24
            elif self._last_main_geometry:
                return self._last_main_geometry[0], self._last_main_geometry[1]

        if self.debug_ui:
            print(
                "[Geometry.anchor] fallback root corner "
                f"foreground={foreground} own={own_hwnd} size=({width},{height})"
            )
        return self.root.winfo_vrootx() + 32, self.root.winfo_vrooty() + 32

    def resolve_geometry(
        self,
        x: Optional[int],
        y: Optional[int],
        *,
        focus_input: bool,
        anchor_hwnd: Optional[int] = None,
        allow_pointer_heuristic: bool = True,
    ) -> Tuple[int, int]:
        self.root.update_idletasks()

        width = self.root.winfo_reqwidth()
        height = self.root.winfo_reqheight()

        virtual_root_x = self.root.winfo_vrootx()
        virtual_root_y = self.root.winfo_vrooty()
        screen_width = self.root.winfo_vrootwidth() or self.root.winfo_screenwidth()
        screen_height = self.root.winfo_vrootheight() or self.root.winfo_screenheight()

        if x is None or y is None:
            anchor_x, anchor_y = self.resolve_activation_anchor(
                width,
                height,
                anchor_hwnd=anchor_hwnd,
                allow_pointer_heuristic=allow_pointer_heuristic,
            )
            anchor_x, anchor_y = self.screen_to_tk_coords(anchor_x, anchor_y)
            target_x = anchor_x if x is None and focus_input else (virtual_root_x + 32 if x is None else x)
            target_y = anchor_y if y is None and focus_input else (virtual_root_y + 32 if y is None else y)
        else:
            target_x = x
            target_y = y

        min_x = virtual_root_x
        min_y = virtual_root_y
        max_x = max(min_x, virtual_root_x + screen_width - width - 8)
        max_y = max(min_y, virtual_root_y + screen_height - height - 8)
        target_x = min(max(target_x, min_x), max_x)
        target_y = min(max(target_y, min_y), max_y)
        return target_x, target_y

    def screen_to_tk_coords(self, x: int, y: int) -> Tuple[int, int]:
        """将 Win32 屏幕坐标转换到 Tk 当前使用的坐标系。"""
        try:
            user32 = self._get_user32()
            sm_xvirtualscreen = 76
            sm_yvirtualscreen = 77
            sm_cxvirtualscreen = 78
            sm_cyvirtualscreen = 79

            physical_root_x = int(user32.GetSystemMetrics(sm_xvirtualscreen))
            physical_root_y = int(user32.GetSystemMetrics(sm_yvirtualscreen))
            physical_width = int(user32.GetSystemMetrics(sm_cxvirtualscreen))
            physical_height = int(user32.GetSystemMetrics(sm_cyvirtualscreen))

            tk_root_x = self.root.winfo_vrootx()
            tk_root_y = self.root.winfo_vrooty()
            tk_width = self.root.winfo_vrootwidth() or self.root.winfo_screenwidth()
            tk_height = self.root.winfo_vrootheight() or self.root.winfo_screenheight()

            if physical_width <= 0 or physical_height <= 0 or tk_width <= 0 or tk_height <= 0:
                return x, y

            scale_x = tk_width / physical_width
            scale_y = tk_height / physical_height
            converted_x = tk_root_x + round((x - physical_root_x) * scale_x)
            converted_y = tk_root_y + round((y - physical_root_y) * scale_y)
            if self.debug_ui:
                print(
                    "[Geometry.coords] screen->tk "
                    f"screen=({x},{y}) physical_root=({physical_root_x},{physical_root_y}) "
                    f"physical_size=({physical_width},{physical_height}) tk_root=({tk_root_x},{tk_root_y}) "
                    f"tk_size=({tk_width},{tk_height}) result=({converted_x},{converted_y})"
                )
            return converted_x, converted_y
        except Exception:
            return x, y

    def get_pointer_position(self) -> Tuple[int, int]:
        """使用 Tk 提供的指针坐标，避免 Win32/Tk 在 DPI 缩放下坐标系不一致。"""
        self.root.update_idletasks()
        return self.root.winfo_pointerx(), self.root.winfo_pointery()

    def remember_main_geometry(
        self,
        x: int,
        y: int,
        width: Optional[int] = None,
        height: Optional[int] = None,
    ) -> None:
        """缓存主候选框最近一次正常显示的位置，避免 withdrawn 后回退到左上角兜底。"""
        resolved_width = width if width is not None else self.root.winfo_width() or self.root.winfo_reqwidth()
        resolved_height = height if height is not None else self.root.winfo_height() or self.root.winfo_reqheight()
        self._last_main_geometry = (x, y, resolved_width, resolved_height)

    def get_last_main_geometry(self) -> Optional[Tuple[int, int, int, int]]:
        return self._last_main_geometry

    def resolve_standby_geometry(self) -> Tuple[int, int, int, int]:
        """基于 _last_main_geometry 尝试在目标位置附近寻找安全区域。"""
        self.root.update_idletasks()
        my_width = self.root.winfo_reqwidth()
        my_height = self.root.winfo_reqheight()

        margin_y = 12
        if self._last_main_geometry:
            main_x, main_y, main_w, main_h = self._last_main_geometry
            target_x = main_x + (main_w - my_width) // 2
            target_y = main_y + main_h + margin_y
        else:
            pt_x, pt_y = WindowManager.get_cursor_position()
            tk_x, tk_y = self.screen_to_tk_coords(pt_x, pt_y)
            target_x = tk_x + 12
            target_y = tk_y + 24

        virtual_root_x = self.root.winfo_vrootx()
        virtual_root_y = self.root.winfo_vrooty()
        screen_width = self.root.winfo_vrootwidth() or self.root.winfo_screenwidth()
        screen_height = self.root.winfo_vrootheight() or self.root.winfo_screenheight()
        min_x = virtual_root_x
        min_y = virtual_root_y
        max_x = max(min_x, virtual_root_x + screen_width - my_width - 8)
        max_y = max(min_y, virtual_root_y + screen_height - my_height - 8)

        if self._last_main_geometry:
            _, main_y, _, _ = self._last_main_geometry
            if target_y > max_y and main_y - my_height - margin_y >= min_y:
                target_y = main_y - my_height - margin_y

        target_x = min(max(target_x, min_x), max_x)
        target_y = min(max(target_y, min_y), max_y)
        return target_x, target_y, my_width, my_height
