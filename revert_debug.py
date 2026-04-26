import re
from pathlib import Path

p = Path("c:/dev/Yime/yime/input_method/app.py")
text = p.read_text(encoding="utf-8")

# 1. 启动后默认显示完整的辅助窗口 -> show_standby
text = text.replace(
    '# 启动后默认显示完整的辅助窗口（包括等待输入的控件）\n        self.candidate_box.show(focus_input=True)',
    '# 启动后默认显示待命图标\n        self.candidate_box.show_standby()'
)

# 2. _hide_candidate_box 中的强行显示
old_hide = """        # 调试期间禁用自动隐藏，使得一直显示完整框
        self.candidate_box.show(focus_input=True)"""
new_hide = """        self.candidate_box.show_standby()"""
text = text.replace(old_hide, new_hide)

# 3. _on_candidates_update 中的强行显示
old_update = """        else:
            if self.debug_ui:
                print("[UI] keep tracking candidate box even if buffer is empty for debugging")

            # 暂时关闭“清空输入就隐藏为旋风框”的逻辑，强制始终显示大框以便于看 清 UI
            self.candidate_box.show(focus_input=True)"""
new_update = """        else:
            self.candidate_box.show_standby()"""
text = text.replace(old_update, new_update)

p.write_text(text, encoding="utf-8")
print("Done reverting.")
