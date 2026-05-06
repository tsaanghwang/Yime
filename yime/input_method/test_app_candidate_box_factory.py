from yime.input_method.app import InputMethodApp


def test_input_method_app_factory_wires_user_lexicon_callbacks(monkeypatch) -> None:
    captured: dict[str, object] = {}

    class _FakeCandidateBox:
        def __init__(self, **kwargs) -> None:
            captured.update(kwargs)

    monkeypatch.setattr("yime.input_method.app.CandidateBox", _FakeCandidateBox)

    app = InputMethodApp.__new__(InputMethodApp)
    app.font_family = "音元"
    app._on_candidate_select = lambda text: None
    app._format_input_outline = lambda text: text
    app._format_projected_code = lambda text: text
    app._resolve_manual_key_output = lambda physical_key, modifiers: ""
    app._format_visible_input = lambda text: text
    app._on_input_change = lambda event=None: None
    app._copy_candidate = lambda index: None
    app._commit_candidate_box_text = lambda text: None
    app._on_candidate_page_size_change = lambda page_size: None
    app._on_candidate_layout_change = lambda layout: None
    app._on_wake_trigger_mode_change = lambda mode: None
    app._on_standby_trigger_mode_change = lambda mode: None
    app._on_mouse_wake_enabled_change = lambda enabled: None
    app._on_mouse_standby_enabled_change = lambda enabled: None
    app._on_ui_scale_change = lambda value: None
    app._on_active_alpha_change = lambda value: None
    app._on_foreground_color_change = lambda value: None
    app._on_background_color_change = lambda value: None
    app._on_active_topmost_change = lambda enabled: None
    app._reload_user_lexicon_from_menu = lambda: None
    app._edit_user_lexicon_from_menu = lambda: None
    app._import_user_lexicon_from_menu = lambda: None
    app._export_user_lexicon_from_menu = lambda: None
    app._open_settings_file = lambda: None
    app._open_runtime_data_dir = lambda: None
    app._open_troubleshooting_doc = lambda: None
    app._build_hotkey_summary = lambda: "当前热键：ctrl+alt+insert"
    app._build_runtime_readiness_display_summary = lambda: "当前模式：热键模式"
    app._build_runtime_data_guidance = lambda: "运行时数据指引"
    app._format_hotkey_label = lambda: "Ctrl+Alt+Insert"
    app._on_hotkey_change = lambda hotkey: True
    app._add_current_input_to_user_lexicon = lambda: None
    app._delete_current_input_from_user_lexicon = lambda: None
    app._resume_from_standby = lambda: None
    app._return_mouse_session_to_standby = lambda: None
    app._close = lambda: None
    app._is_mouse_wake_enabled = lambda: True
    app._is_mouse_standby_enabled = lambda: True
    app.candidate_page_size = 7
    app.candidate_layout = "vertical"

    InputMethodApp._create_candidate_box(app)

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
    assert captured["on_reload_user_lexicon"] is app._reload_user_lexicon_from_menu
    assert captured["on_edit_user_lexicon"] is app._edit_user_lexicon_from_menu
    assert captured["on_import_user_lexicon"] is app._import_user_lexicon_from_menu
    assert captured["on_export_user_lexicon"] is app._export_user_lexicon_from_menu
    assert captured["on_open_settings_file"] is app._open_settings_file
    assert captured["on_open_runtime_data_dir"] is app._open_runtime_data_dir
    assert captured["on_open_troubleshooting_doc"] is app._open_troubleshooting_doc
    assert captured["on_open_user_data_dir"] is app._open_settings_file
    assert captured["on_hotkey_summary_request"] is app._build_hotkey_summary
    assert captured["on_runtime_readiness_summary_request"] is app._build_runtime_readiness_display_summary
    assert captured["on_runtime_data_guidance_request"] is app._build_runtime_data_guidance
    assert captured["on_hotkey_label_request"] is app._format_hotkey_label
    assert captured["on_hotkey_change"] is app._on_hotkey_change
    assert captured["on_add_input_to_user_lexicon"] is app._add_current_input_to_user_lexicon
    assert captured["on_delete_input_from_user_lexicon"] is app._delete_current_input_from_user_lexicon
    assert captured["on_feedback"].__self__ is app
    assert captured["on_feedback"].__func__ is app._emit_feedback.__func__
