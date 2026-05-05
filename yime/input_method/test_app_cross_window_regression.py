from yime.input_method.app_base import BaseInputMethodApp


class _FakeKeyboardSimulator:
    def __init__(self, events: list[object]) -> None:
        self._events = events

    def send_backspace(self, count: int) -> None:
        self._events.append(("backspace", count))

    def send_ctrl_v(self) -> None:
        self._events.append("ctrl_v")


class _FakeClipboard:
    def __init__(self, events: list[object]) -> None:
        self._events = events

    def copy(self, text: str) -> None:
        self._events.append(("copy", text))


class _FakeCandidateBox:
    def __init__(self, events: list[object]) -> None:
        self._events = events

    def clear_commit_text(self) -> None:
        self._events.append("clear_commit_text")

    def clear_input(self, *, focus_input: bool) -> None:
        self._events.append(("clear_input", focus_input))


def _run_scheduled_callbacks(scheduled: list[tuple[int, object]]) -> None:
    for _delay, callback in scheduled:
        callback()


def test_paste_to_previous_window_reports_missing_target_and_unlocks() -> None:
    app = BaseInputMethodApp.__new__(BaseInputMethodApp)
    events: list[object] = []
    app.keyboard_simulator = _FakeKeyboardSimulator(events)
    app._current_external_target_hwnd = lambda: None
    app._describe_external_target = lambda hwnd=None: "missing"
    app._should_keep_input_after_commit = lambda: False
    app._emit_feedback = lambda title, message, level="info", dialog=False: events.append(
        ("feedback", title, message)
    )
    app._unlock_external_target = lambda: events.append("unlock")
    app._restore_external_window = lambda: events.append("restore_external") or True
    app._schedule_ui = lambda delay, callback: events.append(("scheduled", delay, callback))

    BaseInputMethodApp._paste_to_previous_window(app, "你好")

    assert events == [
        ("feedback", "回贴", "已复制: 你好，未找到上一个窗口"),
        "unlock",
    ]


def test_paste_to_previous_window_reports_restore_failure_and_unlocks() -> None:
    app = BaseInputMethodApp.__new__(BaseInputMethodApp)
    events: list[object] = []
    app.keyboard_simulator = _FakeKeyboardSimulator(events)
    app._current_external_target_hwnd = lambda: 30003
    app._describe_external_target = lambda hwnd=None: "hwnd=30003 标题=Fake 类=Fake"
    app._should_keep_input_after_commit = lambda: False
    app._emit_feedback = lambda title, message, level="info", dialog=False: events.append(
        ("feedback", title, message)
    )
    app._unlock_external_target = lambda: events.append("unlock")
    app._restore_external_window = lambda: False
    app._schedule_ui = lambda delay, callback: events.append(("scheduled", delay, callback))

    BaseInputMethodApp._paste_to_previous_window(app, "你好")

    assert events == [
        (
            "feedback",
            "回贴",
            "已复制: 你好，恢复目标失败：hwnd=30003 标题=Fake 类=Fake",
        ),
        "unlock",
    ]


def test_paste_to_previous_window_replaces_existing_code_and_refocuses_when_keep_input() -> None:
    app = BaseInputMethodApp.__new__(BaseInputMethodApp)
    events: list[object] = []
    scheduled: list[tuple[int, object]] = []
    app.keyboard_simulator = _FakeKeyboardSimulator(events)
    app.last_replace_length = 4
    app._current_external_target_hwnd = lambda: 30003
    app._describe_external_target = lambda hwnd=None: "hwnd=30003 标题=Fake 类=Fake"
    app._should_keep_input_after_commit = lambda: True
    app._emit_feedback = lambda title, message, level="info", dialog=False: events.append(
        ("feedback", title, message)
    )
    app._unlock_external_target = lambda: events.append("unlock")
    app._restore_external_window = lambda: events.append("restore_external") or True
    app._schedule_refocus_candidate_input = lambda: events.append("refocus")
    app._schedule_ui = lambda delay, callback: scheduled.append((delay, callback))

    BaseInputMethodApp._paste_to_previous_window(app, "你好")
    _run_scheduled_callbacks(scheduled)

    assert events == [
        "restore_external",
        "restore_external",
        ("backspace", 4),
        "ctrl_v",
        ("feedback", "回贴", "已替换 4 个编码字符: 你好 -> hwnd=30003 标题=Fake 类=Fake"),
        "refocus",
    ]
    assert [delay for delay, _callback in scheduled] == [40, 80, 170, 280, 320]


def test_paste_to_previous_window_pastes_without_backspace_and_unlocks_when_not_keep_input() -> None:
    app = BaseInputMethodApp.__new__(BaseInputMethodApp)
    events: list[object] = []
    scheduled: list[tuple[int, object]] = []
    app.keyboard_simulator = _FakeKeyboardSimulator(events)
    app.last_replace_length = 0
    app._current_external_target_hwnd = lambda: 30003
    app._describe_external_target = lambda hwnd=None: "hwnd=30003 标题=Fake 类=Fake"
    app._should_keep_input_after_commit = lambda: False
    app._emit_feedback = lambda title, message, level="info", dialog=False: events.append(
        ("feedback", title, message)
    )
    app._unlock_external_target = lambda: events.append("unlock")
    app._restore_external_window = lambda: events.append("restore_external") or True
    app._schedule_refocus_candidate_input = lambda: events.append("refocus")
    app._schedule_ui = lambda delay, callback: scheduled.append((delay, callback))

    BaseInputMethodApp._paste_to_previous_window(app, "你好")
    _run_scheduled_callbacks(scheduled)

    assert events == [
        "restore_external",
        "restore_external",
        "ctrl_v",
        ("feedback", "回贴", "已回贴: 你好 -> hwnd=30003 标题=Fake 类=Fake"),
        "unlock",
    ]
    assert [delay for delay, _callback in scheduled] == [40, 80, 180, 220]


def test_commit_candidate_box_text_schedules_paste_and_clears_commit_text_when_target_exists() -> None:
    app = BaseInputMethodApp.__new__(BaseInputMethodApp)
    events: list[object] = []
    scheduled: list[tuple[int, object]] = []
    app.clipboard = _FakeClipboard(events)
    app.candidate_box = _FakeCandidateBox(events)
    app.last_replace_length = 9
    app._current_external_target_hwnd = lambda: 30003
    app._unlock_external_target = lambda: events.append("unlock")
    app._paste_to_previous_window = lambda text: events.append(("paste", text))
    app._schedule_ui = lambda delay, callback: scheduled.append((delay, callback))

    BaseInputMethodApp._commit_candidate_box_text(app, "你好")
    _run_scheduled_callbacks(scheduled)

    assert app.last_replace_length == 0
    assert events == [
        ("copy", "你好"),
        "clear_commit_text",
        ("clear_input", False),
        ("paste", "你好"),
    ]
    assert [delay for delay, _callback in scheduled] == [50]


def test_commit_candidate_box_text_unlocks_without_scheduling_paste_when_no_target() -> None:
    app = BaseInputMethodApp.__new__(BaseInputMethodApp)
    events: list[object] = []
    scheduled: list[tuple[int, object]] = []
    app.clipboard = _FakeClipboard(events)
    app.candidate_box = _FakeCandidateBox(events)
    app.last_replace_length = 9
    app._current_external_target_hwnd = lambda: None
    app._unlock_external_target = lambda: events.append("unlock")
    app._paste_to_previous_window = lambda text: events.append(("paste", text))
    app._schedule_ui = lambda delay, callback: scheduled.append((delay, callback))

    BaseInputMethodApp._commit_candidate_box_text(app, "你好")

    assert app.last_replace_length == 9
    assert events == [
        ("copy", "你好"),
        "unlock",
        "clear_commit_text",
        ("clear_input", False),
    ]
    assert scheduled == []
