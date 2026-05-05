"""Shared application logic for the two input-method entry points."""

from __future__ import annotations

from datetime import datetime, timezone
from pathlib import Path
from tkinter import messagebox, simpledialog
from typing import Callable, Optional

from ..borrow_wanxiang_frequency import marked_pinyin_to_numeric
from .core.decoders import (
    CompositeCandidateDecoder,
    build_code_display,
    build_input_sound_notes,
    build_manual_key_output_map,
    build_input_visual_map,
    build_physical_input_map,
    build_projected_to_physical_map,
    project_physical_input,
    unproject_physical_input,
)
from .ui.candidate_box import CandidateBox
from .utils.clipboard import ClipboardManager
from .utils.keyboard_simulator import KeyboardSimulator
from .utils.runtime_reverse_lookup import RuntimeReverseLookup, looks_like_hanzi_text
from .utils.user_lexicon import UserLexiconStore, resolve_yime_code_from_numeric_pinyin
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
        self.app_dir = app_dir
        self.repo_root = app_dir.parent
        self._pending_feedbacks: list[tuple[str, str, str, bool]] = []
        user_db_path = app_dir / "user_lexicon.db"
        self.user_db_path = user_db_path
        self.user_lexicon_seed_path = app_dir / "user_lexicon_seed.json"
        self.user_lexicon_store = UserLexiconStore(user_db_path)
        self.seed_import_result = self._maybe_import_seed_user_lexicon()
        self.decoder = CompositeCandidateDecoder(app_dir, user_db_path=user_db_path)
        self.input_visual_map = build_input_visual_map(app_dir.parent)
        self.manual_key_output_map = build_manual_key_output_map(app_dir.parent)
        self.physical_input_map = build_physical_input_map(app_dir.parent)
        self.projected_to_physical_map = build_projected_to_physical_map(
            self.physical_input_map
        )
        self.runtime_decoder_warning = self.decoder.get_runtime_warning()
        self.runtime_decoder_source = self.decoder.get_runtime_source()
        self.runtime_reverse_lookup = RuntimeReverseLookup(
            app_dir / "pinyin_hanzi.db",
            user_db_path=user_db_path,
        )
        self.clipboard = ClipboardManager()
        self.keyboard_simulator = KeyboardSimulator()
        self.window_manager = WindowManager()

        if candidate_box_factory is None:
            candidate_box_factory = self._create_candidate_box
        self.candidate_box = candidate_box_factory()
        self._flush_pending_feedbacks()

        self.own_hwnd = self.candidate_box.root.winfo_id()
        self._normalized_own_hwnd = self.window_manager.normalize_window_handle(
            self.own_hwnd
        )
        self.last_external_hwnd: Optional[int] = None
        self._locked_external_hwnd: Optional[int] = None
        self.last_replace_length = 0
        self._post_commit_behavior = "standby"

    def _maybe_import_seed_user_lexicon(self) -> dict[str, int]:
        meta_key = "seed_import_completed"
        if self.user_lexicon_store.get_meta(meta_key):
            return {"phrase_entries": 0, "candidate_frequency": 0}

        seed_path = getattr(self, "user_lexicon_seed_path", None)
        if seed_path is None or not Path(seed_path).exists():
            return {"phrase_entries": 0, "candidate_frequency": 0}

        if self.user_lexicon_store.has_user_data():
            self.user_lexicon_store.set_meta(meta_key, "skipped_existing_user_data")
            self._emit_feedback(
                "seed 用户词库",
                "已跳过 seed 用户词库导入：检测到本机已有用户数据。",
            )
            return {"phrase_entries": 0, "candidate_frequency": 0}

        result = self.user_lexicon_store.import_file(
            Path(seed_path),
            replace_existing=False,
            include_frequency=True,
        )
        imported = bool(result.get("phrase_entries") or result.get("candidate_frequency"))
        timestamp = datetime.now(timezone.utc).isoformat()
        state = f"imported:{timestamp}" if imported else f"empty_seed:{timestamp}"
        self.user_lexicon_store.set_meta(meta_key, state)
        if imported:
            self._emit_feedback(
                "seed 用户词库",
                "已导入 seed 用户词库: "
                f"{result['phrase_entries']} 条词条，{result['candidate_frequency']} 条调序频率。",
            )
        else:
            self._emit_feedback(
                "seed 用户词库",
                "已检查 seed 用户词库：文件存在，但没有可导入的词条或调序频率。",
            )
        return result

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
            on_add_input_to_user_lexicon=self._add_current_input_to_user_lexicon,
            on_delete_input_from_user_lexicon=self._delete_current_input_from_user_lexicon,
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

    def _resolve_manual_key_output(
        self,
        physical_key: str,
        modifiers: dict[str, bool],
    ) -> str:
        normalized_key = physical_key.strip().lower()
        if not normalized_key:
            return ""

        if modifiers.get("alt_gr"):
            layer = "altgr"
        elif modifiers.get("shift"):
            layer = "shift"
        else:
            layer = "base"

        return self.manual_key_output_map.get((normalized_key, layer), "")

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
        self._emit_feedback("复制", f"已复制: {text}")

    def _normalize_external_hwnd(self, hwnd: Optional[int]) -> Optional[int]:
        normalized = self.window_manager.normalize_window_handle(hwnd)
        own_normalized = getattr(self, "_normalized_own_hwnd", None)
        if own_normalized is None:
            own_normalized = self.window_manager.normalize_window_handle(
                getattr(self, "own_hwnd", None)
            )
            self._normalized_own_hwnd = own_normalized

        if not normalized or normalized == own_normalized:
            return None

        # 忽略进程自身的所有窗口（包括 Tkinter 界面、控制台等），防止互相抢夺焦点
        try:
            import ctypes
            import os
            pid = ctypes.c_ulong()
            ctypes.windll.user32.GetWindowThreadProcessId(normalized, ctypes.byref(pid))
            if pid.value == os.getpid():
                return None
        except Exception:
            pass

        # 进一步拦截由于 python.exe 启动时被隐式暴露的前台控制台窗口
        try:
            import ctypes
            console_hwnd = ctypes.windll.kernel32.GetConsoleWindow()
            if console_hwnd and normalized == self.window_manager.normalize_window_handle(console_hwnd):
                return None
        except Exception:
            pass

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

    def _reload_user_lexicon_runtime(self) -> None:
        if hasattr(self.decoder, "reload_user_lexicon"):
            self.decoder.reload_user_lexicon()

    def _dispatch_feedback(
        self,
        title: str,
        message: str,
        *,
        level: str,
        dialog: bool,
    ) -> None:
        self.candidate_box.set_status(message)
        if not dialog:
            return
        if level == "warning":
            messagebox.showwarning(title, message, parent=self.candidate_box.root)
            return
        if level == "error":
            messagebox.showerror(title, message, parent=self.candidate_box.root)
            return
        messagebox.showinfo(title, message, parent=self.candidate_box.root)

    def _emit_feedback(
        self,
        title: str,
        message: str,
        *,
        level: str = "info",
        dialog: bool = False,
    ) -> None:
        if hasattr(self, "candidate_box"):
            self._dispatch_feedback(title, message, level=level, dialog=dialog)
            return
        pending_feedbacks = getattr(self, "_pending_feedbacks", None)
        if pending_feedbacks is None:
            pending_feedbacks = []
            self._pending_feedbacks = pending_feedbacks
        pending_feedbacks.append((title, message, level, dialog))

    def _flush_pending_feedbacks(self) -> None:
        if not hasattr(self, "candidate_box"):
            return
        pending = list(getattr(self, "_pending_feedbacks", []))
        self._pending_feedbacks.clear()
        for title, message, level, dialog in pending:
            self._dispatch_feedback(title, message, level=level, dialog=dialog)

    def _show_user_lexicon_info(self, title: str, message: str) -> None:
        self._emit_feedback(title, message, level="info", dialog=True)

    def _show_user_lexicon_warning(self, title: str, message: str) -> None:
        self._emit_feedback(title, message, level="warning", dialog=True)

    def _show_user_lexicon_error(self, title: str, message: str) -> None:
        self._emit_feedback(title, message, level="error", dialog=True)

    def _normalize_numeric_pinyin_for_user_lexicon(self, raw_pinyin: str) -> tuple[str, str]:
        normalized = " ".join(raw_pinyin.split())
        if not normalized:
            return "", ""

        direct_code = resolve_yime_code_from_numeric_pinyin(self.repo_root, normalized)
        if direct_code:
            return normalized, direct_code

        converted = " ".join(marked_pinyin_to_numeric(normalized).split())
        if converted and converted != normalized:
            converted_code = resolve_yime_code_from_numeric_pinyin(self.repo_root, converted)
            if converted_code:
                return converted, converted_code

        return normalized, ""

    def _format_live_status(self, status: str, *, source: str) -> str:
        normalized = status.strip()
        if not normalized:
            return ""
        if source == "reverse_lookup":
            return f"反查: {normalized}"
        if source == "decode":
            return f"解码: {normalized}"
        return normalized

    def _summarize_decode_status(
        self,
        *,
        canonical_code: str,
        candidates: list[str],
        display_candidates: list[str],
    ) -> str:
        if candidates:
            return "已找到候选。"
        if len(canonical_code) < 4:
            if display_candidates:
                return "前缀等待，可先选单字，继续输入可收窄结果。"
            return "前缀等待，继续输入。"
        return "当前编码未找到候选。"

    def _add_current_input_to_user_lexicon(self) -> None:
        display_input = self.candidate_box.get_input().strip()
        input_text = project_physical_input(display_input, self.physical_input_map).strip()
        if not looks_like_hanzi_text(input_text) or len(input_text) < 2:
            message = "仅支持将当前汉字词语加入用户词库。"
            self._show_user_lexicon_warning("加入用户词库", message)
            return

        existing = self.runtime_reverse_lookup.lookup_first(input_text)
        default_numeric = existing.numeric_pinyin if existing is not None else ""
        default_marked = existing.marked_pinyin if existing is not None else ""

        numeric_pinyin = simpledialog.askstring(
            "加入用户词库",
            f"请输入“{input_text}”的数字标调拼音：",
            initialvalue=default_numeric,
            parent=self.candidate_box.root,
        )
        if numeric_pinyin is None:
            self._emit_feedback("加入用户词库", "已取消加入用户词库。")
            return

        normalized_numeric, yime_code = self._normalize_numeric_pinyin_for_user_lexicon(
            numeric_pinyin
        )
        if not normalized_numeric:
            message = "数字标调拼音不能为空。"
            self._show_user_lexicon_error("加入用户词库", message)
            return

        if not yime_code:
            message = (
                "无法根据第一栏拼音推导音元编码。请在第一栏填写数字标调拼音，"
                "例如“duo1 ri4”；如果你输入的是“duō rì”，系统只会在能自动转换时接受。"
            )
            self._show_user_lexicon_error("加入用户词库", message)
            return

        marked_pinyin = simpledialog.askstring(
            "加入用户词库",
            f"请输入“{input_text}”的标准拼音（可留空）：",
            initialvalue=default_marked,
            parent=self.candidate_box.root,
        )
        if marked_pinyin is None:
            self._emit_feedback("加入用户词库", "已取消加入用户词库。")
            return

        normalized_marked = " ".join(marked_pinyin.split())
        if not normalized_marked and normalized_numeric != " ".join(numeric_pinyin.split()):
            normalized_marked = " ".join(numeric_pinyin.split())

        action = self.user_lexicon_store.upsert_phrase(
            input_text,
            normalized_numeric,
            marked_pinyin=normalized_marked,
            yime_code=yime_code,
            source_note="ui_context_menu",
        )
        self._reload_user_lexicon_runtime()
        marked_display = normalized_marked
        pinyin_parts = [part for part in (marked_display, normalized_numeric) if part]
        pinyin_display = " / ".join(pinyin_parts)
        status_prefix = "已更新用户词库" if action == "updated" else "已加入用户词库"
        if pinyin_display:
            status_message = f"{status_prefix}: {input_text} | {pinyin_display} | {yime_code}"
        else:
            status_message = f"{status_prefix}: {input_text} | {yime_code}"
        self._show_user_lexicon_info("加入用户词库", status_message)
        self._on_input_change()

    def _delete_current_input_from_user_lexicon(self) -> None:
        display_input = self.candidate_box.get_input().strip()
        input_text = project_physical_input(display_input, self.physical_input_map).strip()
        if not looks_like_hanzi_text(input_text) or len(input_text) < 2:
            message = "仅支持将当前汉字词语从用户词库中删除。"
            self._show_user_lexicon_warning("从用户词库中删除", message)
            return

        confirm = messagebox.askyesno(
            "从用户词库中删除",
            f"确定要从用户词库中删除“{input_text}”吗？",
            parent=self.candidate_box.root,
        )
        if not confirm:
            self._emit_feedback("从用户词库中删除", "已取消从用户词库中删除。")
            return

        deleted = self.user_lexicon_store.delete_phrase(input_text)
        if not deleted:
            message = f"用户词库中未找到：{input_text}"
            self._show_user_lexicon_warning("从用户词库中删除", message)
            return

        self._reload_user_lexicon_runtime()
        status_message = f"已从用户词库中删除: {input_text}"
        self._show_user_lexicon_info("从用户词库中删除", status_message)
        self._on_input_change()

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

        if looks_like_hanzi_text(input_text):
            record = self.runtime_reverse_lookup.lookup_first(input_text)
            if record is not None:
                self.last_replace_length = len(input_text)
                status = self._format_live_status(
                    "已按运行时词库首选读音反查。",
                    source="reverse_lookup",
                )
                self.candidate_box.update_candidates(
                    [],
                    record.to_display_text(),
                    "",
                    status,
                )
                return

            self.last_replace_length = len(input_text)
            self.candidate_box.update_candidates(
                [],
                "",
                "",
                self._format_live_status(
                    "运行时词库中未找到该字词。",
                    source="reverse_lookup",
                ),
            )
            return

        canonical_code, active_code, pinyin, candidates, status = (
            self.decoder.decode_text(input_text)
        )

        self.last_replace_length = len(active_code) if active_code else min(4, len(input_text))
        code_display = build_code_display(input_text, canonical_code, active_code)
        display_candidates = self._resolve_display_candidates(canonical_code, candidates)
        self.candidate_box.update_candidates(
            display_candidates,
            pinyin,
            code_display,
            self._format_live_status(
                self._summarize_decode_status(
                    canonical_code=canonical_code,
                    candidates=candidates,
                    display_candidates=display_candidates,
                ),
                source="decode",
            ),
        )

    def _record_candidate_selection(self, hanzi: str) -> int:
        input_text = self.candidate_box.get_projected_input()
        if not input_text:
            input_text = project_physical_input(
                self.candidate_box.get_input(),
                self.physical_input_map,
            )
        if input_text:
            return int(self.decoder.record_selection(input_text, hanzi) or 0)
        return 0

    def _paste_to_previous_window(self, hanzi: str) -> None:
        target_hwnd = self._current_external_target_hwnd()
        target_description = self._describe_external_target(target_hwnd)
        should_keep_input = self._should_keep_input_after_commit()
        if not target_hwnd:
            self._emit_feedback("回贴", f"已复制: {hanzi}，未找到上一个窗口")
            self._unlock_external_target()
            return

        if not self._restore_external_window():
            self._emit_feedback(
                "回贴",
                f"已复制: {hanzi}，恢复目标失败：{target_description}"
            )
            print(f"[YIME] 恢复目标失败: {target_description}")
            self._unlock_external_target()
            return

        # The first foreground hop can be transient for external editors.
        # Re-assert the target shortly before injecting keys so the first send
        # does not depend on a single focus transfer attempt.
        self._schedule_ui(40, lambda: (self._restore_external_window(), None)[1])

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
                lambda: self._emit_feedback(
                    "回贴",
                    f"已替换 {self.last_replace_length} 个编码字符: {hanzi} -> {target_description}"
                ),
            )
            if should_keep_input:
                self._schedule_ui(320, self._schedule_refocus_candidate_input)
            else:
                self._schedule_ui(320, self._unlock_external_target)
            return

        self._schedule_ui(80, self.keyboard_simulator.send_ctrl_v)
        self._schedule_ui(
            180,
            lambda: self._emit_feedback(
                "回贴",
                f"已回贴: {hanzi} -> {target_description}"
            ),
        )
        if should_keep_input:
            self._schedule_ui(220, self._schedule_refocus_candidate_input)
        else:
            self._schedule_ui(220, self._unlock_external_target)

    def _schedule_refocus_candidate_input(self) -> None:
        refocus = getattr(self, "_refocus_candidate_input", None)
        if callable(refocus):
            refocus()

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
