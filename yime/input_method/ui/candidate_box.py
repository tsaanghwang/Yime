"""
候选框UI模块

提供候选词显示、选择、窗口管理等功能
"""

import ctypes
import ctypes.wintypes as wintypes
import os
import tkinter as tk
from .candidate_system import CandidateWindowSystem
from .candidate_geometry import CandidateWindowGeometry
from .candidate_layout import CandidateLayoutBuilder
from .candidate_renderer import CandidateRendererMixin
from .manual_input_resolver import ManualInputResolver
from tkinter import font as tkfont
from tkinter import ttk
from typing import Callable, List, Optional

from ..utils.window_manager import WindowManager

InputChangeCallback = Callable[[Optional[object]], None]
CopyCandidateCallback = Callable[[int], None]
CommitTextCallback = Callable[[str], None]
ManualKeyOutputResolver = Callable[[str, dict[str, bool]], str]
VoidCallback = Callable[[], None]

from .candidate_box_actions import CandidateBoxActions


class CandidateBox(CandidateRendererMixin):
    """候选词显示框"""

    _CANDIDATE_TAG_PREFIX = "candidate_"
    _PAGER_PREV_TAG = "pager_prev"
    _PAGER_NEXT_TAG = "pager_next"
    _DEFAULT_STATUS_TEXT = '连续输入时自动取最近 4 码。请先复制编码，再点"读取剪贴板"。'
    _STANDBY_WINDOW_SIZE = 54
    _PASSIVE_ALPHA = 0.42
    _ACTIVE_ALPHA = 0.97
    _DEFAULT_CANDIDATE_LAYOUT = "horizontal"

    _HWND_TOPMOST = -1
    _HWND_NOTOPMOST = -2
    _SWP_NOSIZE = 0x0001
    _SWP_NOMOVE = 0x0002
    _SWP_NOACTIVATE = 0x0010
    _SWP_SHOWWINDOW = 0x0040
    _SWP_FRAMECHANGED = 0x0020
    _SWP_NOOWNERZORDER = 0x0200
    _SW_SHOWNOACTIVATE = 4
    _SW_SHOW = 5

    _DEBUG_UI = os.environ.get("YIME_DEBUG_UI", "").strip().lower() in {
        "1",
        "true",
        "yes",
        "on",
    }

    def __init__(
        self,
        on_select: Callable[[str], None],
        font_family: str = "音元",
        max_candidates: int = 5,
        candidate_layout: str = "horizontal",
        input_display_formatter: Optional[Callable[[str], str]] = None,
        projected_code_formatter: Optional[Callable[[str], str]] = None,
        manual_key_output_resolver: Optional[ManualKeyOutputResolver] = None,
        manual_input_transformer: Optional[Callable[[str], str]] = None,
        on_input_change: Optional[InputChangeCallback] = None,
        on_copy_candidate: Optional[CopyCandidateCallback] = None,
        on_commit_text: Optional[CommitTextCallback] = None,
        on_restore_from_standby: Optional[VoidCallback] = None,
        on_toggle_standby: Optional[VoidCallback] = None,
        on_close: Optional[VoidCallback] = None,
    ) -> None:
        """
        初始化候选框

        Args:
            on_select: 选择候选词的回调函数
            font_family: 字体名称
            max_candidates: 最大候选词数量
            on_input_change: 输入变化回调
            on_copy_candidate: 复制候选词回调
        """
        self.on_select = on_select
        self.font_family = font_family
        self.max_candidates = max_candidates
        self.all_candidates: List[str] = []
        self.current_candidates: List[str] = []
        self._selected_candidate_index = 0
        self._is_standby = False
        self._manual_input_enabled = False
        self._current_page = 0
        self._candidate_layout = self._normalize_candidate_layout(candidate_layout)
        self._input_display_formatter = input_display_formatter
        self._projected_code_formatter = projected_code_formatter
        self._manual_key_output_resolver = manual_key_output_resolver
        self._manual_input_transformer = manual_input_transformer
        self.projected_input_text = ""
        self._last_main_geometry: Optional[tuple[int, int, int, int]] = None

        # 回调注入
        self._on_input_change_callback = on_input_change
        self._on_copy_candidate_callback = on_copy_candidate
        self._on_commit_text_callback = on_commit_text
        self._on_restore_from_standby = on_restore_from_standby
        self._on_toggle_standby = on_toggle_standby
        self._on_close = on_close
        self._handling_iconify = False

        # 创建主窗口
        self.root = tk.Tk()
        self.root.title("音元拼音")

        self.layout_builder = CandidateLayoutBuilder(self.root, font_family)
        self.layout_builder.build_ui()

        # 将Builder中的组件映射到 self，保持与旧代码的兼容性
        self.font_family = self.layout_builder.font_family
        self.input_var = self.layout_builder.input_var
        self.input_entry = self.layout_builder.input_entry
        self.commit_var = self.layout_builder.commit_var
        self.commit_entry = self.layout_builder.commit_entry
        self.pinyin_var = self.layout_builder.pinyin_var
        self.candidate_text = self.layout_builder.candidate_text
        self.pager_frame = self.layout_builder.pager_frame

        # 兼容旧的按钮名称
        self.prev_page_button = self.layout_builder.prev_button
        self.next_page_button = self.layout_builder.next_button

        # 创建缺失的变量
        self.page_size_var = tk.IntVar(value=max_candidates)
        self.page_info_var = tk.StringVar(self.root, value="第 1/1 页")
        self.shortcut_hint_var = tk.StringVar(value="Space 选首选")
        self.projected_code_var = tk.StringVar(self.root, value="")
        self.input_outline_var = tk.StringVar(self.root, value="")
        self.code_var = tk.StringVar(self.root, value="")

        # 创建缺失的按钮
        self.first_page_button = ttk.Label(self.pager_frame, text="⏮")
        self.last_page_button = ttk.Label(self.pager_frame, text="⏭")
        self.prev_button = self.layout_builder.prev_button
        self.next_button = self.layout_builder.next_button
        self.standby_frame = self.layout_builder.standby_frame
        self.standby_icon = self.layout_builder.standby_icon
        self.main_frame = self.layout_builder.main_frame
        self.decode_info_frame = self.layout_builder.decode_info_frame
        self.status_var = self.layout_builder.status_var
        self.app_version_label = self.layout_builder.app_version_label
        self.dict_version_label = self.layout_builder.dict_version_label
        self.manual_key_layout_label = self.layout_builder.manual_key_layout_label

        # 构建附加子系统
        self.window_system = CandidateWindowSystem(self.root)
        self.window_geometry = CandidateWindowGeometry(self.root)

        # 不要硬性指定宽高，让它自然展开，防止越加越多被裁剪
        self.root.attributes("-topmost", True)
        self.root.resizable(False, False)
        self.root.withdraw()  # 初始隐藏
        self._bind_passive_reactivation_targets()
        self._bind_standby_toggle_targets()
        self.actions = CandidateBoxActions(self)
        self._bind_keys()

        self.root.bind("<Unmap>", self._on_window_unmap)
        self.root.protocol("WM_DELETE_WINDOW", self.actions.request_close)

    def _resize_to_content_if_visible(self) -> None:
        """窗口已显示时，按当前内容请求尺寸自动放大，避免新增说明区被裁掉。"""
        if self._is_standby:
            return
        try:
            if self.root.state() == "withdrawn":
                return
        except tk.TclError:
            return

        self.root.update_idletasks()
        current_x = self.root.winfo_x()
        current_y = self.root.winfo_y()
        target_width = self.root.winfo_reqwidth()
        target_height = self.root.winfo_reqheight()
        self.root.geometry(f"{target_width}x{target_height}+{current_x}+{current_y}")
        self.root.update_idletasks()

    def _bind_keys(self) -> None:
        """绑定快捷键"""
        self.actions.bind_keys()

    def _on_manual_input_key_press(self, event: Optional[tk.Event] = None) -> Optional[str]:
        if not event or event.widget != self.input_entry or not self._manual_input_enabled:
            return None

        modifiers = ManualInputResolver.get_manual_key_modifiers()
        translated_text = ""
        physical_key = ManualInputResolver.normalize_event_physical_key(event)
        if self._manual_key_output_resolver and physical_key:
            translated_text = self._manual_key_output_resolver(physical_key, modifiers)

        if not translated_text:
            translated_text = ManualInputResolver.resolve_manual_input_text(event)
        if len(translated_text) != 1 or translated_text < " ":
            return None

        if self._manual_input_transformer:
            translated_text = self._manual_input_transformer(translated_text)
        if len(translated_text) != 1 or translated_text < " ":
            return None

        native_char = getattr(event, "char", "") or ""
        should_intercept = bool(modifiers.get("alt_gr") or native_char != translated_text)
        if not should_intercept:
            return None

        self.input_entry.insert(tk.INSERT, translated_text)
        self.root.after_idle(self._on_input_change)
        return "break"

    def _bind_passive_reactivation_targets(self) -> None:
        """半透明静置态下，点击主界面任意区域都可恢复激活。"""
        self._bind_passive_reactivation_widget(self.main_frame)

    def _bind_passive_reactivation_widget(self, widget: tk.Misc) -> None:
        widget.bind("<Button-1>", self._reactivate_from_passive, add="+")
        for child in widget.winfo_children():
            self._bind_passive_reactivation_widget(child)

    def _bind_standby_toggle_targets(self) -> None:
        """主界面右键时可直接回到右下角待命图标。"""
        self._bind_standby_toggle_widget(self.main_frame)

    def _bind_standby_toggle_widget(self, widget: tk.Misc) -> None:
        widget.bind("<Button-3>", self._request_standby_from_mouse, add="+")
        for child in widget.winfo_children():
            self._bind_standby_toggle_widget(child)

    def _on_window_focus_in(self, event: object) -> None:
        """当输入候选框获得焦点时，把光标输入插入点（cursor焦点）跳转到输入框输入点。"""
        self.actions.on_window_focus_in(event)

    def _reactivate_from_passive(self, event: Optional[tk.Event] = None) -> None:
        """半透明静置态点击后恢复可输入状态。"""
        if self._is_standby or self._manual_input_enabled:
            return
        if self._on_restore_from_standby:
            self.actions.restore_from_standby(event)
            return
        self.actions.activate_for_manual_input(event)

    def _on_window_unmap(self, event: Optional[tk.Event] = None) -> None:
        """仅在用户显式最小化时，转成右下角待命图标。"""
        if getattr(event, "widget", self.root) != self.root:
            return
        if self._handling_iconify:
            return
        try:
            if self.root.state() != "iconic":
                return
        except tk.TclError:
            return
        self._handling_iconify = True
        self.root.after(0, self._convert_iconify_to_standby)

    def _convert_iconify_to_standby(self) -> None:
        try:
            self.show_standby()
        finally:
            self._handling_iconify = False

    def _on_input_change(self, event: Optional[tk.Event] = None) -> None:
        """输入变化事件处理"""
        self.actions.on_input_change(event)

    def _format_codepoints(self, text: str) -> str:
        if not text:
            return ""
        return " ".join(
            f"U+{ord(char):06X}" if ord(char) > 0xFFFF else f"U+{ord(char):04X}"
            for char in text
        )

    def _refresh_input_outline(self, text: str) -> None:
        # 暂时收起投影编码和音元音符，只保留标准拼音作为主参照。
        self.projected_code_var.set("")
        self.input_outline_var.set("")
        self._resize_to_content_if_visible()

    def _activate_for_manual_input(self, event: Optional[tk.Event] = None) -> None:
        """鼠标点入输入框时允许窗口激活，便于手动粘贴测试编码。"""
        self.actions.activate_for_manual_input(event)

    def _restore_from_standby(self, event: Optional[tk.Event] = None) -> str:
        """从待命小图标恢复主候选框。"""
        return self.actions.restore_from_standby(event)

    def _request_standby_from_mouse(self, event: Optional[tk.Event] = None) -> str:
        """主候选框右键时返回待命图标。"""
        if self._is_standby:
            return "break"
        return self.actions.request_standby(event)

    def set_manual_input_enabled(self, enabled: bool) -> None:
        """切换候选框是否允许手动输入模式。"""
        self._manual_input_enabled = enabled
        if enabled:
            self.input_entry.state(["!readonly"])
        else:
            self.input_entry.state(["readonly"])

    def is_manual_input_enabled(self) -> bool:
        """返回候选框是否处于手动输入模式。"""
        return self._manual_input_enabled

    def is_standby(self) -> bool:
        """返回候选框是否处于待命模式。"""
        return self._is_standby

    def focus_input_cursor(self) -> None:
        """将焦点和光标移动到输入框末尾。"""
        self.input_entry.focus_set()
        self.input_entry.icursor("end")

    def normalize_input_entry_state(self) -> None:
        """清除输入框残留选区，并将插入点固定到末尾。"""
        self.input_entry.selection_clear()
        self.input_entry.icursor(tk.END)

    def _focus_input_with_retry(self, hwnd: int) -> None:
        """对 Electron/VS Code 一类窗口做一次延迟补焦，避免首次焦点请求被吃掉。"""

        def apply_focus(use_force: bool = False) -> None:
            if use_force:
                self.input_entry.focus_force()
            else:
                self.input_entry.focus_set()
            self.normalize_input_entry_state()

        apply_focus()

        def retry_focus() -> None:
            try:
                current_focus = self.root.focus_get()
            except tk.TclError:
                return
            if self._DEBUG_UI:
                print(
                    "[CandidateBox.focus] retry "
                    f"current_focus={current_focus} input_entry={self.input_entry}"
                )
            if current_focus == self.input_entry:
                return
            try:
                self.root.lift()
            except tk.TclError:
                return
            WindowManager.restore_window(hwnd)
            apply_focus(use_force=True)

        self.root.after(60, retry_focus)

    def set_status(self, text: str) -> None:
        """更新状态栏文案。"""
        self.status_var.set(text)

    def _show_main_frame(self) -> None:
        if self._is_standby:
            self.standby_frame.pack_forget()
            self.main_frame.pack(fill=tk.BOTH, expand=True)
            self.root.geometry("")  # 清除待命态 54x54 显式尺寸，让主界面按内容重新撑开
            self.root.update_idletasks()
            self._is_standby = False
        self.root.attributes("-alpha", self._ACTIVE_ALPHA)
        self.root.title("音元拼音")

    def _on_confirm_key(self, event: Optional[tk.Event] = None) -> str:
        """有候选时先将首选加入缓冲区，否则发送缓冲区到外部编辑器。"""
        return self.actions.on_confirm_key(event)

    def _on_digit_shortcut(self, event: Optional[tk.Event], value: int) -> str:
        """数字键在非编辑态下用于选择当前页候选。"""
        return self.actions.on_digit_shortcut(event, value)

    def _clear_input(self, focus_input: bool = True) -> None:
        """清空输入"""
        self.input_var.set("")
        self.pinyin_var.set("")
        self.code_var.set("")
        self.all_candidates = []
        self.current_candidates = []
        self._selected_candidate_index = 0
        self._current_page = 0
        self.status_var.set(self._DEFAULT_STATUS_TEXT)
        self.projected_input_text = ""
        self.projected_code_var.set("")
        self.input_outline_var.set("")
        self._render_candidates()
        self._resize_to_content_if_visible()
        if focus_input:
            self.input_entry.focus_set()

    def clear_input(self, focus_input: bool = True) -> None:
        """公开的清空输入入口。"""
        self._clear_input(focus_input=focus_input)

    def clear_commit_text(self) -> None:
        """清空缓冲区文本。"""
        self.commit_var.set("")
        self.status_var.set("已清空缓冲区。")

    def remove_last_commit_char(self) -> None:
        """撤销缓冲区中的最后一个字符。"""
        current = self.commit_var.get()
        if not current:
            self.status_var.set("缓冲区为空，无可撤销内容。")
            return
        self.commit_var.set(current[:-1])
        if self.commit_var.get():
            self.status_var.set(f"已撤销最后一字，缓冲区: {self.commit_var.get()}")
        else:
            self.status_var.set("已撤销最后一字，缓冲区已清空。")

    def append_commit_text(self, text: str) -> None:
        """向缓冲区追加已选候选。"""
        if not text:
            return
        self.commit_var.set(f"{self.commit_var.get()}{text}")

    def get_candidate(self, index: int) -> Optional[str]:
        """按当前页索引读取候选。"""
        if 0 <= index < len(self.current_candidates):
            return self.current_candidates[index]
        return None

    def get_commit_text(self) -> str:
        """获取缓冲区文本。"""
        return self.commit_var.get()

    def get_selected_candidate_index(self) -> int:
        """返回当前高亮候选在当前页内的索引。"""
        if not self.current_candidates:
            return 0
        return min(self._selected_candidate_index, len(self.current_candidates) - 1)

    def move_selection(self, delta: int) -> None:
        """在当前页内移动高亮候选，不触发提交。"""
        if not self.current_candidates:
            self._selected_candidate_index = 0
            return
        current_index = self.get_selected_candidate_index()
        self._selected_candidate_index = (current_index + delta) % len(self.current_candidates)
        self._render_candidates()

    def _on_commit_backspace(self, event: Optional[tk.Event] = None) -> str:
        """缓冲区为空时，退格回退最近一次已选字。"""
        return self.actions.on_commit_backspace(event)

    def _select_candidate_by_index(self, index: int) -> None:
        """
        选择候选词

        Args:
            index: 候选词索引
        """
        self.actions.select_candidate_by_index(index)

    def _click_candidate_by_index(self, index: int) -> None:
        """鼠标点击候选时立即提交到外部编辑器。"""
        self.actions.on_candidate_click(index)

    def _copy_candidate(self, index: int) -> None:
        """
        复制候选词

        Args:
            index: 候选词索引
        """
        self.actions.copy_candidate(index)

    def _close(self) -> None:
        """关闭窗口"""
        try:
            if self.root.winfo_exists():
                self.root.quit()
                self.root.destroy()
        except tk.TclError:
            pass

    def close(self) -> None:
        """公开的关闭窗口入口。"""
        self._close()

    def show(
        self,
        x: Optional[int] = None,
        y: Optional[int] = None,
        focus_input: bool = True,
        anchor_hwnd: Optional[int] = None,
        force_recompute: bool = False,
    ) -> None:
        """
        显示候选框

        Args:
            x: X坐标（可选）
            y: Y坐标（可选）
            focus_input: 是否将焦点切回候选框输入框
            anchor_hwnd: 用来定位锚点的窗口
            force_recompute: 是否强制重新计算位置
        """
        was_standby = self._is_standby
        try:
            previous_state = self.root.state()
        except tk.TclError:
            previous_state = "withdrawn"

        self._show_main_frame()
        self.set_manual_input_enabled(focus_input)
        preserve_current_position = (
            x is None
            and y is None
            and anchor_hwnd is None
            and not was_standby
            and not force_recompute
            and previous_state != "withdrawn"
        )
        if preserve_current_position:
            target_x = self.root.winfo_x()
            target_y = self.root.winfo_y()
        elif not force_recompute and was_standby and x is None and y is None and self._last_main_geometry is not None:
            # When waking up via mouse, restore to its last active screen location
            target_x, target_y, _, _ = self._last_main_geometry
        else:
            target_x, target_y = self.window_geometry.resolve_geometry(
                x,
                y,
                focus_input=focus_input,
                anchor_hwnd=anchor_hwnd,
            )

        # 移除显式指定尺寸的设定，使用Tkinter自适应
        self.root.geometry(f"+{target_x}+{target_y}")
        hwnd = self.root.winfo_id()
        user32 = self.window_system._get_user32()
        if not focus_input:
            if hasattr(self, "window_system") and self.window_system: self.window_system.set_noactivate(True)
            self.root.attributes("-topmost", True)
            self.root.deiconify()
            self.root.update_idletasks()
            user32.ShowWindow(hwnd, self._SW_SHOWNOACTIVATE)
            user32.SetWindowPos(
                hwnd,
                self._HWND_TOPMOST,
                target_x,
                target_y,
                0,
                0,
                self._SWP_NOSIZE
                | self._SWP_NOACTIVATE
                | self._SWP_SHOWWINDOW
                | self._SWP_NOOWNERZORDER,
            )
        else:
            if hasattr(self, "window_system") and self.window_system: self.window_system.set_noactivate(False)
            self.root.state("normal")
            self.root.deiconify()
            self.root.attributes("-topmost", True)
            user32.ShowWindow(hwnd, self._SW_SHOW)
            user32.SetWindowPos(
                hwnd,
                self._HWND_TOPMOST,
                target_x,
                target_y,
                0,
                0,
                self._SWP_NOSIZE
                | self._SWP_SHOWWINDOW
                | self._SWP_NOOWNERZORDER,
            )
            self.root.lift()
            WindowManager.restore_window(hwnd)
        self.root.update()
        self.window_geometry.remember_main_geometry(target_x, target_y)
        if self._DEBUG_UI:
            is_visible = bool(user32.IsWindowVisible(hwnd))
            print(
                f"[CandidateBox.show] hwnd={hwnd} visible={is_visible} focus_input={focus_input} geometry=auto+{target_x}+{target_y} state={self.root.state()}"
            )
        if focus_input:
            self._focus_input_with_retry(hwnd)
        else:
            self.normalize_input_entry_state()

    def show_standby(self) -> None:
        """显示右下角半透明待命图标，保持输入法处于可再次触发状态。"""
        if not self._is_standby:
            self.main_frame.pack_forget()
            self.standby_frame.pack(fill=tk.BOTH, expand=True)
            self._is_standby = True

        target_x, target_y, width, height = self.window_geometry.resolve_standby_geometry()
        self.root.geometry(f"{width}x{height}+{target_x}+{target_y}")
        self.root.title("音")
        self.root.attributes("-alpha", 0.58)
        self.root.deiconify()
        self.root.update_idletasks()
        hwnd = self.root.winfo_id()
        user32 = self.window_system._get_user32()
        if hasattr(self, "window_system") and self.window_system: self.window_system.set_noactivate(True)
        user32.ShowWindow(hwnd, self._SW_SHOWNOACTIVATE)
        user32.SetWindowPos(
            hwnd,
            self._HWND_TOPMOST,
            target_x,
            target_y,
            width,
            height,
            self._SWP_NOACTIVATE
            | self._SWP_SHOWWINDOW
            | self._SWP_NOOWNERZORDER,
        )
        self.root.update()

    def show_passive(self) -> None:
        """显示半透明主界面，保留当前位置与尺寸，不退成角落图标。"""
        self._show_main_frame()
        self.set_manual_input_enabled(False)
        self.root.update_idletasks()

        if self.root.state() == "withdrawn":
            if self._last_main_geometry is not None:
                target_x, target_y, width, height = self._last_main_geometry
            else:
                target_x, target_y = self.window_geometry.resolve_geometry(None, None, focus_input=False)
                width = self.root.winfo_reqwidth()
                height = self.root.winfo_reqheight()
        else:
            target_x = self.root.winfo_x()
            target_y = self.root.winfo_y()
            width = self.root.winfo_width() or self.root.winfo_reqwidth()
            height = self.root.winfo_height() or self.root.winfo_reqheight()

        self.root.geometry(f"{width}x{height}+{target_x}+{target_y}")
        self.root.attributes("-alpha", self._PASSIVE_ALPHA)
        self.root.attributes("-topmost", False)
        self.root.deiconify()
        self.root.update_idletasks()

        hwnd = self.root.winfo_id()
        user32 = self.window_system._get_user32()
        if hasattr(self, "window_system") and self.window_system: self.window_system.set_noactivate(True)
        user32.ShowWindow(hwnd, self._SW_SHOWNOACTIVATE)
        user32.SetWindowPos(
            hwnd,
            self._HWND_NOTOPMOST,
            target_x,
            target_y,
            width,
            height,
            self._SWP_NOACTIVATE
            | self._SWP_SHOWWINDOW
            | self._SWP_NOOWNERZORDER,
        )
        self.root.update()
        self.window_geometry.remember_main_geometry(target_x, target_y, width, height)

    def hide(self) -> None:
        """隐藏候选框"""
        if self._DEBUG_UI:
            print("[CandidateBox.hide] withdraw")
        self.root.withdraw()

    def update_candidates(
        self,
        candidates: List[str],
        pinyin: str = "",
        code: str = "",
        status: str = "",
    ) -> None:
        """
        更新候选词显示

        Args:
            candidates: 候选词列表
            pinyin: 拼音显示
            code: 编码显示
            status: 状态消息
        """
        previous_count = len(self.all_candidates)
        self.all_candidates = list(candidates)
        if previous_count != len(self.all_candidates):
            self._current_page = 0
        self.pinyin_var.set(f"拼音: {pinyin}" if pinyin else "")
        self.code_var.set("")

        # 解码 4 码暂时不进入常态信息层级，需要排查时再打开调试 UI。
        if self._DEBUG_UI:
            if code:
                self.code_var.set(f"当前解码 4 码: {code}")
            else:
                self.code_var.set("当前解码 4 码: [等待输入...]")

        self.status_var.set(status)
        self._render_candidates()
        self._resize_to_content_if_visible()

    def get_input(self) -> str:
        """
        获取当前输入

        Returns:
            当前输入的文本
        """
        return self.input_var.get()

    def get_projected_input(self) -> str:
        """获取当前投影后的编码字符。"""
        return self.projected_input_text

    def set_projected_input(self, text: str) -> None:
        """设置当前投影后的编码字符，并刷新说明区。"""
        self.projected_input_text = text
        self._refresh_input_outline(text)

    def set_input(self, text: str, projected_text: Optional[str] = None) -> None:
        """
        设置输入框内容

        Args:
            text: 要设置的文本
        """
        self.input_var.set(text)
        self.projected_input_text = text if projected_text is None else projected_text
        self._refresh_input_outline(self.projected_input_text)
        self.normalize_input_entry_state()

    def run(self) -> None:
        """运行主循环"""
        self._render_candidates()
        self.root.mainloop()
