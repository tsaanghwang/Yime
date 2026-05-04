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
    def __init__(self, display_text: str) -> None:
        self.display_text = display_text

    def to_display_text(self) -> str:
        return self.display_text


class _FakeReverseLookup:
    def __init__(self, record) -> None:
        self.record = record

    def lookup_first(self, text: str):
        return self.record


class _FailDecoder:
    def decode_text(self, text: str):
        raise AssertionError(f"decode_text should not run for hanzi reverse lookup: {text}")


def test_on_input_change_prefers_runtime_reverse_lookup_for_hanzi() -> None:
    app = BaseInputMethodApp.__new__(BaseInputMethodApp)
    app.candidate_box = _FakeCandidateBox("日")
    app.physical_input_map = {}
    app.runtime_reverse_lookup = _FakeReverseLookup(_FakeReverseLookupRecord("rì / ri4 | CODE"))
    app.decoder = _FailDecoder()
    app.last_replace_length = 0

    BaseInputMethodApp._on_input_change(app)

    assert app.last_replace_length == 1
    assert app.candidate_box.updated == (
        [],
        "rì / ri4 | CODE",
        "",
        "已按运行时词库首选读音反查。",
    )
