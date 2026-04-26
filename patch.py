import re

with open('c:/dev/Yime/yime/input_method/ui/candidate_box.py', 'r', encoding='utf-8') as f:
    content = f.read()

binding_insert = '''
        self.root.bind("<Prior>", self._on_previous_page_key)
        self.root.bind("<Next>", self._on_next_page_key)
        self.root.bind("<FocusIn>", self._on_window_focus_in)
'''
content = content.replace(
    '        self.root.bind("<Prior>", self._on_previous_page_key)\n        self.root.bind("<Next>", self._on_next_page_key)',
    binding_insert.strip()
)

method_insert = '''
    def _on_window_focus_in(self, event) -> None:
        """当输入候选框获得焦点时，把光标输入插入点（cursor焦点）跳转到输入框输入点。"""
        if getattr(event, "widget", None) == self.root and not self._is_standby:
            self.input_entry.focus_set()
            self.input_entry.icursor("end")

    def _on_input_change(self, event=None) -> None:
'''
content = content.replace(
    '    def _on_input_change(self, event: Optional[tk.Event] = None) -> None:',
    method_insert.strip().replace('event=None', 'event: Optional[tk.Event] = None')
)

with open('c:/dev/Yime/yime/input_method/ui/candidate_box.py', 'w', encoding='utf-8') as f:
    f.write(content)
print("Patched FocusIn")
