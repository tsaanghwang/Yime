from yime.input_method.app import InputMethodApp
from yime.input_method.app_base import BaseInputMethodApp
from yime.input_method.app_global import GlobalListenerApp


class _FakeCandidateBox:
    def __init__(self) -> None:
        self.statuses: list[str] = []

    def set_status(self, status: str) -> None:
        self.statuses.append(status)


def test_configure_input_mode_uses_unified_feedback_for_hotkey_mode(tmp_path) -> None:
    app = InputMethodApp.__new__(InputMethodApp)
    app.input_mode = "hotkey"
    app.hotkey = InputMethodApp._DEFAULT_HOTKEY
    app.hotkey_listener = object()
    app._hotkey_mode = "unknown"
    app.candidate_box = _FakeCandidateBox()

    post_commit_behaviors: list[str] = []
    setup_calls: list[str] = []
    resume_calls: list[str] = []
    feedback_calls: list[tuple[str, str, str, bool]] = []

    app._set_post_commit_behavior = lambda behavior: post_commit_behaviors.append(behavior)
    app._setup_hotkey = lambda: setup_calls.append("setup")
    app._resume_global_capture = lambda: resume_calls.append("resume")
    app._format_hotkey_label = lambda: "ctrl+alt+insert"
    app.runtime_entry_label = "python run_input_method.py"
    app.user_lexicon_exchange_dir = tmp_path / "UserLexicon"
    app.user_db_path = tmp_path / "user_lexicon.db"
    app.user_db_path.write_text("db", encoding="utf-8")
    app.ui_settings_path = tmp_path / "ui_settings.json"
    app.ui_settings_path.write_text("{}", encoding="utf-8")
    app.runtime_candidates_json_path = tmp_path / "runtime_candidates_by_code_true.json"
    app.runtime_candidates_json_path.write_text('{"by_code": {}}', encoding="utf-8")
    app.runtime_decoder_source = "json"
    app.runtime_decoder_warning = ""
    app._is_global_listener_mode = InputMethodApp._is_global_listener_mode.__get__(app, InputMethodApp)
    app._emit_feedback = lambda title, message, level="info", dialog=False: (
        feedback_calls.append((title, message, level, dialog)),
        app.candidate_box.set_status(message),
    )

    InputMethodApp._configure_input_mode(app)

    assert setup_calls == ["setup"]
    assert post_commit_behaviors == ["keep-input"]
    assert resume_calls == []
    assert app._hotkey_mode == "hotkey"
    assert len(feedback_calls) == 1
    assert feedback_calls[0][0] == "输入模式"
    assert feedback_calls[0][2:] == ("info", False)
    message = feedback_calls[0][1]
    assert "当前模式：热键模式" in message
    assert "诊断结论：当前未发现警告或提示，共 11 项正常。" in message
    assert "已确认正常：" in message
    assert "- 唤起方式：正常。按 ctrl+alt+insert 或 点击右下角的'音'图标" in message
    assert "- 休眠方式：正常。再次按 ctrl+alt+insert 或 右键候选框" in message
    assert "- 热键状态：正常。已启用 ctrl+alt+insert" in message
    assert "- 候选来源：正常。运行时 JSON 导出文件" in message
    assert f"- 运行时 JSON 文件：正常。已加载：{app.runtime_candidates_json_path}" in message
    assert "- 运行时数据新鲜度：正常。运行时 JSON 最近更新于" in message
    assert "- 运行时编码表：正常。已启用运行时编码表" in message
    assert f"- 设置文件：正常。已定位：{app.ui_settings_path}" in message
    assert f"- 用户词库状态：正常。已就绪：{app.user_db_path}" in message
    assert f"- 用户词库目录：正常。可用于导入导出：{app.user_lexicon_exchange_dir}" in message
    assert "- 当前运行入口：正常。python run_input_method.py" in message
    assert app.candidate_box.statuses == [message]


def test_build_runtime_readiness_summary_includes_structured_diagnostics_and_advice(tmp_path) -> None:
    app = BaseInputMethodApp.__new__(BaseInputMethodApp)
    occupied_path = tmp_path / "UserLexicon"
    occupied_path.write_text("occupied", encoding="utf-8")
    missing_runtime_json = tmp_path / "runtime_candidates_by_code_true.json"
    app.hotkey = "<ctrl>+<shift>+y"
    app.hotkey_listener = object()
    app.user_lexicon_exchange_dir = occupied_path
    app.runtime_candidates_json_path = missing_runtime_json
    app.runtime_decoder_source = "sqlite"
    app.runtime_decoder_warning = "运行时编码表未启用"
    app._hotkey_mode = "hotkey"
    app._format_hotkey_label = lambda: "Ctrl+Shift+Y"
    app.runtime_entry_label = "python -m yime.input_method.app"
    app.ui_settings_path = tmp_path / "ui_settings.json"
    app.ui_settings_path.write_text("{}", encoding="utf-8")
    app.user_db_path = tmp_path / "user_lexicon.db"
    app.user_db_path.write_text("db", encoding="utf-8")
    app._should_listen_for_hotkey = lambda: True
    app._has_known_hotkey_conflict = lambda hotkey: hotkey == "<ctrl>+<shift>+y"

    summary = BaseInputMethodApp._build_runtime_readiness_summary(
        app,
        mode_summary="当前模式：受限模式（热键当前未启用）",
        wake_text="点击右下角的'音'图标",
        standby_text="右键候选框",
    )

    assert "当前模式：受限模式（热键当前未启用）" in summary
    assert "诊断结论：发现 6 项警告、0 项提示；另有 5 项正常。" in summary
    assert "需优先处理：" in summary
    assert "已确认正常：" in summary
    assert "- 唤起方式：正常。点击右下角的'音'图标" in summary
    assert "- 休眠方式：正常。右键候选框" in summary
    assert "- 热键状态：警告。已启用 Ctrl+Shift+Y，但与已知系统快捷键冲突 建议：建议改用 Ctrl+Alt+Insert。" in summary
    assert "- 候选来源：警告。SQLite runtime_candidates 回退 建议：请检查运行时 JSON 导出文件是否生成。" in summary
    assert f"- 运行时 JSON 文件：警告。未找到文件：{missing_runtime_json} 建议：请重新生成运行时 JSON 导出文件。" in summary
    assert "- 运行时数据新鲜度：警告。当前无法判断运行时 JSON 新鲜度 建议：请先确认运行时 JSON 导出文件已生成。" in summary
    assert "- 运行时编码表：警告。运行时编码表未启用 建议：请检查运行时 JSON 导出文件或重新生成候选数据。" in summary
    assert f"- 设置文件：正常。已定位：{app.ui_settings_path}" in summary
    assert f"- 用户词库状态：正常。已就绪：{app.user_db_path}" in summary
    assert f"- 用户词库目录：警告。路径已被文件占用：{occupied_path} 建议：请删除同名文件或改用可写目录。" in summary
    assert "- 当前运行入口：正常。python -m yime.input_method.app" in summary


def test_return_hotkey_session_to_standby_uses_unified_feedback() -> None:
    app = InputMethodApp.__new__(InputMethodApp)
    app.hotkey = "<ctrl>+<shift>+y"
    app.last_replace_length = 4
    app._display_input_buffer = "abcd"
    app._passive_standby_reason = "manual"
    app.candidate_box = _FakeCandidateBox()
    app._manual_session_trigger = "hotkey"

    events: list[object] = []
    feedback_calls: list[tuple[str, str, str, bool]] = []

    app.input_manager = type(
        "FakeInputManager",
        (),
        {"clear_buffer": lambda self, notify=False: events.append(("clear_buffer", notify))},
    )()
    app.candidate_box.clear_input = lambda focus_input=False: events.append(("clear", focus_input))
    app.candidate_box.clear_commit_text = lambda: events.append("clear_commit")
    app.candidate_box.set_manual_input_enabled = lambda enabled: events.append(("manual", enabled))
    app.candidate_box.show_standby = lambda: events.append("standby")
    app._restore_external_window = lambda: events.append("restore_external") or True
    app._unlock_external_target = lambda: events.append("unlock")
    app._remember_manual_session_context = lambda trigger_source, target_hwnd: events.append(("remember", trigger_source, target_hwnd))
    app._current_manual_target_hwnd = lambda: 24680
    app._is_hotkey_wake_enabled = lambda: True
    app._is_mouse_wake_enabled = lambda: False
    app._format_hotkey_label = lambda: "ctrl+shift+y"
    app._emit_feedback = lambda title, message, level="info", dialog=False: (
        feedback_calls.append((title, message, level, dialog)),
        app.candidate_box.set_status(message),
    )

    InputMethodApp._return_hotkey_session_to_standby(app)

    assert app.last_replace_length == 0
    assert app._display_input_buffer == ""
    assert app._passive_standby_reason == "idle"
    assert ("clear_buffer", False) in events
    assert ("clear", False) in events
    assert "clear_commit" in events
    assert "restore_external" in events
    assert "unlock" in events
    assert feedback_calls == [
        (
            "会话",
            "V1 已回待命：按 ctrl+shift+y 可再次唤起输入框。",
            "info",
            False,
        )
    ]
    assert app.candidate_box.statuses == ["V1 已回待命：按 ctrl+shift+y 可再次唤起输入框。"]


def test_global_listener_run_uses_unified_feedback_for_ready_status() -> None:
    app = GlobalListenerApp.__new__(GlobalListenerApp)
    app.candidate_box = _FakeCandidateBox()
    app.candidate_box.run = lambda: None
    app.enable_pause_toggle = False
    app.is_passthrough_enabled = False

    feedback_calls: list[tuple[str, str, str, bool]] = []

    app._emit_feedback = lambda title, message, level="info", dialog=False: (
        feedback_calls.append((title, message, level, dialog)),
        app.candidate_box.set_status(message),
    )

    class _FakeKeyboardListener:
        def start(self) -> None:
            return None

        def is_active(self) -> bool:
            return False

    app._on_key_press = lambda key_info: True

    original_keyboard_listener = GlobalListenerApp.run.__globals__["KeyboardListener"] if "KeyboardListener" in GlobalListenerApp.run.__globals__ else None
    GlobalListenerApp.run.__globals__["KeyboardListener"] = lambda on_key_press: _FakeKeyboardListener()
    try:
        GlobalListenerApp.run(app)
    finally:
        if original_keyboard_listener is None:
            del GlobalListenerApp.run.__globals__["KeyboardListener"]
        else:
            GlobalListenerApp.run.__globals__["KeyboardListener"] = original_keyboard_listener

    assert feedback_calls == [
        (
            "输入模式",
            "实验性全局监听模式已就绪：直接监听外部键盘输入",
            "info",
            False,
        )
    ]
    assert app.candidate_box.statuses == ["实验性全局监听模式已就绪：直接监听外部键盘输入"]
