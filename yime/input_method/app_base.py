"""Shared application logic for the two input-method entry points."""

from __future__ import annotations

from datetime import datetime, timezone
import json
import os
from pathlib import Path
import subprocess
import sys
from tkinter import messagebox, simpledialog
from typing import Callable, Mapping, Optional, cast

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
from .utils.user_lexicon import (
    UserLexiconStore,
    normalize_numeric_pinyin_syllable_spacing,
    resolve_yime_code_from_numeric_pinyin,
)
from .utils.window_manager import WindowManager


def resolve_user_data_dir(
    app_dir: Path,
    *,
    env: Optional[Mapping[str, str]] = None,
    is_frozen: Optional[bool] = None,
) -> Path:
    environment = os.environ if env is None else env
    override = str(environment.get("YIME_USER_DATA_DIR") or "").strip()
    if override:
        return Path(override).expanduser()

    if is_frozen is None:
        is_frozen = bool(getattr(sys, "frozen", False))

    if is_frozen:
        per_user_root = str(
            environment.get("LOCALAPPDATA") or environment.get("APPDATA") or ""
        ).strip()
        if per_user_root:
            return Path(per_user_root) / "Yime"

    return app_dir


def resolve_user_documents_dir(
    *,
    env: Optional[Mapping[str, str]] = None,
    home: Optional[Path] = None,
) -> Path:
    environment = os.environ if env is None else env
    if home is not None:
        home_dir = Path(home).expanduser()
    else:
        user_profile = str(environment.get("USERPROFILE") or "").strip()
        home_dir = Path(user_profile).expanduser() if user_profile else Path.home()
    return home_dir / "Documents"


def resolve_user_lexicon_exchange_dir(
    *,
    env: Optional[Mapping[str, str]] = None,
    home: Optional[Path] = None,
) -> Path:
    return resolve_user_documents_dir(env=env, home=home) / "Yime" / "UserLexicon"


class BaseInputMethodApp:
    """Common logic shared by the global-listener and hotkey entry points."""

    _DEFAULT_CANDIDATE_PAGE_SIZE = 5
    _DEFAULT_CANDIDATE_LAYOUT = "horizontal"
    _DEFAULT_UI_SCALE_PERCENT = 100
    _DEFAULT_ACTIVE_ALPHA_PERCENT = 97
    _DEFAULT_FOREGROUND_COLOR = "#111827"
    _DEFAULT_BACKGROUND_COLOR = "#f0f0f0"

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
        self.runtime_candidates_json_path = (
            app_dir / "reports" / "runtime_candidates_by_code_true.json"
        )
        self.runtime_entry_label = self._detect_runtime_entry_label()
        self._pending_feedbacks: list[tuple[str, str, str, bool]] = []
        self.user_data_dir = resolve_user_data_dir(app_dir)
        self.user_lexicon_exchange_dir = resolve_user_lexicon_exchange_dir()
        self.user_lexicon_import_path = self.user_lexicon_exchange_dir / "user_lexicon_import.txt"
        self.user_lexicon_export_path = self.user_lexicon_exchange_dir / "user_lexicon_export.txt"
        self.ui_settings_path = self.user_data_dir / "ui_settings.json"
        self.ui_settings = self._load_ui_settings()
        self.candidate_page_size = self._normalize_candidate_page_size(
            self.ui_settings.get("candidate_page_size")
        )
        self.candidate_layout = self._normalize_candidate_layout_setting(
            self.ui_settings.get("candidate_layout")
        )
        self._mouse_wake_enabled_setting = self._normalize_bool_setting(
            self.ui_settings.get("mouse_wake_enabled"),
            True,
        )
        self._mouse_standby_enabled_setting = self._normalize_bool_setting(
            self.ui_settings.get("mouse_standby_enabled"),
            True,
        )
        self.ui_scale_percent = self._normalize_ui_scale_percent(
            self.ui_settings.get("ui_scale_percent")
        )
        self.active_alpha_percent = self._normalize_active_alpha_percent(
            self.ui_settings.get("active_alpha_percent")
        )
        self.foreground_color = self._normalize_foreground_color(
            self.ui_settings.get("foreground_color")
        )
        self.background_color = self._normalize_background_color(
            self.ui_settings.get("background_color")
        )
        self.active_topmost_enabled = self._normalize_bool_setting(
            self.ui_settings.get("active_topmost_enabled"),
            True,
        )
        user_db_path = self.user_data_dir / "user_lexicon.db"
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
        self._apply_ui_settings_to_candidate_box()
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
            max_candidates=self.candidate_page_size,
            candidate_layout=self.candidate_layout,
            input_display_formatter=self._format_input_outline,
            projected_code_formatter=self._format_projected_code,
            manual_key_output_resolver=self._resolve_manual_key_output,
            manual_input_transformer=self._format_visible_input,
            on_input_change=self._on_input_change,
            on_copy_candidate=self._copy_candidate,
            on_commit_text=self._commit_candidate_box_text,
            on_candidate_page_size_change=self._on_candidate_page_size_change,
            on_candidate_layout_change=self._on_candidate_layout_change,
            on_mouse_wake_enabled_change=self._on_mouse_wake_enabled_change,
            on_mouse_standby_enabled_change=self._on_mouse_standby_enabled_change,
            on_ui_scale_change=self._on_ui_scale_change,
            on_active_alpha_change=self._on_active_alpha_change,
            on_foreground_color_change=self._on_foreground_color_change,
            on_background_color_change=self._on_background_color_change,
            on_active_topmost_change=self._on_active_topmost_change,
            on_reload_user_lexicon=self._reload_user_lexicon_from_menu,
            on_import_user_lexicon=self._import_user_lexicon_from_menu,
            on_export_user_lexicon=self._export_user_lexicon_from_menu,
            on_open_settings_file=self._open_settings_file,
            on_open_user_data_dir=self._open_settings_file,
            on_hotkey_summary_request=self._build_hotkey_summary,
            on_runtime_readiness_summary_request=self._build_runtime_readiness_display_summary,
            on_runtime_data_guidance_request=self._build_runtime_data_guidance,
            on_add_input_to_user_lexicon=self._add_current_input_to_user_lexicon,
            on_delete_input_from_user_lexicon=self._delete_current_input_from_user_lexicon,
            on_feedback=self._emit_feedback,
            on_close=self._close,
        )

    def _normalize_candidate_page_size(self, page_size: object) -> int:
        try:
            normalized = page_size if isinstance(page_size, (int, str)) else None
            if normalized is None:
                raise TypeError("candidate page size is missing")
            return min(max(int(normalized), 5), 9)
        except (TypeError, ValueError):
            return self._DEFAULT_CANDIDATE_PAGE_SIZE

    def _normalize_candidate_layout_setting(self, layout: object) -> str:
        normalized = str(layout or "").strip().lower()
        return "vertical" if normalized == "vertical" else self._DEFAULT_CANDIDATE_LAYOUT

    def _normalize_bool_setting(self, value: object, default: bool) -> bool:
        if isinstance(value, bool):
            return value
        if isinstance(value, (int, float)):
            return bool(value)
        if isinstance(value, str):
            normalized = value.strip().lower()
            if normalized in {"1", "true", "yes", "on"}:
                return True
            if normalized in {"0", "false", "no", "off"}:
                return False
        return default

    def _normalize_ui_scale_percent(self, value: object) -> int:
        try:
            normalized = value if isinstance(value, (int, str)) else None
            if normalized is None:
                raise TypeError("ui scale is missing")
            return min(max(int(normalized), 90), 120)
        except (TypeError, ValueError):
            return self._DEFAULT_UI_SCALE_PERCENT

    def _normalize_active_alpha_percent(self, value: object) -> int:
        try:
            normalized = value if isinstance(value, (int, str)) else None
            if normalized is None:
                raise TypeError("active alpha is missing")
            return min(max(int(normalized), 80), 100)
        except (TypeError, ValueError):
            return self._DEFAULT_ACTIVE_ALPHA_PERCENT

    def _normalize_foreground_color(self, value: object) -> str:
        if isinstance(value, str):
            normalized = value.strip().lower()
            if len(normalized) == 7 and normalized.startswith("#"):
                try:
                    int(normalized[1:], 16)
                    return normalized
                except ValueError:
                    pass
        return self._DEFAULT_FOREGROUND_COLOR

    def _normalize_background_color(self, value: object) -> str:
        if isinstance(value, str):
            normalized = value.strip().lower()
            if len(normalized) == 7 and normalized.startswith("#"):
                try:
                    int(normalized[1:], 16)
                    return normalized
                except ValueError:
                    pass
        return self._DEFAULT_BACKGROUND_COLOR

    def _load_ui_settings(self) -> dict[str, object]:
        try:
            raw_payload = self.ui_settings_path.read_text(encoding="utf-8")
        except FileNotFoundError:
            return {}
        except OSError:
            return {}

        try:
            payload = json.loads(raw_payload)
        except json.JSONDecodeError:
            return {}
        return cast(dict[str, object], payload) if isinstance(payload, dict) else {}

    def _save_ui_settings(self) -> None:
        self.user_data_dir.mkdir(parents=True, exist_ok=True)
        payload = dict(self.ui_settings)
        payload["candidate_page_size"] = self.candidate_page_size
        payload["candidate_layout"] = self.candidate_layout
        payload["mouse_wake_enabled"] = self._mouse_wake_enabled_setting
        payload["mouse_standby_enabled"] = self._mouse_standby_enabled_setting
        payload["ui_scale_percent"] = self.ui_scale_percent
        payload["active_alpha_percent"] = self.active_alpha_percent
        payload["foreground_color"] = self.foreground_color
        payload["background_color"] = self.background_color
        payload["active_topmost_enabled"] = self.active_topmost_enabled
        self.ui_settings_path.write_text(
            json.dumps(payload, ensure_ascii=False, indent=2) + "\n",
            encoding="utf-8",
        )

    def _apply_ui_settings_to_candidate_box(self) -> None:
        apply_layout = getattr(self.candidate_box, "set_candidate_layout", None)
        if callable(apply_layout):
            apply_layout(self.candidate_layout)

        apply_mouse_wake = getattr(self.candidate_box, "set_mouse_wake_enabled", None)
        if callable(apply_mouse_wake):
            apply_mouse_wake(self._resolve_effective_mouse_wake_enabled())

        apply_mouse_standby = getattr(self.candidate_box, "set_mouse_standby_enabled", None)
        if callable(apply_mouse_standby):
            apply_mouse_standby(self._resolve_effective_mouse_standby_enabled())

        apply_ui_scale = getattr(self.candidate_box, "set_ui_scale", None)
        if callable(apply_ui_scale):
            apply_ui_scale(self.ui_scale_percent)

        apply_active_alpha = getattr(self.candidate_box, "set_active_alpha_percent", None)
        if callable(apply_active_alpha):
            apply_active_alpha(self.active_alpha_percent)

        apply_foreground_color = getattr(self.candidate_box, "set_foreground_color", None)
        if callable(apply_foreground_color):
            apply_foreground_color(self.foreground_color)

        apply_background_color = getattr(self.candidate_box, "set_background_color", None)
        if callable(apply_background_color):
            apply_background_color(self.background_color)

        apply_topmost = getattr(self.candidate_box, "set_active_topmost_enabled", None)
        if callable(apply_topmost):
            apply_topmost(self.active_topmost_enabled)

    def _on_candidate_page_size_change(self, page_size: int) -> None:
        normalized = self._normalize_candidate_page_size(page_size)
        self.candidate_box.set_page_size(normalized)
        self.candidate_page_size = normalized
        self.ui_settings["candidate_page_size"] = normalized
        self._save_ui_settings()

    def _on_candidate_layout_change(self, layout: str) -> None:
        normalized = self._normalize_candidate_layout_setting(layout)
        self.candidate_box.set_candidate_layout(normalized)
        self.candidate_layout = normalized
        self.ui_settings["candidate_layout"] = normalized
        self._save_ui_settings()

    def _resolve_effective_mouse_wake_enabled(self) -> bool:
        resolver = getattr(self, "_is_mouse_wake_enabled", None)
        if callable(resolver):
            return bool(resolver())
        return bool(self._mouse_wake_enabled_setting)

    def _resolve_effective_mouse_standby_enabled(self) -> bool:
        resolver = getattr(self, "_is_mouse_standby_enabled", None)
        if callable(resolver):
            return bool(resolver())
        return bool(self._mouse_standby_enabled_setting)

    def _update_mouse_trigger_setting(self, attribute_name: str, enabled: bool) -> None:
        current = getattr(self, attribute_name, None)
        if not isinstance(current, frozenset):
            return
        updated = set(cast(frozenset[str], current))
        if enabled:
            updated.add("mouse")
        else:
            updated.discard("mouse")
        setattr(self, attribute_name, frozenset(updated))

    def _on_mouse_wake_enabled_change(self, enabled: bool) -> None:
        normalized = self._normalize_bool_setting(enabled, True)
        self._mouse_wake_enabled_setting = normalized
        self._update_mouse_trigger_setting("wake_triggers", normalized)
        self.candidate_box.set_mouse_wake_enabled(self._resolve_effective_mouse_wake_enabled())
        self.ui_settings["mouse_wake_enabled"] = normalized
        self._save_ui_settings()

    def _on_mouse_standby_enabled_change(self, enabled: bool) -> None:
        normalized = self._normalize_bool_setting(enabled, True)
        self._mouse_standby_enabled_setting = normalized
        self._update_mouse_trigger_setting("standby_triggers", normalized)
        self.candidate_box.set_mouse_standby_enabled(self._resolve_effective_mouse_standby_enabled())
        self.ui_settings["mouse_standby_enabled"] = normalized
        self._save_ui_settings()

    def _on_ui_scale_change(self, scale_percent: int) -> None:
        normalized = self._normalize_ui_scale_percent(scale_percent)
        apply = getattr(self.candidate_box, "set_ui_scale", None)
        if callable(apply):
            apply(normalized)
        self.ui_scale_percent = normalized
        self.ui_settings["ui_scale_percent"] = normalized
        self._save_ui_settings()

    def _on_active_alpha_change(self, alpha_percent: int) -> None:
        normalized = self._normalize_active_alpha_percent(alpha_percent)
        apply = getattr(self.candidate_box, "set_active_alpha_percent", None)
        if callable(apply):
            apply(normalized)
        self.active_alpha_percent = normalized
        self.ui_settings["active_alpha_percent"] = normalized
        self._save_ui_settings()

    def _on_foreground_color_change(self, color: str) -> None:
        normalized = self._normalize_foreground_color(color)
        apply = getattr(self.candidate_box, "set_foreground_color", None)
        if callable(apply):
            apply(normalized)
        self.foreground_color = normalized
        self.ui_settings["foreground_color"] = normalized
        self._save_ui_settings()

    def _on_background_color_change(self, color: str) -> None:
        normalized = self._normalize_background_color(color)
        apply = getattr(self.candidate_box, "set_background_color", None)
        if callable(apply):
            apply(normalized)
        self.background_color = normalized
        self.ui_settings["background_color"] = normalized
        self._save_ui_settings()

    def _on_active_topmost_change(self, enabled: bool) -> None:
        normalized = self._normalize_bool_setting(enabled, True)
        apply = getattr(self.candidate_box, "set_active_topmost_enabled", None)
        if callable(apply):
            apply(normalized)
        self.active_topmost_enabled = normalized
        self.ui_settings["active_topmost_enabled"] = normalized
        self._save_ui_settings()

    def _reload_user_lexicon_from_menu(self) -> None:
        self._apply_user_lexicon_import_file(
            title="应用用户词库",
            success_prefix="已应用用户词库",
        )

    def _get_user_lexicon_exchange_dir(self) -> Path:
        exchange_dir = getattr(self, "user_lexicon_exchange_dir", None)
        if exchange_dir is None:
            exchange_dir = resolve_user_lexicon_exchange_dir()
            self.user_lexicon_exchange_dir = exchange_dir
        return Path(exchange_dir)

    def _get_user_lexicon_import_path(self) -> Path:
        import_path = getattr(self, "user_lexicon_import_path", None)
        if import_path is None:
            import_path = self._get_user_lexicon_exchange_dir() / "user_lexicon_import.txt"
            self.user_lexicon_import_path = import_path
        return Path(import_path)

    def _get_user_lexicon_export_path(self) -> Path:
        export_path = getattr(self, "user_lexicon_export_path", None)
        if export_path is None:
            export_path = self._get_user_lexicon_exchange_dir() / "user_lexicon_export.txt"
            self.user_lexicon_export_path = export_path
        return Path(export_path)

    def _open_path_in_shell(self, path_text: str) -> None:
        if hasattr(os, "startfile"):
            os.startfile(path_text)  # type: ignore[attr-defined]
        elif sys.platform == "darwin":
            subprocess.Popen(["open", path_text])
        else:
            subprocess.Popen(["xdg-open", path_text])

    def _edit_user_lexicon_from_menu(self) -> None:
        import_path = self._get_user_lexicon_import_path()
        import_path.parent.mkdir(parents=True, exist_ok=True)
        result = self.user_lexicon_store.write_text_export_file(import_path)
        self._open_path_in_shell(str(import_path))
        self._show_user_lexicon_info(
            "用户词库",
            "已生成可编辑的用户词库导入文件："
            f"{result['phrase_entries']} 条词条，{result['candidate_frequency']} 条初始频率。\n\n"
            f"请编辑并保存：{import_path}\n"
            "保存后可通过“导入用户词库”将修改写回。",
        )

    def _apply_user_lexicon_import_file(
        self,
        *,
        title: str,
        success_prefix: str,
    ) -> None:
        import_path = self._get_user_lexicon_import_path()
        import_path.parent.mkdir(parents=True, exist_ok=True)
        if not import_path.exists():
            self._show_user_lexicon_warning(
                title,
                "未找到导入文件。\n\n"
                f"请将 UTF-8 文本文件放到：{import_path}\n"
                "文件名固定为 user_lexicon_import.txt，表头为：词语\t数字标调拼音\t初始频率",
            )
            return

        try:
            result = self.user_lexicon_store.import_text_file(
                import_path,
                repo_root=self.repo_root,
            )
        except ValueError as exc:
            self._show_user_lexicon_error(title, str(exc))
            return

        self._reload_user_lexicon_runtime()
        self._on_input_change()
        self._show_user_lexicon_info(
            title,
            f"{success_prefix}："
            f"{result['phrase_entries']} 条词条，{result['candidate_frequency']} 条初始频率。\n\n"
            f"读取文件：{import_path}",
        )

    def _import_user_lexicon_from_menu(self) -> None:
        self._apply_user_lexicon_import_file(
            title="导入用户词库",
            success_prefix="已导入用户词库",
        )

    def _export_user_lexicon_from_menu(self) -> None:
        export_path = self._get_user_lexicon_export_path()
        export_path.parent.mkdir(parents=True, exist_ok=True)
        result = self.user_lexicon_store.write_text_export_file(export_path)
        self._show_user_lexicon_info(
            "导出用户词库",
            "已导出用户词库："
            f"{result['phrase_entries']} 条词条，{result['candidate_frequency']} 条初始频率。\n\n"
            f"写入文件：{export_path}",
        )

    def _open_settings_file(self) -> None:
        self.user_data_dir.mkdir(parents=True, exist_ok=True)
        self._save_ui_settings()
        settings_path = self.ui_settings_path
        path_text = str(settings_path)
        self._open_path_in_shell(path_text)
        self._emit_feedback("设置文件", f"已保存当前设置并打开设置文件：{path_text}")

    def _open_user_data_dir(self) -> None:
        # Backward-compatible alias for older call sites.
        self._open_settings_file()

    def _open_troubleshooting_doc(self) -> None:
        troubleshooting_path = Path(self.repo_root) / "docs" / "help" / "troubleshooting.md"
        path_text = str(troubleshooting_path)
        self._open_path_in_shell(path_text)
        self._emit_feedback("故障排查", f"已打开故障排查文档：{path_text}")

    def _build_hotkey_summary(self) -> str:
        hotkey = str(getattr(self, "hotkey", "未配置热键") or "未配置热键")
        wake_hint = getattr(self, "_wake_trigger_hint", None)
        standby_hint = getattr(self, "_standby_trigger_hint", None)
        wake_text = wake_hint() if callable(wake_hint) else "当前未提供"
        standby_text = standby_hint() if callable(standby_hint) else "当前未提供"
        format_hotkey_label = getattr(self, "_format_hotkey_label", None)
        display_hotkey = format_hotkey_label() if callable(format_hotkey_label) else hotkey
        return (
            f"当前热键：{display_hotkey}\n"
            f"唤起方式：{wake_text}\n"
            f"休眠方式：{standby_text}"
        )

    def _detect_runtime_entry_label(self) -> str:
        if bool(getattr(sys, "frozen", False)):
            return f"打包程序：{Path(sys.executable).name}"

        argv = list(getattr(sys, "argv", []) or [])
        if not argv:
            return "当前未识别运行入口"

        argv0 = str(argv[0] or "").replace("\\", "/")
        argv0_name = Path(argv0).name.lower()
        if argv0_name == "run_input_method.py":
            return "python run_input_method.py"
        if argv0_name in {"app.py", "__main__.py"} and "yime/input_method" in argv0.lower():
            return "python -m yime.input_method.app"
        if argv0_name:
            return f"当前命令：{Path(argv0).name}"
        return "当前未识别运行入口"

    def _describe_runtime_candidate_source(self) -> str:
        source = str(getattr(self, "runtime_decoder_source", "unknown") or "unknown").lower()
        if source == "json":
            return "运行时 JSON 导出文件"
        if source == "sqlite":
            return "SQLite runtime_candidates 回退"
        if source == "static":
            return "静态候选表兜底"
        return "当前未识别候选来源"

    def _check_user_lexicon_exchange_dir(self) -> tuple[str, str, Optional[str]]:
        exchange_dir = Path(getattr(self, "user_lexicon_exchange_dir", "") or "")
        if not str(exchange_dir):
            return (
                "警告",
                "当前未配置用户词库交换目录",
                "请检查用户目录解析是否正常。",
            )
        if exchange_dir.exists() and not exchange_dir.is_dir():
            return (
                "警告",
                f"路径已被文件占用：{exchange_dir}",
                "请删除同名文件或改用可写目录。",
            )
        try:
            exchange_dir.mkdir(parents=True, exist_ok=True)
        except OSError as exc:
            return (
                "警告",
                f"无法创建目录：{exchange_dir}（{exc}）",
                "请检查 Documents/Yime 目录权限。",
            )
        return (
            "正常",
            f"可用于导入导出：{exchange_dir}",
            None,
        )

    def _check_runtime_candidate_json_file(self) -> tuple[str, str, Optional[str]]:
        runtime_json_path = Path(getattr(self, "runtime_candidates_json_path", "") or "")
        if not str(runtime_json_path):
            return (
                "警告",
                "当前未配置运行时 JSON 导出文件路径",
                "请检查运行时编码表路径配置。",
            )
        if not runtime_json_path.exists():
            return (
                "警告",
                f"未找到文件：{runtime_json_path}",
                "请重新生成运行时 JSON 导出文件。",
            )
        if not runtime_json_path.is_file():
            return (
                "警告",
                f"路径不是文件：{runtime_json_path}",
                "请检查运行时 JSON 导出路径是否被目录占用。",
            )
        try:
            size_bytes = runtime_json_path.stat().st_size
            preview = runtime_json_path.read_text(encoding="utf-8")
        except OSError as exc:
            return (
                "警告",
                f"文件不可读：{runtime_json_path}（{exc}）",
                "请检查文件权限或同步状态。",
            )
        if size_bytes <= 0 or not preview.strip():
            return (
                "警告",
                f"文件为空：{runtime_json_path}",
                "请重新生成运行时 JSON 导出文件。",
            )

        runtime_source = str(getattr(self, "runtime_decoder_source", "unknown") or "unknown").lower()
        if runtime_source == "json":
            return (
                "正常",
                f"已加载：{runtime_json_path}（{size_bytes} 字节）",
                None,
            )
        return (
            "警告",
            f"文件存在：{runtime_json_path}（{size_bytes} 字节），但当前未启用",
            "请检查文件内容是否有效，或是否仍是 Git LFS 指针。",
        )

    def _check_runtime_candidate_json_freshness(self) -> tuple[str, str, Optional[str]]:
        runtime_json_path = Path(getattr(self, "runtime_candidates_json_path", "") or "")
        if not str(runtime_json_path) or not runtime_json_path.exists() or not runtime_json_path.is_file():
            return (
                "警告",
                "当前无法判断运行时 JSON 新鲜度",
                "请先确认运行时 JSON 导出文件已生成。",
            )

        try:
            modified_at = datetime.fromtimestamp(runtime_json_path.stat().st_mtime, tz=timezone.utc)
        except OSError as exc:
            return (
                "警告",
                f"无法读取文件修改时间：{runtime_json_path}（{exc}）",
                "请检查文件权限或同步状态。",
            )

        age_seconds = max((datetime.now(timezone.utc) - modified_at).total_seconds(), 0.0)
        timestamp_text = modified_at.strftime("%Y-%m-%d %H:%M:%S UTC")
        if age_seconds <= 24 * 60 * 60:
            return ("正常", f"运行时 JSON 最近更新于 {timestamp_text}", None)
        if age_seconds <= 7 * 24 * 60 * 60:
            return (
                "提示",
                f"运行时 JSON 最近更新于 {timestamp_text}（已超过 24 小时）",
                "若候选结果与预期不一致，可重新生成运行时 JSON。",
            )
        return (
            "警告",
            f"运行时 JSON 最近更新于 {timestamp_text}（已超过 7 天）",
            "建议重新生成运行时 JSON，避免使用过旧数据。",
        )

    def _check_ui_settings_file(self) -> tuple[str, str, Optional[str]]:
        settings_path = Path(getattr(self, "ui_settings_path", "") or "")
        if not str(settings_path):
            return (
                "警告",
                "当前未配置设置文件路径",
                "请检查用户数据目录解析是否正常。",
            )
        if settings_path.exists() and settings_path.is_file():
            return ("正常", f"已定位：{settings_path}", None)
        return (
            "提示",
            f"路径已配置：{settings_path}（尚未落盘）",
            "可通过“打开设置文件”先生成默认配置。",
        )

    def _check_user_lexicon_store(self) -> tuple[str, str, Optional[str]]:
        user_db_path = Path(getattr(self, "user_db_path", "") or "")
        if not str(user_db_path):
            return (
                "警告",
                "当前未配置用户词库数据库路径",
                "请检查用户数据目录解析是否正常。",
            )
        if user_db_path.exists() and user_db_path.is_file():
            return ("正常", f"已就绪：{user_db_path}", None)
        return (
            "提示",
            f"数据库尚未生成：{user_db_path}",
            "首次加入或导入用户词条后会自动创建。",
        )

    def _check_runtime_entry(self) -> tuple[str, str, Optional[str]]:
        entry_label = str(getattr(self, "runtime_entry_label", "") or "").strip()
        if entry_label:
            return ("正常", entry_label, None)
        return (
            "提示",
            "当前未识别运行入口",
            "建议优先使用 python run_input_method.py 或 python -m yime.input_method.app。",
        )

    def _build_runtime_data_guidance(self) -> str:
        runtime_source = str(getattr(self, "runtime_decoder_source", "unknown") or "unknown").lower()
        runtime_warning = str(getattr(self, "runtime_decoder_warning", "") or "").strip()
        runtime_json_path = Path(getattr(self, "runtime_candidates_json_path", "") or "")
        if runtime_source == "json" and not runtime_warning:
            return ""

        lines = ["运行时数据指引："]
        if str(runtime_json_path):
            lines.append(f"1. 先检查文件：{runtime_json_path}")
        else:
            lines.append("1. 先检查运行时 JSON 导出文件路径是否已配置。")
        lines.append("2. 若文件缺失、为空或明显过旧，可在仓库根目录运行：python -m yime.export_runtime_candidates_json")
        lines.append("3. 若仍回退到 SQLite，请打开 docs/help/troubleshooting.md 查看“候选词为空或结果不完整”。")
        lines.append("4. 如果文件存在但仍未启用，优先检查它是否还是 Git LFS 指针文件。")
        return "\n".join(lines)

    def _build_runtime_diagnostic_items(
        self,
        *,
        wake_text: Optional[str] = None,
        standby_text: Optional[str] = None,
    ) -> list[tuple[str, str, str, Optional[str]]]:
        items: list[tuple[str, str, str, Optional[str]]] = []

        normalized_wake = str(wake_text or "").strip()
        if normalized_wake and normalized_wake != "当前未配置唤醒方式":
            items.append(("唤起方式", "正常", normalized_wake, None))
        else:
            items.append((
                "唤起方式",
                "警告",
                normalized_wake or "当前未配置唤醒方式",
                "请在设置中启用热键或鼠标唤起方式。",
            ))

        normalized_standby = str(standby_text or "").strip()
        if normalized_standby and normalized_standby != "当前未配置休眠方式":
            items.append(("休眠方式", "正常", normalized_standby, None))
        else:
            items.append((
                "休眠方式",
                "警告",
                normalized_standby or "当前未配置休眠方式",
                "请在设置中启用热键或鼠标休眠方式。",
            ))

        hotkey_mode = str(getattr(self, "_hotkey_mode", "unknown") or "unknown")
        should_listen = getattr(self, "_should_listen_for_hotkey", None)
        expects_hotkey = bool(should_listen()) if callable(should_listen) else False
        display_hotkey_getter = getattr(self, "_format_hotkey_label", None)
        display_hotkey = (
            display_hotkey_getter() if callable(display_hotkey_getter)
            else str(getattr(self, "hotkey", "未配置热键") or "未配置热键")
        )
        has_known_conflict = getattr(self, "_has_known_hotkey_conflict", None)
        hotkey_conflict = (
            bool(has_known_conflict(str(getattr(self, "hotkey", "") or "")))
            if callable(has_known_conflict)
            else False
        )
        hotkey_listener = bool(getattr(self, "hotkey_listener", None))
        if hotkey_mode == "disabled":
            items.append(("热键状态", "提示", "当前模式不使用热键会话", None))
        elif expects_hotkey and hotkey_listener and hotkey_conflict:
            items.append((
                "热键状态",
                "警告",
                f"已启用 {display_hotkey}，但与已知系统快捷键冲突",
                "建议改用 Ctrl+Alt+Insert。",
            ))
        elif expects_hotkey and hotkey_listener:
            items.append(("热键状态", "正常", f"已启用 {display_hotkey}", None))
        elif expects_hotkey:
            items.append((
                "热键状态",
                "警告",
                "已配置热键相关唤起/休眠，但当前监听未启用",
                "请检查热键设置，或改用点击唤起模式。",
            ))
        else:
            items.append(("热键状态", "提示", "当前模式不依赖热键", None))

        runtime_source = str(getattr(self, "runtime_decoder_source", "unknown") or "unknown").lower()
        candidate_source = self._describe_runtime_candidate_source()
        if runtime_source == "json":
            items.append(("候选来源", "正常", candidate_source, None))
        else:
            items.append((
                "候选来源",
                "警告",
                candidate_source,
                "请检查运行时 JSON 导出文件是否生成。",
            ))

        items.append(("运行时 JSON 文件", *self._check_runtime_candidate_json_file()))
        items.append(("运行时数据新鲜度", *self._check_runtime_candidate_json_freshness()))

        warning = str(getattr(self, "runtime_decoder_warning", "") or "").strip()
        if warning:
            items.append((
                "运行时编码表",
                "警告",
                warning,
                "请检查运行时 JSON 导出文件或重新生成候选数据。",
            ))
        else:
            items.append(("运行时编码表", "正常", "已启用运行时编码表", None))

        items.append(("设置文件", *self._check_ui_settings_file()))
        items.append(("用户词库状态", *self._check_user_lexicon_store()))
        items.append(("用户词库目录", *self._check_user_lexicon_exchange_dir()))
        items.append(("当前运行入口", *self._check_runtime_entry()))
        return items

    def _render_runtime_diagnostic_summary(
        self,
        *,
        mode_summary: str,
        items: list[tuple[str, str, str, Optional[str]]],
    ) -> str:
        grouped_items: dict[str, list[str]] = {
            "警告": [],
            "提示": [],
            "正常": [],
        }
        for label, status, detail, advice in items:
            line = f"- {label}：{status}。{detail}"
            if advice:
                line = f"{line} 建议：{advice}"
            grouped_items.setdefault(status, []).append(line)

        warning_count = len(grouped_items.get("警告", []))
        notice_count = len(grouped_items.get("提示", []))
        normal_count = len(grouped_items.get("正常", []))

        if warning_count:
            overview = f"诊断结论：发现 {warning_count} 项警告、{notice_count} 项提示；另有 {normal_count} 项正常。"
        elif notice_count:
            overview = f"诊断结论：当前无警告，有 {notice_count} 项提示；另有 {normal_count} 项正常。"
        else:
            overview = f"诊断结论：当前未发现警告或提示，共 {normal_count} 项正常。"

        lines = [mode_summary, overview]
        if warning_count:
            lines.append("需优先处理：")
            lines.extend(grouped_items["警告"])
        if notice_count:
            lines.append("可留意：")
            lines.extend(grouped_items["提示"])
        if normal_count:
            lines.append("已确认正常：")
            lines.extend(grouped_items["正常"])
        return "\n".join(lines)

    def _build_runtime_readiness_summary(
        self,
        *,
        mode_summary: str,
        wake_text: Optional[str] = None,
        standby_text: Optional[str] = None,
    ) -> str:
        items = self._build_runtime_diagnostic_items(
            wake_text=wake_text,
            standby_text=standby_text,
        )
        return self._render_runtime_diagnostic_summary(
            mode_summary=mode_summary,
            items=items,
        )

    def _build_runtime_readiness_display_summary(self) -> str:
        wake_hint = getattr(self, "_wake_trigger_hint", None)
        standby_hint = getattr(self, "_standby_trigger_hint", None)
        wake_text = wake_hint() if callable(wake_hint) else None
        standby_text = standby_hint() if callable(standby_hint) else None

        hotkey_mode = str(getattr(self, "_hotkey_mode", "unknown") or "unknown")
        if hotkey_mode == "hotkey":
            mode_summary = "当前模式：热键模式"
        elif hotkey_mode == "click-only":
            wake_triggers = getattr(self, "wake_triggers", frozenset({"hotkey", "mouse"}))
            standby_triggers = getattr(self, "standby_triggers", frozenset({"hotkey", "mouse"}))
            if wake_triggers == frozenset({"mouse"}) and standby_triggers == frozenset({"mouse"}):
                mode_summary = "当前模式：点击唤起模式（热键不可用）"
            else:
                mode_summary = "当前模式：受限模式（热键当前未启用）"
        elif hotkey_mode == "disabled":
            mode_summary = "当前模式：实验性全局监听模式"
        else:
            mode_summary = "当前模式：待确认"

        return self._build_runtime_readiness_summary(
            mode_summary=mode_summary,
            wake_text=wake_text,
            standby_text=standby_text,
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
        cast(list[tuple[str, str, str, bool]], pending_feedbacks).append(
            (title, message, level, dialog)
        )

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
        normalized = normalize_numeric_pinyin_syllable_spacing(raw_pinyin)
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

        raw_numeric_input = " ".join(numeric_pinyin.split())
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
        if not normalized_marked and normalized_numeric != raw_numeric_input:
            if not any(char.isdigit() for char in raw_numeric_input):
                normalized_marked = raw_numeric_input

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
