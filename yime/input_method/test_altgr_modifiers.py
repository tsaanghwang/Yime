from yime.input_method.utils.modifier_state import is_alt_gr_active


def test_altgr_is_active_for_right_alt_alone() -> None:
    assert is_alt_gr_active({"alt_r": True, "alt": True, "ctrl": False}) is True


def test_altgr_is_active_for_ctrl_alt_fallback() -> None:
    assert is_alt_gr_active({"alt_r": False, "alt": True, "ctrl": True}) is True


def test_altgr_is_not_active_for_left_alt_alone() -> None:
    assert is_alt_gr_active({"alt_r": False, "alt": True, "ctrl": False}) is False
