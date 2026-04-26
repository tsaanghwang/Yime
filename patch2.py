with open('c:/dev/Yime/yime/input_method/ui/candidate_box.py', 'r', encoding='utf-8') as f:
    content = f.read()

content = content.replace(
"""self.root.bind("<Prior>", self._on_previous_page_key)
        self.root.bind("<Next>", self._on_next_page_key)
        self.root.bind("<FocusIn>", self._on_window_focus_in)""",
"""        self.root.bind("<Prior>", self._on_previous_page_key)
        self.root.bind("<Next>", self._on_next_page_key)
        self.root.bind("<FocusIn>", self._on_window_focus_in)""")

content = content.replace(
"""def _on_window_focus_in(self, event) -> None:""",
"""    def _on_window_focus_in(self, event: __import__('tkinter').Event) -> None:""")

with open('c:/dev/Yime/yime/input_method/ui/candidate_box.py', 'w', encoding='utf-8') as f:
    f.write(content)
