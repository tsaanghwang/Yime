"""
音元输入法 - 改进版

添加全局快捷键功能，优化输入流程
"""

from __future__ import annotations

import sys
import argparse
import ctypes
from pathlib import Path

# 添加项目根目录到路径
project_root = Path(__file__).resolve().parent.parent.parent
if str(project_root) not in sys.path:
    sys.path.insert(0, str(project_root))

from yime.input_method.app_base import BaseInputMethodApp


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

        super().__init__(
            auto_paste=auto_paste,
            font_family=font_family,
        )

        # 默认为显示状态以便于直接输入测试
        self.candidate_box.show(focus_input=True)

        # 窗口焦点轮询
        self._poll_foreground_window()

        # 设置关闭处理
        self.candidate_box.root.protocol("WM_DELETE_WINDOW", self._close)

        # 快捷键监听器
        self.hotkey_listener = None
        self._setup_hotkey()

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
        # 在主线程中执行
        self.candidate_box.root.after(0, self._do_show_and_focus)

    def _do_show_and_focus(self) -> None:
        """实际显示和聚焦操作"""
        self.candidate_box.show()
        self.candidate_box.input_entry.focus_set()
        self.candidate_box.input_entry.select_range(0, 'end')

    def _on_candidate_select(self, hanzi: str) -> None:
        """候选词选择处理"""
        self._record_candidate_selection(hanzi)

        # 复制到剪贴板
        self._copy_text_with_status(hanzi)

        # 自动粘贴
        if (
            self.auto_paste
            and self.last_external_hwnd
            and self.last_external_hwnd != self.own_hwnd
        ):
            self.candidate_box.root.after(
                50, lambda: self._paste_to_previous_window(hanzi)
            )

        # 调试期间禁用自动隐藏变成图标，便于直接查看完整 UI
        self._clear_candidate_box_state(focus_input=True)
        self.candidate_box.root.after(100, lambda: self.candidate_box.show(focus_input=True))

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
        keep_external_focus = bool(
            self.last_external_hwnd and self.last_external_hwnd != self.own_hwnd
        )
        self.candidate_box.show(focus_input=not keep_external_focus)
        if keep_external_focus:
            return
        self.candidate_box.input_entry.focus_set()
        self.candidate_box.input_entry.icursor("end")
        self.candidate_box.input_entry.selection_clear()

    def _close(self) -> None:
        """关闭应用"""
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

        # 显示使用说明
        print("\n使用方法:")
        print(f"1. 按 {self.hotkey.replace('<', '').replace('>', ' ')}唤出候选框")
        print("2. 在输入框中输入音元编码")
        print("3. 选择候选词（数字键或鼠标点击）")
        print("4. 自动复制到剪贴板并粘贴到目标窗口")
        print("5. 或在其他应用输入编码后，复制并点击'读取剪贴板'")
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
