from typing import Any, cast

from pytest import MonkeyPatch

from yime.input_method.app import InputMethodApp


def test_input_method_app_factory_wires_user_lexicon_callbacks(monkeypatch: MonkeyPatch) -> None:
    captured: dict[str, Any] = {}

    def _noop_text(_text: str) -> None:
        return None

    def _format_text(text: str) -> str:
        return text

    def _resolve_manual_key_output(_physical_key: str, _modifiers: object) -> str:
        return ""

    def _on_input_change(_event: object = None) -> None:
        return None

    def _noop_value(_value: object) -> None:
        return None

    def _noop() -> None:
        return None

    def _hotkey_summary() -> str:
        return "当前热键：ctrl+alt+insert"

    def _runtime_readiness_summary() -> str:
        return "当前模式：热键模式"

    def _runtime_data_guidance() -> str:
        return "运行时数据指引"

    def _hotkey_label() -> str:
        return "Ctrl+Alt+Insert"

    def _on_hotkey_change(_hotkey: object) -> bool:
        return True

    def _enabled() -> bool:
        return True

    class _FakeCandidateBox:
        def __init__(self, **kwargs: Any) -> None:
            captured.update(kwargs)

    monkeypatch.setattr("yime.input_method.app.CandidateBox", _FakeCandidateBox)

    app = cast(Any, InputMethodApp.__new__(InputMethodApp))
    app.font_family = "音元"
    app._on_candidate_select = _noop_text
    app._format_input_outline = _format_text
    app._format_projected_code = _format_text
    app._resolve_manual_key_output = _resolve_manual_key_output
    app._format_visible_input = _format_text
    app._on_input_change = _on_input_change
    app._copy_candidate = _noop_value
    app._commit_candidate_box_text = _noop_text
    app._on_candidate_page_size_change = _noop_value
    app._on_candidate_layout_change = _noop_value
    app._on_wake_trigger_mode_change = _noop_value
    app._on_standby_trigger_mode_change = _noop_value
    app._on_mouse_wake_enabled_change = _noop_value
    app._on_mouse_standby_enabled_change = _noop_value
    app._on_ui_scale_change = _noop_value
    app._on_active_alpha_change = _noop_value
    app._on_foreground_color_change = _noop_value
    app._on_background_color_change = _noop_value
    app._on_active_topmost_change = _noop_value
    app._on_reverse_lookup_display_mode_change = _noop_value
    app._reload_user_lexicon_from_menu = _noop
    app._edit_user_lexicon_from_menu = _noop
    app._import_user_lexicon_from_menu = _noop
    app._export_user_lexicon_from_menu = _noop
    app._open_settings_file = _noop
    app._open_user_data_dir = _noop
    app._open_runtime_data_dir = _noop
    app._open_troubleshooting_doc = _noop
    app._build_hotkey_summary = _hotkey_summary
    app._build_runtime_readiness_display_summary = _runtime_readiness_summary
    app._build_runtime_data_guidance = _runtime_data_guidance
    app._format_hotkey_label = _hotkey_label
    app._on_hotkey_change = _on_hotkey_change
    app._add_current_input_to_user_lexicon = _noop
    app._delete_current_input_from_user_lexicon = _noop
    app._resume_from_standby = _noop
    app._return_mouse_session_to_standby = _noop
    app._close = _noop
    app.hover_tip_enabled = True
    app._is_mouse_wake_enabled = _enabled
    app._is_mouse_standby_enabled = _enabled
    app.candidate_page_size = 7
    app.candidate_layout = "vertical"

    cast(Any, InputMethodApp)._create_candidate_box(app)

    assert captured["max_candidates"] == 7
    assert captured["candidate_layout"] == "vertical"
    assert captured["on_candidate_page_size_change"] is app._on_candidate_page_size_change
    assert captured["on_candidate_layout_change"] is app._on_candidate_layout_change
    assert captured["on_wake_trigger_mode_change"] is app._on_wake_trigger_mode_change
    assert captured["on_standby_trigger_mode_change"] is app._on_standby_trigger_mode_change
    assert captured["on_mouse_wake_enabled_change"] is app._on_mouse_wake_enabled_change
    assert captured["on_mouse_standby_enabled_change"] is app._on_mouse_standby_enabled_change
    assert captured["on_ui_scale_change"] is app._on_ui_scale_change
    assert captured["on_active_alpha_change"] is app._on_active_alpha_change
    assert captured["on_foreground_color_change"] is app._on_foreground_color_change
    assert captured["on_background_color_change"] is app._on_background_color_change
    assert captured["on_active_topmost_change"] is app._on_active_topmost_change
    assert captured["on_reverse_lookup_display_mode_change"] is app._on_reverse_lookup_display_mode_change
    assert captured["on_reload_user_lexicon"] is app._reload_user_lexicon_from_menu
    assert captured["on_edit_user_lexicon"] is app._edit_user_lexicon_from_menu
    assert captured["on_import_user_lexicon"] is app._import_user_lexicon_from_menu
    assert captured["on_export_user_lexicon"] is app._export_user_lexicon_from_menu
    assert captured["on_open_settings_file"] is app._open_settings_file
    assert captured["on_open_runtime_data_dir"] is app._open_runtime_data_dir
    assert captured["on_open_troubleshooting_doc"] is app._open_troubleshooting_doc
    assert captured["on_open_user_data_dir"] is app._open_user_data_dir
    assert captured["on_hotkey_summary_request"] is app._build_hotkey_summary
    assert captured["on_runtime_readiness_summary_request"] is app._build_runtime_readiness_display_summary
    assert captured["on_runtime_data_guidance_request"] is app._build_runtime_data_guidance
    assert captured["on_hotkey_label_request"] is app._format_hotkey_label
    assert captured["on_hotkey_change"] is app._on_hotkey_change
    assert captured["on_add_input_to_user_lexicon"] is app._add_current_input_to_user_lexicon
    assert captured["on_delete_input_from_user_lexicon"] is app._delete_current_input_from_user_lexicon
    assert captured["on_feedback"].__self__ is app
    assert captured["on_feedback"].__func__ is app._emit_feedback.__func__
