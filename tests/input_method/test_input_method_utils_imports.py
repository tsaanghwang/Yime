from __future__ import annotations

import ctypes
import importlib
import sys


def test_user_lexicon_import_does_not_require_windll(monkeypatch) -> None:
    monkeypatch.delattr(ctypes, "WinDLL", raising=False)

    for module_name in (
        "yime.input_method.utils.window_manager",
        "yime.input_method.utils.user_lexicon",
        "yime.input_method.utils",
    ):
        sys.modules.pop(module_name, None)

    module = importlib.import_module("yime.input_method.utils.user_lexicon")

    assert getattr(module, "UserLexiconStore").__name__ == "UserLexiconStore"
