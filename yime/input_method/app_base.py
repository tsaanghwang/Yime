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
        self._locked_external_hwnd: Optional[int] = None
        self.last_replace_length = 0
        self._post_commit_behavior = "standby"

        self.candidate_box.root.protocol("WM_DELETE_WINDOW", self._close)

    def _create_candidate_box(self) -> CandidateBox:
        return CandidateBox(
            on_select=self._on_candidate_select,
            font_family=self.font_family,
            input_display_formatter=self._format_input_outline,
            projected_code_formatter=self._format_projected_code,
            on_input_change=self._on_input_change,
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

    def _resolve_display_candidates(
        self,
        canonical_code: str,
        decoded_candidates: list[str],
    ) -> list[str]:
        """Use prefix hits as the candidate list until a full syllable resolves."""
        if decoded_candidates:
            return list(decoded_candidates)
        if not canonical_code or len(canonical_code) >= 4:
            return []

        matches = self.decoder.get_char_candidates_by_prefix(canonical_code, limit=5)
        merged: list[str] = []
        seen: set[str] = set()
        for _code, items in matches:
            for item in items:
                if item.text in seen:
                    continue
                seen.add(item.text)
                merged.append(item.text)
                if len(merged) >= 8:
                    return merged
        return merged

    def _schedule_ui(self, delay_ms: int, callback: Callable[[], None]) -> object:
        return self.candidate_box.root.after(delay_ms, callback)

    def _copy_text_with_status(self, text: str) -> None:
        self.clipboard.copy(text)
        self.candidate_box.status_var.set(f"已复制: {text}")

    def _normalize_external_hwnd(self, hwnd: Optional[int]) -> Optional[int]:
        normalized = self.window_manager.normalize_window_handle(hwnd)
        if not normalized or normalized == self.own_hwnd:
            return None
        return int(normalized)

    def _describe_external_target(self, hwnd: Optional[int] = None) -> str:
        return self.window_manager.describe_window(
            self._normalize_external_hwnd(hwnd or self._current_external_target_hwnd())
        )

    def _set_post_commit_behavior(self, behavior: str) -> None:
        self._post_commit_behavior = (
            "keep-input" if behavior == "keep-input" else "standby"
        )

    def _should_keep_input_after_commit(self) -> bool:
        return getattr(self, "_post_commit_behavior", "standby") == "keep-input"

    def _current_external_target_hwnd(self) -> Optional[int]:
        return self._normalize_external_hwnd(
            self._locked_external_hwnd or self.last_external_hwnd
        )

    def _lock_external_target(self, hwnd: Optional[int] = None) -> Optional[int]:
        target = self._normalize_external_hwnd(hwnd or self.last_external_hwnd)
        if target is None:
            return None
        self.last_external_hwnd = target
        self._locked_external_hwnd = target
        return target

    def _unlock_external_target(self) -> None:
        self._locked_external_hwnd = None

    def _restore_external_window(self) -> bool:
        target_hwnd = self._current_external_target_hwnd()
        if not target_hwnd:
            return False
        try:
            return bool(self.window_manager.restore_window(target_hwnd))
        except Exception:
            return False

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
        if not self._locked_external_hwnd and foreground and foreground != self.own_hwnd:
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
        display_candidates = self._resolve_display_candidates(canonical_code, candidates)
        if display_candidates and not candidates and len(canonical_code) < 4:
            status = f"当前 {len(canonical_code)}/4 码，先显示前缀单字候选，继续输入可收窄结果。"
        self.candidate_box.update_candidates(display_candidates, pinyin, code_display, status)

    def _record_candidate_selection(self, hanzi: str) -> None:
        input_text = self.candidate_box.get_projected_input()
        if not input_text:
            input_text = project_physical_input(
                self.candidate_box.get_input(),
                self.physical_input_map,
            )
        if input_text:
            self.decoder.record_selection(input_text, hanzi)

    def _paste_to_previous_window(self, hanzi: str) -> None:
        target_hwnd = self._current_external_target_hwnd()
        target_description = self._describe_external_target(target_hwnd)
        should_keep_input = self._should_keep_input_after_commit()
        if not target_hwnd:
            self.candidate_box.status_var.set(f"已复制: {hanzi}，未找到上一个窗口")
            self._unlock_external_target()
            return

        if not self._restore_external_window():
            self.candidate_box.status_var.set(
                f"已复制: {hanzi}，恢复目标失败：{target_description}"
            )
            print(f"[YIME] 恢复目标失败: {target_description}")
            self._unlock_external_target()
            return

        # The first foreground hop can be transient for external editors.
        # Re-assert the target shortly before injecting keys so the first send
        # does not depend on a single focus transfer attempt.
        self._schedule_ui(40, self._restore_external_window)

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
                    f"已替换 {self.last_replace_length} 个编码字符: {hanzi} -> {target_description}"
                ),
            )
            if should_keep_input:
                self._schedule_ui(320, self._refocus_candidate_input)
            else:
                self._schedule_ui(320, self._unlock_external_target)
            return

        self._schedule_ui(80, self.keyboard_simulator.send_ctrl_v)
        self._schedule_ui(
            180,
            lambda: self.candidate_box.status_var.set(
                f"已回贴: {hanzi} -> {target_description}"
            ),
        )
        if should_keep_input:
            self._schedule_ui(220, self._refocus_candidate_input)
        else:
            self._schedule_ui(220, self._unlock_external_target)

    def _commit_candidate_box_text(self, text: str) -> None:
        self.clipboard.copy(text)

        if self._current_external_target_hwnd():
            self.last_replace_length = 0
            self._schedule_ui(50, lambda: self._paste_to_previous_window(text))
        else:
            self._unlock_external_target()

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
