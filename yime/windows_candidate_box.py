"""Compatibility shim for the retired Windows candidate-box test shell."""

from yime.legacy.pending_removal.windows_candidate_box import (
    CandidateBoxApp,
    KEYEVENTF_KEYUP,
    SW_RESTORE,
    VK_BACK,
    VK_C,
    VK_CONTROL,
    VK_LEFT,
    VK_SHIFT,
    VK_V,
    get_foreground_window,
    main,
    parse_args,
    restore_window,
    send_backspace,
    send_ctrl_c,
    send_ctrl_v,
    send_shift_left,
    user32,
)

__all__ = [
    "CandidateBoxApp",
    "KEYEVENTF_KEYUP",
    "SW_RESTORE",
    "VK_BACK",
    "VK_C",
    "VK_CONTROL",
    "VK_LEFT",
    "VK_SHIFT",
    "VK_V",
    "get_foreground_window",
    "main",
    "parse_args",
    "restore_window",
    "send_backspace",
    "send_ctrl_c",
    "send_ctrl_v",
    "send_shift_left",
    "user32",
]


if __name__ == "__main__":
    raise SystemExit(main())
