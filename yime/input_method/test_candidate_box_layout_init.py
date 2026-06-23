import tkinter as tk
from types import SimpleNamespace
from typing import Any, cast

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


@pytest.mark.parametrize("page_size", [5, 6, 7, 8, 9])
def test_horizontal_layout_keeps_long_candidates_clear_of_pager(page_size: int) -> None:
    try:
        box = CandidateBox(
            on_select=lambda text: None,
            font_family="TkDefaultFont",
            candidate_layout="horizontal",
        )
    except tk.TclError as exc:
        pytest.skip(f"tkinter unavailable: {exc}")

    try:
        box.set_page_size(page_size)
        candidates = [
            "毕业生",
            "机器人",
            "计算机",
            "验证码",
            "博物馆",
            "预处理",
            "西班牙",
            "服务员",
            "验证集",
        ][:page_size]
        box.update_candidates(candidates, "bi4", "", "")
        box.root.update_idletasks()
        expected_text_width = sum(
            box.ui_font.measure(f"{index}. ")
            + box.text_font.measure(candidate)
            + box.text_font.measure("  ")
            for index, candidate in enumerate(candidates, start=1)
        )

        assert box.candidate_text.winfo_reqwidth() >= expected_text_width
        assert box.root.winfo_reqwidth() >= (
            box.candidate_text.winfo_reqwidth() + box.pager_frame.winfo_reqwidth()
        )
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
            self.candidate_layout_var = cast(Any, _FakeVar())
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

    assert cast(Any, box.candidate_layout_var).value == "vertical"
    assert cast(Any, box)._candidate_layout == "vertical"
    assert box.sync_calls == 1
    assert box.render_calls == 1
    assert box.resize_calls == 1


def test_hover_tip_lifecycle_uses_real_tk_tooltip_window() -> None:
    try:
        box = CandidateBox(
            on_select=lambda text: None,
            font_family="TkDefaultFont",
            candidate_layout="horizontal",
        )
    except tk.TclError as exc:
        pytest.skip(f"tkinter unavailable: {exc}")

    try:
        box.set_status("候选区提示")
        box.root.update_idletasks()

        event = cast(Any, SimpleNamespace(x_root=240, y_root=160))
        getattr(box, "_on_hover_tip_enter")(event, lambda: cast(Any, box)._status_text)
        box.root.update_idletasks()

        assert cast(Any, box)._tooltip_window is not None
        assert cast(Any, box)._tooltip_label is not None
        assert cast(Any, box)._tooltip_window.winfo_exists() == 1
        assert str(cast(Any, box)._tooltip_label.cget("text")) == "候选区提示"

        box.set_hover_tip_enabled(False)
        box.root.update_idletasks()

        assert cast(Any, box)._tooltip_window is None
        assert cast(Any, box)._tooltip_label is None

        event = cast(Any, SimpleNamespace(x_root=260, y_root=180))
        getattr(box, "_on_hover_tip_enter")(event, lambda: cast(Any, box)._status_text)
        box.root.update_idletasks()

        assert cast(Any, box)._tooltip_window is None
        assert cast(Any, box)._tooltip_label is None
    finally:
        box.root.destroy()
