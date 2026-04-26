with open('c:/dev/Yime/yime/input_method/app.py', 'r', encoding='utf-8') as f:
    content = f.read()

replacement = """        display_input = self.candidate_box.get_input()
        projected_input = self.candidate_box.get_projected_input()
        
        # When user typed directly in the Entry, display_input changes but projected_input might lag.
        # We need to compute projection if they differ in length or aren't synchronized.
        # Simple fix: if display_input is not empty and projected_input doesn't match its length or we just changed the UI.
        
        projected_input = project_physical_input(display_input, self.physical_input_map)
        self.candidate_box.set_projected_input(projected_input)
        
        input_text = projected_input"""

import re
content = re.sub(
    r'        display_input = self\.candidate_box\.get_input\(\)\s*'
    r'projected_input = self\.candidate_box\.get_projected_input\(\)\s*'
    r'if projected_input == display_input:\s*'
    r'projected_input = project_physical_input\(display_input, self\.physical_input_map\)\s*'
    r'self\.candidate_box\.set_projected_input\(projected_input\)\s*'
    r'input_text = projected_input',
    replacement,
    content,
    flags=re.MULTILINE
)

with open('c:/dev/Yime/yime/input_method/app.py', 'w', encoding='utf-8') as f:
    f.write(content)
