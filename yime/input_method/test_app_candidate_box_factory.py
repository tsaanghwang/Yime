from yime.input_method.app import InputMethodApp


def test_input_method_app_factory_wires_user_lexicon_callbacks(monkeypatch) -> None:
    captured: dict[str, object] = {}

    class _FakeCandidateBox:
        def __init__(self, **kwargs) -> None:
            captured.update(kwargs)

    monkeypatch.setattr("yime.input_method.app.CandidateBox", _FakeCandidateBox)

    app = InputMethodApp.__new__(InputMethodApp)
    app.font_family = "音元"
    app._on_candidate_select = lambda text: None
    app._format_input_outline = lambda text: text
    app._format_projected_code = lambda text: text
    app._resolve_manual_key_output = lambda physical_key, modifiers: ""
    app._format_visible_input = lambda text: text
    app._on_input_change = lambda event=None: None
    app._copy_candidate = lambda index: None
    app._commit_candidate_box_text = lambda text: None
    app._add_current_input_to_user_lexicon = lambda: None
    app._delete_current_input_from_user_lexicon = lambda: None
    app._resume_from_standby = lambda: None
    app._return_mouse_session_to_standby = lambda: None
    app._close = lambda: None
    app._is_mouse_wake_enabled = lambda: True
    app._is_mouse_standby_enabled = lambda: True

    InputMethodApp._create_candidate_box(app)

    assert captured["on_add_input_to_user_lexicon"] is app._add_current_input_to_user_lexicon
    assert captured["on_delete_input_from_user_lexicon"] is app._delete_current_input_from_user_lexicon
    assert captured["on_feedback"].__self__ is app
    assert captured["on_feedback"].__func__ is app._emit_feedback.__func__
