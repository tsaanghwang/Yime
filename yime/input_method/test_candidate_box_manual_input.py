from types import SimpleNamespace
from typing import Any, TypeVar, cast

import pytest
from yime.input_method.ui.candidate_box import CandidateBox
from yime.input_method.ui.manual_input_resolver import ManualInputResolver

_T = TypeVar("_T")


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


def _build_box(entry: _FakeEntry, root: _FakeRoot) -> Any:
    def _default_manual_key_output_resolver(key: str, modifiers: dict[str, bool]) -> str:
        _ = (key, modifiers)
        return "X"

    return cast(
        Any,
        SimpleNamespace(
        input_entry=entry,
        _manual_input_enabled=True,
        _manual_key_output_resolver=_default_manual_key_output_resolver,
        _manual_input_transformer=None,
        root=root,
        _on_input_change=lambda: None,
        ),
    )


def _mock_classmethod_return(value: _T) -> classmethod:
    def _func(cls: type[Any], *args: object, **kwargs: object) -> _T:
        _ = (cls, args, kwargs)
        return value

    return classmethod(_func)


def test_manual_input_keypress_allows_native_ctrl_v(monkeypatch: pytest.MonkeyPatch) -> None:
    entry = _FakeEntry()
    root = _FakeRoot()
    box = _build_box(entry, root)
    event = SimpleNamespace(widget=entry, char="", keycode=86, keysym="v")

    monkeypatch.setattr(
        ManualInputResolver,
        "get_manual_key_modifiers",
        _mock_classmethod_return({"ctrl": True, "alt_gr": False}),
    )
    monkeypatch.setattr(
        ManualInputResolver,
        "normalize_event_physical_key",
        _mock_classmethod_return("v"),
    )

    result = CandidateBox._on_manual_input_key_press(box, event)  # type: ignore[arg-type,reportPrivateUsage]

    assert result is None
    assert entry.insert_calls == []
    assert root.after_idle_calls == []


def test_manual_input_keypress_still_intercepts_altgr_translation(monkeypatch: pytest.MonkeyPatch) -> None:
    entry = _FakeEntry()
    root = _FakeRoot()
    box = _build_box(entry, root)
    event = SimpleNamespace(widget=entry, char="j", keycode=74, keysym="j")

    monkeypatch.setattr(
        ManualInputResolver,
        "get_manual_key_modifiers",
        _mock_classmethod_return({"ctrl": True, "alt_gr": True}),
    )
    monkeypatch.setattr(
        ManualInputResolver,
        "normalize_event_physical_key",
        _mock_classmethod_return("j"),
    )

    result = CandidateBox._on_manual_input_key_press(box, event)  # type: ignore[arg-type,reportPrivateUsage]

    assert result == "break"
    assert entry.insert_calls == [("insert", "X")]
    assert len(root.after_idle_calls) == 1


def test_manual_input_keypress_allows_native_shift_insert(monkeypatch: pytest.MonkeyPatch) -> None:
    entry = _FakeEntry()
    root = _FakeRoot()
    box = _build_box(entry, root)
    event = SimpleNamespace(widget=entry, char="", keycode=45, keysym="Insert")

    monkeypatch.setattr(
        ManualInputResolver,
        "get_manual_key_modifiers",
        _mock_classmethod_return({"shift": True, "ctrl": False, "alt_gr": False}),
    )
    monkeypatch.setattr(
        ManualInputResolver,
        "normalize_event_physical_key",
        _mock_classmethod_return(""),
    )

    result = CandidateBox._on_manual_input_key_press(box, event)  # type: ignore[arg-type,reportPrivateUsage]

    assert result is None
    assert entry.insert_calls == []
    assert root.after_idle_calls == []


def test_manual_input_keypress_allows_native_numpad_decimal(monkeypatch: pytest.MonkeyPatch) -> None:
    entry = _FakeEntry()
    root = _FakeRoot()
    box = _build_box(entry, root)
    event = SimpleNamespace(widget=entry, char=".", keycode=0x6E, keysym="KP_Decimal")

    monkeypatch.setattr(
        ManualInputResolver,
        "is_numpad_event",
        _mock_classmethod_return(True),
    )

    result = CandidateBox._on_manual_input_key_press(box, event)  # type: ignore[arg-type,reportPrivateUsage]

    assert result is None
    assert entry.insert_calls == []
    assert root.after_idle_calls == []


def test_manual_input_keypress_intercepts_number_row_via_layout_resolver(monkeypatch: pytest.MonkeyPatch) -> None:
    entry = _FakeEntry()
    root = _FakeRoot()
    box = _build_box(entry, root)

    def _manual_key_output_resolver(key: str, modifiers: dict[str, bool]) -> str:
        _ = modifiers
        return "\U00100015" if key == "1" else ""

    def _manual_input_transformer(text: str) -> str:
        return "\ue4fe" if text == "\U00100015" else text

    box._manual_key_output_resolver = _manual_key_output_resolver
    box._manual_input_transformer = _manual_input_transformer
    event = SimpleNamespace(widget=entry, char="1", keycode=49, keysym="1")

    monkeypatch.setattr(
        ManualInputResolver,
        "get_manual_key_modifiers",
        _mock_classmethod_return({"shift": False, "ctrl": False, "alt_gr": False}),
    )
    monkeypatch.setattr(
        ManualInputResolver,
        "normalize_event_physical_key",
        _mock_classmethod_return("1"),
    )
    monkeypatch.setattr(
        ManualInputResolver,
        "resolve_manual_input_text",
        _mock_classmethod_return("1"),
    )

    result = CandidateBox._on_manual_input_key_press(box, event)  # type: ignore[arg-type,reportPrivateUsage]

    assert result == "break"
    assert entry.insert_calls == [("insert", "\ue4fe")]
    assert len(root.after_idle_calls) == 1


def test_manual_input_keypress_allows_native_numpad_digit(monkeypatch: pytest.MonkeyPatch) -> None:
    entry = _FakeEntry()
    root = _FakeRoot()
    box = _build_box(entry, root)
    event = SimpleNamespace(widget=entry, char="1", keycode=0x61, keysym="KP_1")

    monkeypatch.setattr(
        ManualInputResolver,
        "is_numpad_event",
        _mock_classmethod_return(True),
    )

    result = CandidateBox._on_manual_input_key_press(box, event)  # type: ignore[arg-type,reportPrivateUsage]

    assert result is None
    assert entry.insert_calls == []
    assert root.after_idle_calls == []
