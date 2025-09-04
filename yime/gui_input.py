import os
import sys
import io
import tkinter as tk
from tkinter import ttk
import pyperclip
from convert_pinyin_to_hanzi import YinYuanInputConverter
from typing import Optional, Tuple, List, Callable, Any
import sqlite3

class HanziInputApp:
    def __init__(self, master: tk.Tk):
        """初始化输入法GUI界面"""
        self.master = master
        master.title("音元输入法(数据库版)")

        # 初始化数据库路径和连接
        script_dir = os.path.dirname(os.path.abspath(__file__))
        self.db_path = os.path.join(script_dir, "pinyin_hanzi.db")
        self.db_conn = None  # 延迟初始化

        # 初始化转换器
        self.converter = self._initialize_converter()

        # 创建UI组件
        self._create_widgets()

        # 存储当前候选汉字
        self.current_candidates: List[str] = []

        # --- 新增：用于轮询的变量和启动轮询 ---
        self.last_input_text = ""
        self._poll_input_change()
        # ------------------------------------

    def _initialize_converter(self) -> YinYuanInputConverter:
        """初始化拼音转换器(完全数据库版)"""
        try:
            # 获取当前脚本所在目录的绝对路径
            script_dir = os.path.dirname(os.path.abspath(__file__))
            db_path = os.path.join(script_dir, "pinyin_hanzi.db")

            # 检查数据库文件是否存在
            if not os.path.exists(db_path):
                raise FileNotFoundError(f"数据库文件不存在: {db_path}")

            return YinYuanInputConverter(db_path=db_path)
        except Exception as e:
            self._show_error_message(f"初始化转换器失败: {str(e)}")
            raise

    def _create_widgets(self):
        """创建所有GUI组件"""
        # 输入区域
        input_frame = ttk.Frame(self.master, padding="10")
        input_frame.pack(fill=tk.X)

        ttk.Label(input_frame, text="输入音元符号:").pack(anchor=tk.W)
        self.input_entry = ttk.Entry(input_frame, width=40, font=('Arial', 12, 'normal'))
        self.input_entry.pack(fill=tk.X, pady=5)
        # 注意：我们保留KeyRelease绑定，以获得即时响应，轮询作为补充
        self.input_entry.bind("<KeyRelease>", self.on_input_change)

        # 拼音显示区域
        ttk.Label(input_frame, text="标准拼音:").pack(anchor=tk.W)
        self.pinyin_display = ttk.Label(
            input_frame,
            text="",
            foreground="blue",
            font=('Arial', 12, 'bold')
        )
        self.pinyin_display.pack(anchor=tk.W, pady=2)

        # 候选汉字区域
        ttk.Label(input_frame, text="候选汉字:").pack(anchor=tk.W)
        self.hanzi_frame = ttk.Frame(input_frame)
        self.hanzi_frame.pack(fill=tk.X, pady=5)

        # 结果区域
        result_frame = ttk.Frame(self.master, padding="10")
        result_frame.pack(fill=tk.BOTH, expand=True)

        ttk.Label(result_frame, text="已选汉字:").pack(anchor=tk.W)
        self.result_display = ttk.Label(
            result_frame,
            text="",
            font=('Arial', 14, 'normal'),
            wraplength=400
        )
        self.result_display.pack(fill=tk.BOTH, expand=True, pady=5)

        # 操作按钮
        self.button_frame = ttk.Frame(self.master, padding="10")  # 改为实例变量
        self.button_frame.pack(fill=tk.X)

        ttk.Button(
            self.button_frame,
            text="复制结果",
            command=self.copy_to_clipboard
        ).pack(side=tk.LEFT, padx=5)

        ttk.Button(
             self.button_frame,
            text="清空",
            command=self.clear_display
        ).pack(side=tk.LEFT, padx=5)

        # 右键菜单
        self._setup_context_menu()

    def _setup_context_menu(self):
        """设置右键上下文菜单"""
        self.context_menu = tk.Menu(self.master, tearoff=0)
        self.context_menu.add_command(
            label="复制",
            command=self.copy_to_clipboard
        )
        self.context_menu.add_command(
            label="粘贴",
            command=self._paste_from_clipboard
        )
        self.context_menu.add_command(
            label="清空",
            command=self.clear_display
        )

        # 绑定右键事件
        self.result_display.bind(
            "<Button-3>",
            lambda e: self.context_menu.tk_popup(e.x_root, e.y_root)
        )

        # 在button_frame中添加测试按钮
        ttk.Button(
             self.button_frame,
            text="测试音元序列",
            command=self.load_yinyuan_sequence
        ).pack(side=tk.LEFT, padx=5)

    def _poll_input_change(self):
        """定期检查输入框内容是否变化"""
        try:
            current_text = self.input_entry.get()
            if current_text != self.last_input_text:
                # 添加诊断信息，检查是否检测到变化
                print(f"检测到输入变化: {current_text!r}")  # 使用repr()表示
                self.last_input_text = current_text
                self.on_input_change()

            # 使用标准方式递归调用，并忽略类型检查器的警告
            self.master.after(100, self._poll_input_change)  # type: ignore
        except tk.TclError:
            # 窗口关闭时会发生此错误，可以安全忽略
            pass
    # ----------------------

    def on_input_change(self, event: Optional[tk.Event] = None):
        """处理输入变化事件(数据库版)"""
        input_text = self.input_entry.get()

        # --- 同步轮询状态 ---
        self.last_input_text = input_text
        # --------------------

        if not input_text:
            self.clear_display()
            return

        try:
            # 调用转换器获取拼音和候选汉字(从数据库)
            result = self.converter.convert(input_text)

            # --- 关键诊断信息 ---
            print(f"转换器返回结果: {result}")
            # --------------------

            if result and isinstance(result, tuple) and len(result) == 2:
                pinyin, candidates = result
                # 确保pinyin是字符串类型
                display_text = str(pinyin) if pinyin is not None else ""
                self.pinyin_display['text'] = display_text
                self._update_hanzi_buttons(candidates if isinstance(candidates, list) else [])
            else:
                print("结果无效或为空，清空候选字。") # 确认执行了清空操作
                self.pinyin_display['text'] = ""
                self._update_hanzi_buttons([])

        except sqlite3.Error as e:
            self._show_error_message(f"数据库错误: {str(e)}")
            self.clear_display()
        except Exception as e:
            self._show_error_message(f"转换错误: {str(e)}")
            self.clear_display()

    def _update_hanzi_buttons(self, candidates: List[str]):
        """更新候选汉字按钮"""
        # 清除旧按钮
        for widget in self.hanzi_frame.winfo_children():
            widget.destroy()

        self.current_candidates = candidates

        # 创建新按钮 (最多显示9个候选字)
        for i, hanzi in enumerate(candidates[:9]):
            btn = ttk.Button(
                self.hanzi_frame,
                text=hanzi,
                command=lambda h=hanzi: self._select_hanzi(h),
                width=3
            )
            btn.grid(row=0, column=i, padx=2, pady=2)

    def _select_hanzi(self, hanzi: str):
        """选择候选汉字"""
        try:
            current_text = self.result_display.cget("text")
            self.result_display["text"] = current_text + hanzi
            self.input_entry.delete(0, tk.END)
            self.pinyin_display['text'] = ""
            self._update_hanzi_buttons([])
        except tk.TclError as e:
            self._show_error_message(f"更新显示失败: {str(e)}")


    def copy_to_clipboard(self):
        """复制结果到剪贴板"""
        text = self.result_display.cget("text")
        if text:
            pyperclip.copy(text)
            self._show_temporary_message("(已复制到剪贴板)")

    def _paste_from_clipboard(self):
        """从剪贴板粘贴到输入框"""
        try:
            text = pyperclip.paste()
            if text:
                self.input_entry.delete(0, tk.END)
                self.input_entry.insert(0, text)
                # 手动触发输入变化处理
                self.on_input_change()
                # 强制刷新界面
                self.master.update()
        except Exception:
            self._show_error_message("无法从剪贴板粘贴")

    def clear_display(self):
        """清空所有显示"""
        self.input_entry.delete(0, tk.END)
        self.pinyin_display['text'] = ""

        try:
            self.result_display["text"] = ""
        except tk.TclError as e:
            self._show_error_message(f"清空显示失败: {str(e)}")

        for widget in self.hanzi_frame.winfo_children():
            widget.destroy()
        self.current_candidates = []

    def _show_temporary_message(self, message: str, delay: int = 1000):
        """显示临时消息"""
        if hasattr(self, '_message_timer'):
            self.master.after_cancel(self._message_timer)
        original_text = self.result_display.cget("text")
        original_fg = self.result_display.cget("foreground")
        self.result_display["text"] = message
        self.result_display["foreground"] = "black"
        self._message_timer = self.master.after(delay, lambda: (
            self.result_display.configure(text=original_text),
            self.result_display.configure(foreground=original_fg)
        ))


    def _show_error_message(self, message: str):
        """显示错误消息"""
        if not hasattr(self, 'result_display'):
            # 确保有结果显示区域
            self.result_display = ttk.Label(self.master)
            self.result_display.pack()

        self.result_display["text"] = message
        self.result_display["foreground"] = "red"

    # 修改gui_input.py中的load_yinyuan_sequence方法
    def load_yinyuan_sequence(self):
        """从数据库加载音元序列并显示在输入框"""
        try:
            conn = self._get_db_connection()
            c = conn.cursor()

            # 首先检查表是否存在
            c.execute("SELECT name FROM sqlite_master WHERE type='table' AND name='yinjie_mapping'")
            if not c.fetchone():
                self._show_error_message("yinjie_mapping表不存在")
                return None

            # 检查表结构
            c.execute("PRAGMA table_info(yinjie_mapping)")
            columns = [col[1] for col in c.fetchall()]
            if 'symbol' not in columns:
                self._show_error_message("yinjie_mapping表缺少symbol字段")
                return None

            # 查询所有音元符号
            c.execute("SELECT symbol FROM yinjie_mapping ORDER BY mark_tone")
            rows = c.fetchall()

            if rows:
                sequence = "".join([row['symbol'] for row in rows])
                self.input_entry.delete(0, tk.END)
                self.input_entry.insert(0, sequence)
                self.on_input_change()
                return sequence
            else:
                self._show_error_message("数据库中没有音元数据")
                return None

        except sqlite3.Error as e:
            self._show_error_message(f"读取音元序列失败: {str(e)}")
            return None

    def _get_db_connection(self):
        """获取数据库连接(单例模式)"""
        if not hasattr(self, '_db_conn') or self._db_conn is None:
            try:
                self._db_conn = sqlite3.connect(self.db_path)
                self._db_conn.row_factory = sqlite3.Row
            except sqlite3.Error as e:
                self._show_error_message(f"数据库连接失败: {str(e)}")
                raise
        return self._db_conn

def main():
    """主函数"""
    # 调试代码：查询数据库（使用正确路径）
    try:
        script_dir = os.path.dirname(os.path.abspath(__file__))
        db_path = os.path.join(script_dir, "pinyin_hanzi.db")

        print(f"\n尝试打开数据库: {db_path}")
        conn = sqlite3.connect(db_path)
        cursor = conn.cursor()

        print("\n=== 数据库调试信息 ===")
        cursor.execute("SELECT * FROM yinjie_mapping LIMIT 3")
        print("yinjie_mapping 表样例:", cursor.fetchall())

        cursor.execute("SELECT * FROM pinyin_hanzi LIMIT 3")
        print("pinyin_hanzi 表样例:", cursor.fetchall())

        conn.close()
    except Exception as e:
        print(f"数据库调试错误: {str(e)}")

    # 正常启动GUI
    root = tk.Tk()
    app = HanziInputApp(root)
    root.mainloop()

if __name__ == "__main__":
    main()
