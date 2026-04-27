"""Single-character prefix hint panel for the candidate box."""

from __future__ import annotations

import tkinter as tk
from tkinter import ttk
from typing import Any


class PrefixHintPanel:
    """Display read-only single-character prefix lookup hints."""

    def __init__(self, parent: tk.Widget, ui_font: Any) -> None:
        ttk.Label(parent, text="单字前缀提示", style="Yime.TLabel").pack(
            anchor=tk.W
        )
        self.text_var = tk.StringVar(parent, value="")
        ttk.Label(
            parent,
            textvariable=self.text_var,
            justify=tk.LEFT,
            wraplength=600,
            font=ui_font,
            foreground="#666666",
        ).pack(anchor=tk.W, fill=tk.X, pady=(4, 8))

    def set_text(self, text: str) -> None:
        self.text_var.set(text)

    def clear(self) -> None:
        self.set_text("")
