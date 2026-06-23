from collections.abc import Sequence
from typing import Any, NoReturn, TypeAlias, cast

from yime.input_method.app_base import BaseInputMethodApp
from yime.input_method.ui.candidate_box import CandidateBox


_UpdatedCandidates: TypeAlias = tuple[list[str], str, str, str]
_DecodeResponse: TypeAlias = tuple[str, str, str, list[str], str]


def _new_app() -> Any:
    return BaseInputMethodApp.__new__(BaseInputMethodApp)


def _on_input_change(app: Any) -> None:
    cast(Any, BaseInputMethodApp)._on_input_change(app)


def _derive_reverse_lookup_key_sequence(app: Any, text: str) -> str:
    return cast(str, cast(Any, BaseInputMethodApp)._derive_reverse_lookup_key_sequence(app, text))


def _project_candidate_box_display_input(app: Any, text: str) -> str:
    return cast(str, cast(Any, BaseInputMethodApp)._project_candidate_box_display_input(app, text))


def _format_visible_input(app: Any, text: str) -> str:
    return cast(str, cast(Any, BaseInputMethodApp)._format_visible_input(app, text))


def _default_status_text() -> str:
    return cast(str, getattr(CandidateBox, "_DEFAULT_STATUS_TEXT"))


def _resolved_candidates(_canonical_code: str, decoded_candidates: list[str]) -> list[str]:
    return list(decoded_candidates)


def _no_resolved_candidates(_canonical_code: str, _decoded_candidates: list[str]) -> list[str]:
    return []


class _FakeCandidateBox:
    def __init__(self, text: str) -> None:
        self._text = text
        self._projected = text
        self.updated: _UpdatedCandidates | None = None

    def get_input(self) -> str:
        return self._text

    def get_projected_input(self) -> str:
        return self._projected

    def set_input(self, text: str, projected_text: str | None = None) -> None:
        self._text = text
        self._projected = text if projected_text is None else projected_text

    def update_candidates(
        self,
        candidates: Sequence[str],
        pinyin: str = "",
        code: str = "",
        status: str = "",
    ) -> None:
        self.updated = (list(candidates), pinyin, code, status)


class _FakeReverseLookupRecord:
    def __init__(self, marked_pinyin: str, numeric_pinyin: str, yime_code: str) -> None:
        self.marked_pinyin = marked_pinyin
        self.numeric_pinyin = numeric_pinyin
        self.yime_code = yime_code


class _FakeReverseLookup:
    def __init__(self, record: _FakeReverseLookupRecord | None) -> None:
        self.record = record

    def lookup_first(self, _text: str) -> _FakeReverseLookupRecord | None:
        return self.record


class _FailDecoder:
    def decode_text(self, text: str) -> NoReturn:
        raise AssertionError(f"decode_text should not run for hanzi reverse lookup: {text}")


class _FakeDecoder:
    def __init__(self, response: _DecodeResponse) -> None:
        self.response = response

    def decode_text(self, _text: str) -> _DecodeResponse:
        return self.response

    def get_char_candidates_by_prefix(self, _prefix: str, _limit: int = 5) -> list[str]:
        return []


def test_on_input_change_prefers_runtime_reverse_lookup_for_hanzi() -> None:
    app = _new_app()
    candidate_box = _FakeCandidateBox("日")
    app.candidate_box = candidate_box
    app.physical_input_map = {}
    app.projected_to_keycap_map = {"甲": "q"}
    app.reverse_lookup_display_mode = "all"
    app.runtime_reverse_lookup = _FakeReverseLookup(_FakeReverseLookupRecord("rì", "ri4", "甲甲"))
    app.decoder = _FailDecoder()
    app.last_replace_length = 0

    _on_input_change(app)

    assert app.last_replace_length == 1
    assert candidate_box.updated == (
        [],
        "标准拼音: rì | 数字标调拼音: ri4 | 音元拼音: 甲甲 | 键位序列: qq",
        "",
        "反查: 已按运行时词库首选读音反查。",
    )


def test_on_input_change_uses_current_default_status_for_empty_input() -> None:
    app = _new_app()
    candidate_box = _FakeCandidateBox("")
    app.candidate_box = candidate_box
    app.physical_input_map = {}
    app.literal_passthrough_chars = set()

    _on_input_change(app)

    assert candidate_box.updated == (
        [],
        "",
        "",
        _default_status_text(),
    )


def test_derive_reverse_lookup_key_sequence_supports_bmp_trial_projection_chars() -> None:
    app = _new_app()
    app.projected_to_keycap_map = {"甲": "q", "乙": "j", "丙": "k", "丁": "l"}

    result = _derive_reverse_lookup_key_sequence(app, "甲乙丙丁")

    assert result == "qjkl"


def test_on_input_change_prefixes_decode_status() -> None:
    app = _new_app()
    candidate_box = _FakeCandidateBox("abcd")
    app.candidate_box = candidate_box
    app.physical_input_map = {}
    app.runtime_reverse_lookup = _FakeReverseLookup(None)
    app.decoder = _FakeDecoder(("ABCD", "ABCD", "rì", ["日"], "从运行时编码表找到 1 个候选。"))
    app.last_replace_length = 0
    app._resolve_display_candidates = _resolved_candidates

    _on_input_change(app)

    assert app.last_replace_length == 4
    assert candidate_box.updated is not None
    candidates, pinyin, code, status = candidate_box.updated
    assert candidates == ["日"]
    assert pinyin == "rì"
    assert code.startswith("当前4码 U+0041 U+0042 U+0043 U+0044")
    assert status == "解码: 已找到候选。"


def test_on_input_change_summarizes_prefix_waiting_status() -> None:
    app = _new_app()
    candidate_box = _FakeCandidateBox("a")
    app.candidate_box = candidate_box
    app.physical_input_map = {}
    app.runtime_reverse_lookup = _FakeReverseLookup(None)
    app.decoder = _FakeDecoder(("A", "A", "", [], "当前 1/4 码，继续输入。"))
    app.last_replace_length = 0
    app._resolve_display_candidates = _no_resolved_candidates

    _on_input_change(app)

    assert candidate_box.updated is not None
    _candidates, _pinyin, _code, status = candidate_box.updated
    assert status == "解码: 前缀等待，继续输入。"


def test_on_input_change_summarizes_not_found_status() -> None:
    app = _new_app()
    candidate_box = _FakeCandidateBox("abcd")
    app.candidate_box = candidate_box
    app.physical_input_map = {}
    app.runtime_reverse_lookup = _FakeReverseLookup(None)
    app.decoder = _FakeDecoder(("ABCD", "ABCD", "", [], "运行时编码表中未找到该 4 码候选。"))
    app.last_replace_length = 0
    app._resolve_display_candidates = _no_resolved_candidates

    _on_input_change(app)

    assert candidate_box.updated is not None
    _candidates, _pinyin, _code, status = candidate_box.updated
    assert status == "解码: 当前编码未找到候选。"


def test_project_candidate_box_display_input_preserves_non_base_literal_outputs() -> None:
    app = _new_app()
    app.physical_input_map = {"1": "甲", "a": "乙"}
    app.literal_passthrough_chars = {"1"}

    result = _project_candidate_box_display_input(app, "1a")

    assert result == "1乙"


def test_format_visible_input_preserves_shift_digit_literals() -> None:
    app = _new_app()
    app.physical_input_map = {"1": "甲", "a": "乙"}
    app.literal_passthrough_chars = {"1"}

    result = _format_visible_input(app, "1a")

    assert result == "1乙"


def test_on_input_change_keeps_shift_digit_literal_visible() -> None:
    app = _new_app()
    candidate_box = _FakeCandidateBox("1")
    app.candidate_box = candidate_box
    app.physical_input_map = {"1": "甲"}
    app.literal_passthrough_chars = {"1"}
    app.projected_to_keycap_map = {}
    app.reverse_lookup_display_mode = "default"
    app.runtime_reverse_lookup = _FakeReverseLookup(None)
    app.decoder = _FakeDecoder(("1", "1", "", [], "当前 1/4 码，继续输入。"))
    app.last_replace_length = 0
    app._resolve_display_candidates = _no_resolved_candidates

    _on_input_change(app)

    assert candidate_box.get_input() == "1"
    assert candidate_box.get_projected_input() == "1"
