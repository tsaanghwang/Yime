import json
from pathlib import Path

from yime.input_method.app_base import BaseInputMethodApp


def test_load_ui_settings_returns_empty_when_file_missing(tmp_path: Path) -> None:
    app = BaseInputMethodApp.__new__(BaseInputMethodApp)
    app.ui_settings_path = tmp_path / "ui_settings.json"

    assert app._load_ui_settings() == {}


def test_on_candidate_page_size_change_persists_setting(tmp_path: Path) -> None:
    page_size_calls: list[int] = []
    layout_calls: list[str] = []
    mouse_wake_calls: list[bool] = []
    mouse_standby_calls: list[bool] = []
    ui_scale_calls: list[int] = []
    alpha_calls: list[int] = []
    foreground_calls: list[str] = []
    background_calls: list[str] = []
    topmost_calls: list[bool] = []

    class _FakeCandidateBox:
        def set_page_size(self, page_size: int) -> None:
            page_size_calls.append(page_size)

        def set_candidate_layout(self, layout: str) -> None:
            layout_calls.append(layout)

        def set_mouse_wake_enabled(self, enabled: bool) -> None:
            mouse_wake_calls.append(enabled)

        def set_mouse_standby_enabled(self, enabled: bool) -> None:
            mouse_standby_calls.append(enabled)

        def set_ui_scale(self, scale_percent: int) -> None:
            ui_scale_calls.append(scale_percent)

        def set_active_alpha_percent(self, alpha_percent: int) -> None:
            alpha_calls.append(alpha_percent)

        def set_foreground_color(self, color: str) -> None:
            foreground_calls.append(color)

        def set_background_color(self, color: str) -> None:
            background_calls.append(color)

        def set_active_topmost_enabled(self, enabled: bool) -> None:
            topmost_calls.append(enabled)

    app = BaseInputMethodApp.__new__(BaseInputMethodApp)
    app.user_data_dir = tmp_path
    app.ui_settings_path = tmp_path / "ui_settings.json"
    app.ui_settings = {}
    app.candidate_box = _FakeCandidateBox()
    app.candidate_page_size = 5
    app.candidate_layout = "horizontal"
    app._mouse_wake_enabled_setting = True
    app._mouse_standby_enabled_setting = True
    app.ui_scale_percent = 100
    app.active_alpha_percent = 97
    app.foreground_color = "#111827"
    app.background_color = "#f0f0f0"
    app.active_topmost_enabled = True

    app._on_candidate_page_size_change(8)
    app._on_candidate_layout_change("vertical")
    app._on_mouse_wake_enabled_change(False)
    app._on_mouse_standby_enabled_change(False)
    app._on_ui_scale_change(110)
    app._on_active_alpha_change(85)
    app._on_foreground_color_change("#166534")
    app._on_background_color_change("#f7f3e8")
    app._on_active_topmost_change(False)

    assert page_size_calls == [8]
    assert layout_calls == ["vertical"]
    assert mouse_wake_calls == [False]
    assert mouse_standby_calls == [False]
    assert ui_scale_calls == [110]
    assert alpha_calls == [85]
    assert foreground_calls == ["#166534"]
    assert background_calls == ["#f7f3e8"]
    assert topmost_calls == [False]
    assert app.candidate_page_size == 8
    assert app.ui_settings["candidate_page_size"] == 8
    assert app.ui_settings["candidate_layout"] == "vertical"
    assert app.ui_settings["mouse_wake_enabled"] is False
    assert app.ui_settings["mouse_standby_enabled"] is False
    assert app.ui_settings["ui_scale_percent"] == 110
    assert app.ui_settings["active_alpha_percent"] == 85
    assert app.ui_settings["foreground_color"] == "#166534"
    assert app.ui_settings["background_color"] == "#f7f3e8"
    assert app.ui_settings["active_topmost_enabled"] is False
    assert json.loads(app.ui_settings_path.read_text(encoding="utf-8")) == {
        "candidate_page_size": 8,
        "candidate_layout": "vertical",
        "mouse_wake_enabled": False,
        "mouse_standby_enabled": False,
        "ui_scale_percent": 110,
        "active_alpha_percent": 85,
        "foreground_color": "#166534",
        "background_color": "#f7f3e8",
        "active_topmost_enabled": False,
    }


def test_load_candidate_page_size_is_clamped(tmp_path: Path) -> None:
    settings_path = tmp_path / "ui_settings.json"
    settings_path.write_text(
        '{"candidate_page_size": 99, "candidate_layout": "vertical", "ui_scale_percent": 500, "active_alpha_percent": 10}\n',
        encoding="utf-8",
    )

    app = BaseInputMethodApp.__new__(BaseInputMethodApp)
    app.ui_settings_path = settings_path

    payload = app._load_ui_settings()

    assert app._normalize_candidate_page_size(payload.get("candidate_page_size")) == 9
    assert app._normalize_candidate_layout_setting(payload.get("candidate_layout")) == "vertical"
    assert app._normalize_ui_scale_percent(payload.get("ui_scale_percent")) == 120
    assert app._normalize_active_alpha_percent(payload.get("active_alpha_percent")) == 80


def test_trigger_mode_change_persists_and_updates_runtime_state(tmp_path: Path) -> None:
    from yime.input_method.app import InputMethodApp

    mouse_wake_calls: list[bool] = []
    mouse_standby_calls: list[bool] = []
    hotkey_events: list[str] = []

    class _FakeVar:
        def __init__(self) -> None:
            self.value = "both"

        def set(self, value: str) -> None:
            self.value = value

        def get(self) -> str:
            return self.value

    class _FakeCandidateBox:
        def __init__(self) -> None:
            self.wake_trigger_mode_var = _FakeVar()
            self.standby_trigger_mode_var = _FakeVar()

        def set_mouse_wake_enabled(self, enabled: bool) -> None:
            mouse_wake_calls.append(enabled)

        def set_mouse_standby_enabled(self, enabled: bool) -> None:
            mouse_standby_calls.append(enabled)

    class _FakeListener:
        def start(self) -> None:
            hotkey_events.append("start")

        def stop(self) -> None:
            hotkey_events.append("stop")

    app = InputMethodApp.__new__(InputMethodApp)
    app.user_data_dir = tmp_path
    app.ui_settings_path = tmp_path / "ui_settings.json"
    app.ui_settings = {}
    app.candidate_box = _FakeCandidateBox()
    app.candidate_page_size = 5
    app.candidate_layout = "horizontal"
    app._mouse_wake_enabled_setting = True
    app._mouse_standby_enabled_setting = True
    app.ui_scale_percent = 100
    app.active_alpha_percent = 97
    app.foreground_color = "#111827"
    app.background_color = "#f0f0f0"
    app.active_topmost_enabled = True
    app.wake_triggers = frozenset({"hotkey", "mouse"})
    app.standby_triggers = frozenset({"hotkey", "mouse"})
    app.hotkey = "<ctrl>+<alt>+<insert>"
    app.hotkey_listener = None
    app._hotkey_mode = "unknown"
    app._setup_hotkey = lambda: hotkey_events.append("setup") or setattr(app, "hotkey_listener", _FakeListener())
    app._sync_hotkey_listener_for_trigger_modes = InputMethodApp._sync_hotkey_listener_for_trigger_modes.__get__(app, InputMethodApp)
    app._on_wake_trigger_mode_change = InputMethodApp._on_wake_trigger_mode_change.__get__(app, InputMethodApp)
    app._on_standby_trigger_mode_change = InputMethodApp._on_standby_trigger_mode_change.__get__(app, InputMethodApp)
    app._normalize_trigger_mode = InputMethodApp._normalize_trigger_mode
    app._trigger_mode_to_label = InputMethodApp._trigger_mode_to_label.__get__(app, InputMethodApp)
    app._is_mouse_wake_enabled = InputMethodApp._is_mouse_wake_enabled.__get__(app, InputMethodApp)
    app._is_mouse_standby_enabled = InputMethodApp._is_mouse_standby_enabled.__get__(app, InputMethodApp)
    app._should_listen_for_hotkey = InputMethodApp._should_listen_for_hotkey.__get__(app, InputMethodApp)
    app._save_ui_settings = BaseInputMethodApp._save_ui_settings.__get__(app, BaseInputMethodApp)

    app._on_wake_trigger_mode_change("mouse")
    app._on_standby_trigger_mode_change("hotkey")

    assert app.wake_triggers == frozenset({"mouse"})
    assert app.standby_triggers == frozenset({"hotkey"})
    assert mouse_wake_calls == [True]
    assert mouse_standby_calls == [False]
    assert app.candidate_box.wake_trigger_mode_var.get() == "mouse"
    assert app.candidate_box.standby_trigger_mode_var.get() == "hotkey"
    assert app.ui_settings["wake_trigger_mode"] == "mouse"
    assert app.ui_settings["standby_trigger_mode"] == "hotkey"
    assert hotkey_events == ["setup", "start"]


def test_hotkey_change_persists_and_rebinds_listener(tmp_path: Path) -> None:
    from yime.input_method.app import InputMethodApp

    hotkey_events: list[str] = []
    feedback_calls: list[tuple[str, str]] = []

    class _FakeListener:
        def start(self) -> None:
            hotkey_events.append("start")

        def stop(self) -> None:
            hotkey_events.append("stop")

    app = InputMethodApp.__new__(InputMethodApp)
    app.user_data_dir = tmp_path
    app.ui_settings_path = tmp_path / "ui_settings.json"
    app.ui_settings = {}
    app.candidate_page_size = 5
    app.candidate_layout = "horizontal"
    app._mouse_wake_enabled_setting = True
    app._mouse_standby_enabled_setting = True
    app.ui_scale_percent = 100
    app.active_alpha_percent = 97
    app.foreground_color = "#111827"
    app.background_color = "#f0f0f0"
    app.active_topmost_enabled = True
    app.wake_triggers = frozenset({"hotkey", "mouse"})
    app.standby_triggers = frozenset({"hotkey", "mouse"})
    app.hotkey = "<ctrl>+<alt>+<insert>"
    app.hotkey_listener = _FakeListener()
    app._hotkey_mode = "hotkey"
    app._setup_hotkey = lambda: hotkey_events.append("setup") or setattr(app, "hotkey_listener", _FakeListener())
    app._sync_hotkey_listener_for_trigger_modes = InputMethodApp._sync_hotkey_listener_for_trigger_modes.__get__(app, InputMethodApp)
    app._should_listen_for_hotkey = InputMethodApp._should_listen_for_hotkey.__get__(app, InputMethodApp)
    app._is_hotkey_wake_enabled = InputMethodApp._is_hotkey_wake_enabled.__get__(app, InputMethodApp)
    app._is_hotkey_standby_enabled = InputMethodApp._is_hotkey_standby_enabled.__get__(app, InputMethodApp)
    app._save_ui_settings = BaseInputMethodApp._save_ui_settings.__get__(app, BaseInputMethodApp)
    app._emit_feedback = lambda title, message, level="info", dialog=False: feedback_calls.append((title, message))

    changed = InputMethodApp._on_hotkey_change(app, "Ctrl+Shift+Y")

    assert changed is True
    assert app.hotkey == "<ctrl>+<shift>+y"
    assert app.ui_settings["hotkey"] == "<ctrl>+<shift>+y"
    assert hotkey_events == ["stop", "setup", "start"]
    assert feedback_calls == [("快捷键", "唤起热键已更新为 Ctrl+Shift+Y。")]
    assert json.loads(app.ui_settings_path.read_text(encoding="utf-8"))["hotkey"] == "<ctrl>+<shift>+y"
