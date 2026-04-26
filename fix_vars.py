import re

with open('c:/dev/Yime/yime/input_method/ui/candidate_box.py', 'r', encoding='utf-8') as f:
    text = f.read()

text = re.sub(r' tk\.StringVar\(\)', r' tk.StringVar(self.root)', text)
text = re.sub(r' tk\.StringVar\(value=', r' tk.StringVar(self.root, value=', text)

with open('c:/dev/Yime/yime/input_method/ui/candidate_box.py', 'w', encoding='utf-8') as f:
    f.write(text)

