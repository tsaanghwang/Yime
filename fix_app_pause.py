import re
from pathlib import Path

p = Path("c:/dev/Yime/yime/input_method/app.py")
text = p.read_text(encoding="utf-8")

# 一、增加 is_paused 状态
old_init = """        self.keyboard_listener: Optional[KeyboardListener] = None"""
new_init = """        self.keyboard_listener: Optional[KeyboardListener] = None
        self.is_paused = False  # 是否处于系统输入法切换时的暂停测试模式"""
text = text.replace(old_init, new_init)

# 二、修改 on_key_press，并在碰到 Esc / 其他键时处理唤醒，或者根据 is_paused 过滤拦截
old_key_press = """    def _on_key_press(self, key_info: dict) -> bool:
        \"\"\"
        键盘按键回调

        Returns:
            True继续传递，False拦截
        \"\"\"
        try:
            if self.candidate_box.is_manual_input_active():
                return True
            # 让 InputManager 决定是否拦截
            handled = self.input_manager.process_key(key_info)
            return handled"""
            
new_key_press = """    def _on_key_press(self, key_info: dict) -> bool:
        \"\"\"
        键盘按键回调

        Returns:
            True继续传递，False拦截
        \"\"\"
        try:
            # === 测试模式切换逻辑 ===
            if key_info.get("char") == "t" and key_info.get("modifiers", {}).get("ctrl", False) and key_info.get("modifiers", {}).get("alt", False):
                self.is_paused = not self.is_paused
                self.input_manager.clear_buffer(notify=True)
                print(f"[TEST MODE] Paused={self.is_paused}")
                return False  # 拦截切换快捷键
                
            if self.is_paused:
                return True
            # ========================
            
            if self.candidate_box.is_manual_input_active():
                return True
                
            buffer_was_empty = not bool(self.input_manager.get_buffer())
                
            # 让 InputManager 决定是否拦截
            handled = self.input_manager.process_key(key_info)
            
            # 如果是从空缓存变为有缓存（开始输入），还原悬浮框大小
            if buffer_was_empty and self.input_manager.get_buffer() and not self.candidate_box.root.state() == "withdrawn":
                x, y = self.candidate_box.get_pointer_position()
                self._enqueue_ui(lambda: self.candidate_box.show(x, y + 20, focus_input=False))
                
            return handled"""
text = text.replace(old_key_press, new_key_press)

p.write_text(text, encoding="utf-8")
print("Done hooking pause logic.")
