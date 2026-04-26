import re
from pathlib import Path

p = Path("c:/dev/Yime/yime/input_method/ui/candidate_box.py")
text = p.read_text(encoding="utf-8")

old_show = """    def _show_main_frame(self) -> None:
        if self._is_standby:
            self.standby_frame.pack_forget()
            self.main_frame.pack(fill=tk.BOTH, expand=True)
            self.root.attributes("-alpha", 0.97)
            self.root.title("音元候选框")
            self._is_standby = False"""

new_show = """    def _show_main_frame(self) -> None:
        if self._is_standby:
            self.standby_frame.pack_forget()
            self.main_frame.pack(fill=tk.BOTH, expand=True)
            self.root.attributes("-alpha", 0.97)
            self.root.title("音元候选框")
            self.root.geometry("")  # 清除可能遗留的 54x54 写死尺寸，让布局重新被内部组件撑开
            self.root.update_idletasks()
            self._is_standby = False"""

if old_show in text:
    text = text.replace(old_show, new_show)
    p.write_text(text, encoding="utf-8")
    print("Fixed!")
else:
    print("Could not find block.")

