# yime/gui_input.py
import tkinter as tk
from tkinter import ttk
from output_hanzi import get_hanzi_by_any_pinyin
from convert_pinyin_to_hanzi import YinYuanInputConverter

class YinYuanInputApp:
    def __init__(self, root):
        self.root = root
        self.root.title("音元输入法")

        # 初始化转换器
        self.converter = YinYuanInputConverter()

        # 创建界面组件
        self.create_widgets()

    def create_widgets(self):
        # 输入框
        self.input_label = ttk.Label(self.root, text="输入音元符号序列:")
        self.input_label.pack(pady=5)

        self.input_entry = ttk.Entry(self.root, width=50)
        self.input_entry.pack(pady=5)
        self.input_entry.bind("<KeyRelease>", self.on_input_change)

        # 转换结果显示
        self.result_frame = ttk.LabelFrame(self.root, text="转换结果")
        self.result_frame.pack(pady=10, fill="x", padx=10)

        self.pinyin_label = ttk.Label(self.result_frame, text="拼音: ")
        self.pinyin_label.pack(anchor="w")

        self.zhuyin_label = ttk.Label(self.result_frame, text="注音: ")
        self.zhuyin_label.pack(anchor="w")

        # 候选汉字列表
        self.hanzi_frame = ttk.LabelFrame(self.root, text="候选汉字")
        self.hanzi_frame.pack(pady=10, fill="x", padx=10)

        self.hanzi_buttons = []
        self.selected_hanzi = tk.StringVar()

    def on_input_change(self, event):
        input_text = self.input_entry.get()

        if not input_text:
            self.clear_results()
            return

        # 获取拼音和注音
        yinjie_data = self.converter._load_json('yime/enhanced_yinjie_mapping.json')
        found = False

        for yinjie, mappings in yinjie_data['音元符号'].items():
            if yinjie == input_text:
                self.pinyin_label.config(text=f"拼音: {mappings['数字标调']} / {mappings['调号标调']}")
                self.zhuyin_label.config(text=f"注音: {mappings['注音符号']}")
                found = True

                # 获取候选汉字
                hanzi_list = get_hanzi_by_any_pinyin(mappings['数字标调'])
                self.show_hanzi_list(hanzi_list)
                break

        if not found:
            self.clear_results()

    def show_hanzi_list(self, hanzi_list):
        # 清除现有按钮
        for btn in self.hanzi_buttons:
            btn.destroy()
        self.hanzi_buttons = []

        if not hanzi_list:
            label = ttk.Label(self.hanzi_frame, text="未找到匹配的汉字")
            label.pack()
            self.hanzi_buttons.append(label)
            return

        # 创建汉字选择按钮
        for hanzi in hanzi_list:
            btn = ttk.Radiobutton(
                self.hanzi_frame,
                text=hanzi,
                variable=self.selected_hanzi,
                value=hanzi
            )
            btn.pack(anchor="w")
            self.hanzi_buttons.append(btn)

    def clear_results(self):
        self.pinyin_label.config(text="拼音: ")
        self.zhuyin_label.config(text="注音: ")

        for btn in self.hanzi_buttons:
            btn.destroy()
        self.hanzi_buttons = []

if __name__ == "__main__":
    root = tk.Tk()
    app = YinYuanInputApp(root)
    root.mainloop()
