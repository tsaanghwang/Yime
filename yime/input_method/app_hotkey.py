"""
音元输入法 - 改进版

添加全局快捷键功能，优化输入流程
"""

from __future__ import annotations

import sys
import argparse
import ctypes
import queue
import tkinter as tk
from pathlib import Path
from typing import Callable

# 添加项目根目录到路径
project_root = Path(__file__).resolve().parent.parent.parent
if str(project_root) not in sys.path:
    sys.path.insert(0, str(project_root))

from yime.input_method.app_base import BaseInputMethodApp
from yime.input_method.ui.candidate_box import CandidateBox


class InputMethodAppV2(BaseInputMethodApp):
    """音元输入法 - 改进版（带快捷键）"""

    def __init__(
        self,
        auto_paste: bool = True,
        font_family: str = "音元",
        hotkey: str = "<ctrl>+<shift>+y",
    ) -> None:
        """
        初始化输入法应用

        Args:
            auto_paste: 是否自动粘贴
            font_family: 字体名称
            hotkey: 唤出快捷键
        """
        self.auto_paste = auto_paste
        self.font_family = font_family
        self.hotkey = hotkey
        self._startup_mode = "unknown"
        self._is_closing = False
        self._ui_queue: queue.SimpleQueue[Callable[[], None]] = queue.SimpleQueue()

        super().__init__(
            auto_paste=auto_paste,
            font_family=font_family,
        )

        # 设置关闭处理
        self.candidate_box.root.protocol("WM_DELETE_WINDOW", self._close)

        # 快捷键监听器
        self.hotkey_listener = None
        self._setup_hotkey()

        if self.hotkey_listener:
            self._startup_mode = "hotkey"
            self._set_post_commit_behavior("standby")
            self.candidate_box.show_standby()
            self.candidate_box.set_status(
                f"V2 热键模式已就绪：按 {self.hotkey.replace('<', '').replace('>', ' ')} 唤出输入框。"
            )
        else:
            # 热键不可用时退回手动模式，保留原先直接输入行为。
            self._startup_mode = "manual-fallback"
            self._set_post_commit_behavior("keep-input")
            self.candidate_box.show(focus_input=True)
            self.candidate_box.set_status(
                "V2 热键初始化失败，当前已退回手动编码区模式。"
            )

        # 窗口焦点轮询
        self._poll_foreground_window()
        self._pump_ui_queue()

    def _create_candidate_box(self) -> CandidateBox:
        return CandidateBox(
            on_select=self._on_candidate_select,
            font_family=self.font_family,
            input_display_formatter=self._format_input_outline,
            projected_code_formatter=self._format_projected_code,
            manual_key_output_resolver=self._resolve_manual_key_output,
            manual_input_transformer=self._format_visible_input,
            on_input_change=self._on_input_change,
            on_copy_candidate=self._copy_candidate,
            on_commit_text=self._commit_candidate_box_text,
            on_restore_from_standby=self._resume_from_standby,
            on_close=self._close,
        )

    def _setup_hotkey(self) -> None:
        """设置全局快捷键"""
        try:
            from pynput import keyboard

            def on_activate():
                """快捷键激活"""
                print("快捷键激活：显示候选框")
                self._show_and_focus()

            # 创建快捷键监听器
            self.hotkey_listener = keyboard.GlobalHotKeys({
                self.hotkey: on_activate,
            })

            print(f"全局快捷键已设置: {self.hotkey}")

        except Exception as e:
            print(f"设置快捷键失败: {e}")
            print("将使用手动模式")

    def _show_and_focus(self) -> None:
        """显示候选框并聚焦"""
        foreground = self.window_manager.get_foreground_window()
        target = self._lock_external_target(foreground)
        target_description = self._describe_external_target(target)
        print(f"[YIME V2] 本次锁定目标: {target_description}")
        self._enqueue_ui(
            lambda: self._activate_from_hotkey(
                foreground,
                target_description,
                post_commit_behavior="standby",
            )
        )

    def _activate_from_hotkey(
        self,
        foreground: int | None,
        target_description: str,
        *,
        post_commit_behavior: str,
    ) -> None:
        """进入一轮新的手动输入会话，并锁定当前外部目标。"""
        self._lock_external_target(foreground)
        self._set_post_commit_behavior(post_commit_behavior)
        self.last_replace_length = 0
        self.candidate_box.clear_input(focus_input=False)
        self.candidate_box.set_status(f"V2 锁定目标: {target_description}")
        self.candidate_box.show(focus_input=True, anchor_hwnd=foreground)
        self.candidate_box.input_entry.focus_set()
        self.candidate_box.input_entry.select_range(0, 'end')

    def _resume_from_standby(self) -> None:
        """用户点回待命图标或半透明主框时，重新锁定目标并恢复输入。"""
        target_description = self._describe_external_target(self.last_external_hwnd)
        if not self.last_external_hwnd:
            self._set_post_commit_behavior("keep-input")
            self.candidate_box.show(focus_input=True, anchor_hwnd=self.last_external_hwnd)
            self.candidate_box.set_status("V2 未找到外部目标，已回到本地输入模式。")
            return
        self._activate_from_hotkey(
            self.last_external_hwnd,
            target_description,
            post_commit_behavior="keep-input",
        )

    def _pump_ui_queue(self) -> None:
        """在 Tk 主线程中执行由热键线程提交的 UI 任务。"""
        if self._is_closing:
            return

        while True:
            try:
                callback = self._ui_queue.get_nowait()
            except queue.Empty:
                break

            try:
                callback()
            except tk.TclError:
                pass
            except Exception as exc:
                print(f"V2 UI任务执行出错: {exc}")

        self._schedule_ui(16, self._pump_ui_queue)

    def _enqueue_ui(self, callback: Callable[[], None]) -> None:
        """允许热键线程把 UI 更新投递回 Tk 主线程。"""
        if self._is_closing:
            return
        self._ui_queue.put(callback)

    def _on_candidate_select(self, hanzi: str) -> None:
        """候选词选择处理"""
        self._record_candidate_selection(hanzi)
        self.last_replace_length = 0
        self.candidate_box.root.after(0, lambda: self.candidate_box.show(focus_input=True))

    def _after_commit_candidate_box_text(self) -> None:
        """发送后立即退回待命，由共享回贴链路把焦点交还外部编辑器。"""
        if not self._current_external_target_hwnd():
            self._set_post_commit_behavior("keep-input")
            self.candidate_box.show(focus_input=True)
            return

        if self._should_keep_input_after_commit():
            self.candidate_box.show(focus_input=False)
            return

        self.candidate_box.show_passive()

    def _copy_candidate(self, index: int) -> None:
        """复制候选词"""
        candidates = self.candidate_box.current_candidates
        if 0 <= index < len(candidates):
            hanzi = candidates[index]
            self._record_candidate_selection(hanzi)
            self._copy_text_with_status(hanzi)
            self.candidate_box.clear_input(focus_input=True)

    def _refocus_candidate_input(self) -> None:
        """外部编辑动作完成后，将焦点拉回编码输入框。"""
        self.candidate_box.show(focus_input=True)
        self.candidate_box.input_entry.focus_set()
        self.candidate_box.input_entry.icursor("end")
        self.candidate_box.input_entry.selection_clear()

    def _close(self) -> None:
        """关闭应用"""
        self._is_closing = True

        # 停止快捷键监听
        if self.hotkey_listener:
            self.hotkey_listener.stop()

        self.candidate_box.close()

    def run(self) -> None:
        """运行应用"""
        # 启动快捷键监听
        if self.hotkey_listener:
            try:
                self.hotkey_listener.start()
                print(f"快捷键监听已启动: {self.hotkey}")
                print("按快捷键唤出候选框")
            except Exception as e:
                print(f"启动快捷键监听失败: {e}")
                self._startup_mode = "manual-fallback"
                self.candidate_box.show(focus_input=True)
                self.candidate_box.set_status(
                    f"V2 快捷键监听启动失败，已退回手动模式: {e}"
                )

        # 显示使用说明
        print("\n使用方法:")
        if self._startup_mode == "hotkey":
            print("当前模式: V2 热键模式")
        elif self._startup_mode == "manual-fallback":
            print("当前模式: V2 手动回退模式（热键未生效）")
        print(f"1. 按 {self.hotkey.replace('<', '').replace('>', ' ')}唤出候选框")
        print("2. 在输入框中输入音元编码")
        print("3. 用 Space / Enter / 数字键 / 鼠标把候选加入缓冲区")
        print("4. 用 Enter 或“发送”把缓冲区内容传到目标窗口")
        print("5. 需要时可继续在缓冲区里撤销一字")
        print("\n按 ESC 清空输入，关闭窗口退出")

        # 运行候选框
        self.candidate_box.run()


def parse_args() -> argparse.Namespace:
    """解析命令行参数"""
    parser = argparse.ArgumentParser(description="音元输入法 - 改进版")
    parser.add_argument(
        "--copy-only",
        action="store_true",
        help="只复制候选字到剪贴板，不自动回贴到上一个窗口。",
    )
    parser.add_argument(
        "--font-family",
        default="音元",
        help="输入框字体名。默认: 音元",
    )
    parser.add_argument(
        "--hotkey",
        default="<ctrl>+<shift>+y",
        help="唤出快捷键。默认: Ctrl+Shift+Y",
    )
    return parser.parse_args()


def main() -> None:
    """主函数"""
    if ctypes.sizeof(ctypes.c_void_p) == 0:
        raise SystemExit("Windows API 初始化失败")

    try:
        # 启用高 DPI 支持，解决 Tkinter 在高分屏下渲染模糊的问题
        ctypes.windll.shcore.SetProcessDpiAwareness(1)
    except Exception:
        pass

    args = parse_args()
    app = InputMethodAppV2(
        auto_paste=not args.copy_only,
        font_family=args.font_family,
        hotkey=args.hotkey,
    )
    app.run()


if __name__ == "__main__":
    main()
