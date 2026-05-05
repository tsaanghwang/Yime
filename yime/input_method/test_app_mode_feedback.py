from yime.input_method.app import InputMethodApp
from yime.input_method.app_global import GlobalListenerApp


class _FakeCandidateBox:
    def __init__(self) -> None:
        self.statuses: list[str] = []

    def set_status(self, status: str) -> None:
        self.statuses.append(status)


def test_configure_input_mode_uses_unified_feedback_for_hotkey_mode() -> None:
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
    assert feedback_calls == [
        (
            "输入模式",
            "V1 热键模式已就绪：按 ctrl+alt+insert 唤起输入框；再次按下可回待命。",
            "info",
            False,
        )
    ]
    assert app.candidate_box.statuses == [
        "V1 热键模式已就绪：按 ctrl+alt+insert 唤起输入框；再次按下可回待命。"
    ]


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
