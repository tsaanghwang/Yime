import tkinter as tk

import pytest

from yime.input_method.ui.candidate_renderer import CandidateRendererMixin
from yime.input_method.ui.candidate_box import CandidateBox


def test_candidate_box_initial_vertical_layout_renders_without_manual_toggle() -> None:
    try:
        box = CandidateBox(
            on_select=lambda text: None,
            font_family="TkDefaultFont",
            candidate_layout="vertical",
        )
    except tk.TclError as exc:
        pytest.skip(f"tkinter unavailable: {exc}")

    try:
        box.update_candidates(["一", "乙", "二", "十", "丁"], "yi1", "", "")

        candidate_text = box.candidate_text.get("1.0", "end-1c")
        assert "1. 一\n2. 乙" in candidate_text
        assert "第 1/1 页" in candidate_text
        assert int(box.candidate_text.cget("height")) >= 6
        assert box.first_page_button.pack_info().get("side", "top") == "top"
        assert box.prev_page_button.pack_info().get("side", "top") == "top"
        assert box.toolbar_menu_button.pack_info().get("side", "top") == "top"
        assert box.layout_builder.drag_grip.pack_info().get("side", "top") == "top"
    finally:
        box.root.destroy()


def test_candidate_box_initial_vertical_layout_starts_compact_without_candidates() -> None:
    try:
        box = CandidateBox(
            on_select=lambda text: None,
            font_family="TkDefaultFont",
            candidate_layout="vertical",
        )
    except tk.TclError as exc:
        pytest.skip(f"tkinter unavailable: {exc}")

    try:
        box.root.update_idletasks()

        assert int(box.candidate_text.cget("width")) <= 12
        assert int(box.candidate_text.cget("height")) == 1
    finally:
        box.root.destroy()


def test_set_candidate_layout_requests_resize_when_layout_changes() -> None:
    class _FakeVar:
        def __init__(self) -> None:
            self.value = "horizontal"

        def set(self, value: str) -> None:
            self.value = value

    class _FakeBox(CandidateRendererMixin):
        def __init__(self) -> None:
            self.candidate_layout_var = _FakeVar()
            self._candidate_layout = "horizontal"
            self.sync_calls = 0
            self.render_calls = 0
            self.resize_calls = 0

        def _sync_pager_button_layout(self) -> None:
            self.sync_calls += 1

        def _render_candidates(self) -> None:
            self.render_calls += 1

        def _resize_to_content_if_visible(self) -> None:
            self.resize_calls += 1

    box = _FakeBox()

    box.set_candidate_layout("vertical")

    assert box.candidate_layout_var.value == "vertical"
    assert box._candidate_layout == "vertical"
    assert box.sync_calls == 1
    assert box.render_calls == 1
    assert box.resize_calls == 1
