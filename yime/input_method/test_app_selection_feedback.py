from typing import Any, cast

from yime.input_method.app import InputMethodApp


class _FakeCandidateBox:
    def __init__(self, text: str, projected: str) -> None:
        self._text = text
        self._projected = projected
        self.statuses: list[str] = []
        self.root = object()

    def get_input(self) -> str:
        return self._text

    def get_projected_input(self) -> str:
        return self._projected

    def set_status(self, status: str) -> None:
        self.statuses.append(status)


class _FakeDecoder:
    def __init__(self, persisted_freq: int) -> None:
        self.persisted_freq = persisted_freq
        self.calls: list[tuple[str, str]] = []

    def record_selection(self, text: str, candidate_text: str) -> int:
        self.calls.append((text, candidate_text))
        return self.persisted_freq


class _TestInputMethodApp(InputMethodApp):
    def select_candidate(self, candidate_text: str) -> None:
        self._on_candidate_select(candidate_text)


def test_on_candidate_select_reports_reordering_hint() -> None:
    app = _TestInputMethodApp.__new__(_TestInputMethodApp)
    fake_candidate_box = _FakeCandidateBox("abcd", "abcd")
    fake_decoder = _FakeDecoder(3)
    app_state = cast(Any, app)
    app_state.candidate_box = fake_candidate_box
    app_state.physical_input_map = {}
    app_state.decoder = fake_decoder
    app.last_replace_length = 9

    app.select_candidate("安权")

    assert fake_decoder.calls == [("abcd", "安权")]
    assert app.last_replace_length == 0
    assert fake_candidate_box.statuses == [
        "调序已记录：安权（累计 3 次）。如需追查请用 diagnose_candidate_order.py。"
    ]
