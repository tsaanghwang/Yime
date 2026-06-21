"""音元输入法 Windows 桌面应用。"""

from __future__ import annotations

from importlib import import_module
from typing import Any

__version__ = "1.0.0"
__author__ = "Yime Team"

InputMethodApp = getattr(import_module(".app", __name__), "InputMethodApp")

__all__ = ["InputMethodApp", "main"]


def main(*args: Any, **kwargs: Any) -> Any:
	module = import_module(".app", __name__)
	return module.main(*args, **kwargs)


def __getattr__(name: str) -> Any:
	if name == "main":
		module = import_module(".app", __name__)
		return getattr(module, name)
	raise AttributeError(f"module {__name__!r} has no attribute {name!r}")
