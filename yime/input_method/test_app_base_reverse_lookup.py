from yime.input_method.app_base import BaseInputMethodApp


class _FakeCandidateBox:
    def __init__(self, text: str) -> None:
        self._text = text
        self._projected = text
        self.updated: tuple[list[str], str, str, str] | None = None

    def get_input(self) -> str:
        return self._text

    def get_projected_input(self) -> str:
        return self._projected

    def set_input(self, text: str, projected_text: str | None = None) -> None:
        self._text = text
        self._projected = text if projected_text is None else projected_text

    def update_candidates(self, candidates, pinyin="", code="", status="") -> None:
        self.updated = (list(candidates), pinyin, code, status)


class _FakeReverseLookupRecord:
    def __init__(self, marked_pinyin: str, numeric_pinyin: str, yime_code: str) -> None:
        self.marked_pinyin = marked_pinyin
        self.numeric_pinyin = numeric_pinyin
        self.yime_code = yime_code


class _FakeReverseLookup:
    def __init__(self, record) -> None:
        self.record = record

    def lookup_first(self, text: str):
        return self.record


class _FailDecoder:
    def decode_text(self, text: str):
        raise AssertionError(f"decode_text should not run for hanzi reverse lookup: {text}")


class _FakeDecoder:
    def __init__(self, response) -> None:
        self.response = response

    def decode_text(self, text: str):
        return self.response

    def get_char_candidates_by_prefix(self, prefix: str, limit: int = 5):
        return []


def test_on_input_change_prefers_runtime_reverse_lookup_for_hanzi() -> None:
    app = BaseInputMethodApp.__new__(BaseInputMethodApp)
    app.candidate_box = _FakeCandidateBox("日")
    app.physical_input_map = {}
    app.projected_to_keycap_map = {"甲": "q"}
    app.reverse_lookup_display_mode = "all"
    app.runtime_reverse_lookup = _FakeReverseLookup(_FakeReverseLookupRecord("rì", "ri4", "甲甲"))
    app.decoder = _FailDecoder()
    app.last_replace_length = 0

    BaseInputMethodApp._on_input_change(app)

    assert app.last_replace_length == 1
    assert app.candidate_box.updated == (
        [],
        "标准拼音: rì | 数字标调拼音: ri4 | 音元拼音: 甲甲 | 键位序列: qq",
        "",
        "反查: 已按运行时词库首选读音反查。",
    )


def test_on_input_change_uses_current_default_status_for_empty_input() -> None:
    app = BaseInputMethodApp.__new__(BaseInputMethodApp)
    app.candidate_box = _FakeCandidateBox("")
    app.physical_input_map = {}

    BaseInputMethodApp._on_input_change(app)

    assert app.candidate_box.updated == (
        [],
        "",
        "",
        "连续输入时会自动取最近 4 码。可直接输入编码，或粘贴后继续输入。",
    )


def test_derive_reverse_lookup_key_sequence_supports_bmp_trial_projection_chars() -> None:
    app = BaseInputMethodApp.__new__(BaseInputMethodApp)
    app.projected_to_keycap_map = {"甲": "q", "乙": "j", "丙": "k", "丁": "l"}

    result = BaseInputMethodApp._derive_reverse_lookup_key_sequence(app, "甲乙丙丁")

    assert result == "qjkl"


def test_on_input_change_prefixes_decode_status() -> None:
    app = BaseInputMethodApp.__new__(BaseInputMethodApp)
    app.candidate_box = _FakeCandidateBox("abcd")
    app.physical_input_map = {}
    app.runtime_reverse_lookup = _FakeReverseLookup(None)
    app.decoder = _FakeDecoder(("ABCD", "ABCD", "rì", ["日"], "从运行时编码表找到 1 个候选。"))
    app.last_replace_length = 0
    app._resolve_display_candidates = lambda canonical_code, decoded_candidates: list(decoded_candidates)

    BaseInputMethodApp._on_input_change(app)

    assert app.last_replace_length == 4
    assert app.candidate_box.updated is not None
    candidates, pinyin, code, status = app.candidate_box.updated
    assert candidates == ["日"]
    assert pinyin == "rì"
    assert code.startswith("当前4码 U+0041 U+0042 U+0043 U+0044")
    assert status == "解码: 已找到候选。"


def test_on_input_change_summarizes_prefix_waiting_status() -> None:
    app = BaseInputMethodApp.__new__(BaseInputMethodApp)
    app.candidate_box = _FakeCandidateBox("a")
    app.physical_input_map = {}
    app.runtime_reverse_lookup = _FakeReverseLookup(None)
    app.decoder = _FakeDecoder(("A", "A", "", [], "当前 1/4 码，继续输入。"))
    app.last_replace_length = 0
    app._resolve_display_candidates = lambda canonical_code, decoded_candidates: []

    BaseInputMethodApp._on_input_change(app)

    assert app.candidate_box.updated is not None
    _candidates, _pinyin, _code, status = app.candidate_box.updated
    assert status == "解码: 前缀等待，继续输入。"


def test_on_input_change_summarizes_not_found_status() -> None:
    app = BaseInputMethodApp.__new__(BaseInputMethodApp)
    app.candidate_box = _FakeCandidateBox("abcd")
    app.physical_input_map = {}
    app.runtime_reverse_lookup = _FakeReverseLookup(None)
    app.decoder = _FakeDecoder(("ABCD", "ABCD", "", [], "运行时编码表中未找到该 4 码候选。"))
    app.last_replace_length = 0
    app._resolve_display_candidates = lambda canonical_code, decoded_candidates: []

    BaseInputMethodApp._on_input_change(app)

    assert app.candidate_box.updated is not None
    _candidates, _pinyin, _code, status = app.candidate_box.updated
    assert status == "解码: 当前编码未找到候选。"
