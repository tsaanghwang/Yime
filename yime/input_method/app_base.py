"""Shared application logic for the two input-method entry points."""

from __future__ import annotations

from pathlib import Path
from typing import Callable, Optional

from .core.decoders import (
    CompositeCandidateDecoder,
    build_code_display,
    build_input_sound_notes,
    build_input_visual_map,
    build_physical_input_map,
    build_projected_to_physical_map,
    project_physical_input,
    unproject_physical_input,
)
from .ui.candidate_box import CandidateBox
from .utils.clipboard import ClipboardManager
from .utils.keyboard_simulator import KeyboardSimulator
from .utils.window_manager import WindowManager


class BaseInputMethodApp:
    """Common logic shared by the global-listener and hotkey entry points."""

    def __init__(
        self,
        *,
        auto_paste: bool,
        font_family: str,
        candidate_box_factory: Optional[Callable[[], CandidateBox]] = None,
    ) -> None:
        self.auto_paste = auto_paste
        self.font_family = font_family

        app_dir = Path(__file__).resolve().parent.parent
        self.decoder = CompositeCandidateDecoder(app_dir)
        self.input_visual_map = build_input_visual_map(app_dir.parent)
        self.physical_input_map = build_physical_input_map(app_dir.parent)
        self.projected_to_physical_map = build_projected_to_physical_map(
            self.physical_input_map
        )
        self.runtime_decoder_warning = self.decoder.get_runtime_warning()
        self.runtime_decoder_source = self.decoder.get_runtime_source()
        self.clipboard = ClipboardManager()
        self.keyboard_simulator = KeyboardSimulator()
        self.window_manager = WindowManager()

        if candidate_box_factory is None:
            candidate_box_factory = self._create_candidate_box
        self.candidate_box = candidate_box_factory()

        self.own_hwnd = self.candidate_box.root.winfo_id()
        self.last_external_hwnd: Optional[int] = None
        self.last_replace_length = 0

        self.candidate_box.root.protocol("WM_DELETE_WINDOW", self._close)

    def _create_candidate_box(self) -> CandidateBox:
        return CandidateBox(
            on_select=self._on_candidate_select,
            font_family=self.font_family,
            input_display_formatter=self._format_input_outline,
            projected_code_formatter=self._format_projected_code,
            on_input_change=self._on_input_change,
            on_decode_from_clipboard=self._decode_from_clipboard,
            on_copy_candidate=self._copy_candidate,
            on_commit_text=self._commit_candidate_box_text,
            on_close=self._close,
        )

    def _format_input_outline(self, text: str) -> str:
        return build_input_sound_notes(text, self.input_visual_map)

    def _format_projected_code(self, text: str) -> str:
        return unproject_physical_input(text, self.projected_to_physical_map)

    def _format_visible_input(self, text: str) -> str:
        if not text:
            return ""
        return project_physical_input(text, self.physical_input_map)

    def _format_prefix_hint(self, text: str) -> str:
        if not text:
            return ""

        canonical_code, active_code, _pinyin, candidates, _status = (
            self.decoder.decode_text(text)
        )
        if candidates or not active_code or len(canonical_code) >= 4:
            return ""

        matches = self.decoder.get_char_candidates_by_prefix(canonical_code, limit=5)
        if not matches:
            return "暂无单字前缀命中"

        candidate_count = sum(len(items) for _code, items in matches)
        samples: list[str] = []
        seen: set[str] = set()
        for _code, items in matches:
            for item in items:
                if item.text in seen:
                    continue
                seen.add(item.text)
                samples.append(item.text)
                if len(samples) >= 8:
                    break
            if len(samples) >= 8:
                break

        sample_text = " ".join(samples)
        if sample_text:
            return f"可继续编码 {len(matches)} 组 / 单字候选 {candidate_count} 个 / 示例 {sample_text}"
        return f"可继续编码 {len(matches)} 组 / 单字候选 {candidate_count} 个"

    def _schedule_ui(self, delay_ms: int, callback: Callable[[], None]) -> object:
        return self.candidate_box.root.after(delay_ms, callback)

    def _copy_text_with_status(self, text: str) -> None:
        self.clipboard.copy(text)
        self.candidate_box.status_var.set(f"已复制: {text}")

    def _restore_external_window(self) -> bool:
        if not self.last_external_hwnd or self.last_external_hwnd == self.own_hwnd:
            return False
        try:
            self.window_manager.restore_window(self.last_external_hwnd)
        except Exception:
            return False
        return True

    def _clear_candidate_box_state(
        self,
        *,
        focus_input: bool,
        clear_commit_text: bool = False,
    ) -> None:
        self.candidate_box.clear_input(focus_input=focus_input)
        if clear_commit_text:
            self.candidate_box.clear_commit_text()

    def _poll_foreground_window(self) -> None:
        foreground = self.window_manager.get_foreground_window()
        if foreground and foreground != self.own_hwnd:
            self.last_external_hwnd = foreground
        self._schedule_ui(250, self._poll_foreground_window)

    def _on_input_change(self, event: Optional[object] = None) -> None:
        display_input = self.candidate_box.get_input()
        input_text = project_physical_input(display_input, self.physical_input_map)
        if (
            display_input != input_text
            or self.candidate_box.get_projected_input() != input_text
        ):
            self.candidate_box.set_input(input_text, projected_text=input_text)

        if not input_text:
            self.candidate_box.set_prefix_hint("")
            self.candidate_box.update_candidates(
                [],
                "",
                "",
                '连续输入时自动取最近 4 码。请先复制编码，再点"读取剪贴板"。',
            )
            return

        canonical_code, active_code, pinyin, candidates, status = (
            self.decoder.decode_text(input_text)
        )

        self.last_replace_length = len(active_code) if active_code else min(4, len(input_text))
        code_display = build_code_display(input_text, canonical_code, active_code)
        self.candidate_box.set_prefix_hint(self._format_prefix_hint(input_text))
        self.candidate_box.update_candidates(candidates, pinyin, code_display, status)

    def _record_candidate_selection(self, hanzi: str) -> None:
        input_text = self.candidate_box.get_projected_input()
        if not input_text:
            input_text = project_physical_input(
                self.candidate_box.get_input(),
                self.physical_input_map,
            )
        if input_text:
            self.decoder.record_selection(input_text, hanzi)

    def _decode_from_clipboard(self) -> None:
        captured = self.clipboard.paste()
        if not captured:
            self.candidate_box.status_var.set("剪贴板没有可读取文本。")
            return

        self.candidate_box.set_input(
            self._format_visible_input(captured),
            projected_text=captured,
        )
        self.candidate_box.input_entry.focus_set()
        self._on_input_change()

    def _paste_to_previous_window(self, hanzi: str) -> None:
        if not self.last_external_hwnd:
            self.candidate_box.status_var.set(f"已复制: {hanzi}，未找到上一个窗口")
            return

        if not self._restore_external_window():
            self.candidate_box.status_var.set(f"已复制: {hanzi}，恢复前一个窗口失败")
            return

        if self.last_replace_length > 0:
            self._schedule_ui(
                80,
                lambda: self.keyboard_simulator.send_backspace(
                    self.last_replace_length
                ),
            )
            self._schedule_ui(170, self.keyboard_simulator.send_ctrl_v)
            self._schedule_ui(
                280,
                lambda: self.candidate_box.status_var.set(
                    f"已替换前一个窗口中的 {self.last_replace_length} 个编码字符: {hanzi}"
                ),
            )
            return

        self._schedule_ui(80, self.keyboard_simulator.send_ctrl_v)
        self._schedule_ui(
            180,
            lambda: self.candidate_box.status_var.set(f"已回贴到前一个窗口: {hanzi}"),
        )

    def _commit_candidate_box_text(self, text: str) -> None:
        self.clipboard.copy(text)

        if self.last_external_hwnd and self.last_external_hwnd != self.own_hwnd:
            self.last_replace_length = 0
            self._schedule_ui(50, lambda: self._paste_to_previous_window(text))

        self.candidate_box.clear_commit_text()
        self._clear_candidate_box_state(focus_input=False)
        self._after_commit_candidate_box_text()

    def _after_commit_candidate_box_text(self) -> None:
        """Hook for subclasses that need extra cleanup after commit."""

    def _copy_candidate(self, index: int) -> None:
        raise NotImplementedError

    def _on_candidate_select(self, hanzi: str) -> None:
        raise NotImplementedError

    def _close(self) -> None:
        raise NotImplementedError
