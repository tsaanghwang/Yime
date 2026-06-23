from yime.input_method.ui.candidate_system import CandidateWindowSystem
from unittest import mock


_should_start_nonclient_right_drag = getattr(
    CandidateWindowSystem, "_should_start_nonclient_right_drag"
)
_handle_wndproc_message = getattr(CandidateWindowSystem, "_handle_wndproc_message")
_HTCAPTION = getattr(CandidateWindowSystem, "_HTCAPTION")
_HTSYSMENU = getattr(CandidateWindowSystem, "_HTSYSMENU")
_HTMAXBUTTON = getattr(CandidateWindowSystem, "_HTMAXBUTTON")
_WM_NCRBUTTONDOWN = getattr(CandidateWindowSystem, "_WM_NCRBUTTONDOWN")


def test_nonclient_right_drag_hit_targets_are_limited() -> None:
    assert _should_start_nonclient_right_drag(_HTCAPTION) is True
    assert _should_start_nonclient_right_drag(_HTSYSMENU) is True
    assert _should_start_nonclient_right_drag(_HTMAXBUTTON) is True
    assert _should_start_nonclient_right_drag(0) is False
    assert _should_start_nonclient_right_drag(20) is False


def test_handle_wndproc_message_ignores_other_messages_and_hits() -> None:
    system = CandidateWindowSystem.__new__(CandidateWindowSystem)
    setattr(system, "_user32", mock.Mock())

    handled_message = _handle_wndproc_message(
        system,
        123,
        0,
        _HTCAPTION,
        456,
    )
    handled_hit = _handle_wndproc_message(
        system,
        123,
        _WM_NCRBUTTONDOWN,
        0,
        456,
    )

    assert handled_message is False
    assert handled_hit is False
