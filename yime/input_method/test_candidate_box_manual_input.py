from types import SimpleNamespace

from yime.input_method.ui.candidate_box import CandidateBox
from yime.input_method.ui.manual_input_resolver import ManualInputResolver


class _FakeEntry:
    def __init__(self) -> None:
        self.insert_calls: list[tuple[object, str]] = []

    def insert(self, index: object, text: str) -> None:
        self.insert_calls.append((index, text))


class _FakeRoot:
    def __init__(self) -> None:
        self.after_idle_calls: list[object] = []

    def after_idle(self, callback: object) -> None:
        self.after_idle_calls.append(callback)


def _build_box(entry: _FakeEntry, root: _FakeRoot) -> object:
    return SimpleNamespace(
        input_entry=entry,
        _manual_input_enabled=True,
        _manual_key_output_resolver=lambda key, modifiers: "X",
        _manual_input_transformer=None,
        root=root,
        _on_input_change=lambda: None,
    )


def test_manual_input_keypress_allows_native_ctrl_v(monkeypatch) -> None:
    entry = _FakeEntry()
    root = _FakeRoot()
    box = _build_box(entry, root)
    event = SimpleNamespace(widget=entry, char="", keycode=86, keysym="v")

    monkeypatch.setattr(
        ManualInputResolver,
        "get_manual_key_modifiers",
        classmethod(lambda cls: {"ctrl": True, "alt_gr": False}),
    )
    monkeypatch.setattr(
        ManualInputResolver,
        "normalize_event_physical_key",
        classmethod(lambda cls, current_event: "v"),
    )

    result = CandidateBox._on_manual_input_key_press(box, event)

    assert result is None
    assert entry.insert_calls == []
    assert root.after_idle_calls == []


def test_manual_input_keypress_still_intercepts_altgr_translation(monkeypatch) -> None:
    entry = _FakeEntry()
    root = _FakeRoot()
    box = _build_box(entry, root)
    event = SimpleNamespace(widget=entry, char="j", keycode=74, keysym="j")

    monkeypatch.setattr(
        ManualInputResolver,
        "get_manual_key_modifiers",
        classmethod(lambda cls: {"ctrl": True, "alt_gr": True}),
    )
    monkeypatch.setattr(
        ManualInputResolver,
        "normalize_event_physical_key",
        classmethod(lambda cls, current_event: "j"),
    )

    result = CandidateBox._on_manual_input_key_press(box, event)

    assert result == "break"
    assert entry.insert_calls == [("insert", "X")]
    assert len(root.after_idle_calls) == 1


def test_manual_input_keypress_allows_native_shift_insert(monkeypatch) -> None:
    entry = _FakeEntry()
    root = _FakeRoot()
    box = _build_box(entry, root)
    event = SimpleNamespace(widget=entry, char="", keycode=45, keysym="Insert")

    monkeypatch.setattr(
        ManualInputResolver,
        "get_manual_key_modifiers",
        classmethod(lambda cls: {"shift": True, "ctrl": False, "alt_gr": False}),
    )
    monkeypatch.setattr(
        ManualInputResolver,
        "normalize_event_physical_key",
        classmethod(lambda cls, current_event: ""),
    )

    result = CandidateBox._on_manual_input_key_press(box, event)

    assert result is None
    assert entry.insert_calls == []
    assert root.after_idle_calls == []
