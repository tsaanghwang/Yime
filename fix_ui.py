import re
from pathlib import Path

p = Path("c:/dev/Yime/yime/input_method/ui/candidate_box.py")
text = p.read_text(encoding="utf-8")

# 1. 替换 _build_ui 里面的 outline_frame 及 tk.Label，改为直接 ttk.Label transparent
old_ui = """        # 用一个带有固定外观的 Frame 强行占据空间，防止被下方控件挤压没高度
        outline_frame = tk.Frame(self.main_frame, bg="#e2e8f0", bd=1, relief=tk.SUNKEN)
        outline_frame.pack(fill=tk.X, pady=(4, 8))

        self.projected_code_var = tk.StringVar(self.root, value="投影码点: ")
        tk.Label(
            outline_frame,
            textvariable=self.projected_code_var,
            anchor=tk.W,
            justify=tk.LEFT,
            bg="#f8fafc",
            padx=6,
            pady=4,
            font=("Consolas", 10),
        ).pack(fill=tk.X)

        self.input_outline_var = tk.StringVar(self.root, value="码元轮廓: ")
        tk.Label(
            outline_frame,
            textvariable=self.input_outline_var,
            anchor=tk.W,
            justify=tk.LEFT,
            bg="#f8fafc",
            padx=6,
            pady=4,
            wraplength=600,
            font=("Consolas", 10),
        ).pack(fill=tk.X)"""

new_ui = """        self.projected_code_var = tk.StringVar(self.root, value="")
        ttk.Label(
            self.main_frame,
            textvariable=self.projected_code_var,
            justify=tk.LEFT,
            font=("Consolas", 10),
            foreground="#666666",
        ).pack(anchor=tk.W, fill=tk.X)

        self.input_outline_var = tk.StringVar(self.root, value="")
        ttk.Label(
            self.main_frame,
            textvariable=self.input_outline_var,
            justify=tk.LEFT,
            wraplength=600,
            font=("Consolas", 10),
            foreground="#666666",
        ).pack(anchor=tk.W, fill=tk.X, pady=(0, 8))"""

if old_ui in text:
    text = text.replace(old_ui, new_ui)
else:
    print("Warning: _build_ui replacement failed")

# 2. 替换 _refresh_input_outline 里面的设置
old_refresh1 = """        if not text:
            self.projected_code_var.set("投影码点: ")
            self.input_outline_var.set("码元轮廓: ")"""
new_refresh1 = """        if not text:
            self.projected_code_var.set("")
            self.input_outline_var.set("")"""
text = text.replace(old_refresh1, new_refresh1)

old_refresh2 = """        self.projected_code_var.set(
            f"投影码点: {self._format_codepoints(text)}\\n投影长度: {len(text)} 码"
        )"""
new_refresh2 = """        self.projected_code_var.set(
            f"{self._format_codepoints(text)}\\n投影长度: {len(text)} 码"
        )"""
text = text.replace(old_refresh2, new_refresh2)

old_refresh3 = """        self.input_outline_var.set(f"码元轮廓: {display_text}" if display_text else "")"""
new_refresh3 = """        self.input_outline_var.set(f"{display_text}" if display_text else "")"""
text = text.replace(old_refresh3, new_refresh3)

# 3. 替换 _clear_input 里面的设置
old_clear = """        self.projected_input_text = ""
        self.projected_code_var.set("投影码点: ")
        self.input_outline_var.set("码元轮廓: ")"""
new_clear = """        self.projected_input_text = ""
        self.projected_code_var.set("")
        self.input_outline_var.set("")"""
text = text.replace(old_clear, new_clear)

p.write_text(text, encoding="utf-8")
print("Done patching.")
