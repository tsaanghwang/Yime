from yime.input_method.ui.candidate_system import CandidateWindowSystem


def test_nonclient_right_drag_hit_targets_are_limited() -> None:
    assert CandidateWindowSystem._should_start_nonclient_right_drag(
        CandidateWindowSystem._HTCAPTION
    ) is True
    assert CandidateWindowSystem._should_start_nonclient_right_drag(
        CandidateWindowSystem._HTSYSMENU
    ) is True
    assert CandidateWindowSystem._should_start_nonclient_right_drag(
        CandidateWindowSystem._HTMAXBUTTON
    ) is True
    assert CandidateWindowSystem._should_start_nonclient_right_drag(0) is False
    assert CandidateWindowSystem._should_start_nonclient_right_drag(20) is False


from unittest import mock


def test_handle_wndproc_message_ignores_other_messages_and_hits() -> None:
    system = CandidateWindowSystem.__new__(CandidateWindowSystem)
    system._user32 = mock.Mock()

    handled_message = system._handle_wndproc_message(
        123,
        0,
        CandidateWindowSystem._HTCAPTION,
        456,
    )
    handled_hit = system._handle_wndproc_message(
        123,
        CandidateWindowSystem._WM_NCRBUTTONDOWN,
        0,
        456,
    )

    assert handled_message is False
    assert handled_hit is False
