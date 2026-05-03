import re

with open('yime/input_method/test_input_method.py', 'r', encoding='utf-8') as f:
    content = f.read()

# Fix 4th test
content = content.replace(
    'CandidateBox._resolve_activation_anchor.__globals__["WindowManager"].get_window_text = staticmethod(lambda _hwnd: "Temp.md - Yime - Visual Studio Code")',
    'CandidateBox._resolve_activation_anchor.__globals__["WindowManager"].get_window_text = staticmethod(lambda _hwnd: "Temp.md - Yime - Visual Studio Code")\n            CandidateBox._resolve_activation_anchor.__globals__["WindowManager"].get_cursor_position = staticmethod(lambda: (828, 516))'
)

with open('yime/input_method/test_input_method.py', 'w', encoding='utf-8') as f:
    f.write(content)
