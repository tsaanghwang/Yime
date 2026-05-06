from yime.input_method.ui.candidate_box_actions import CandidateBoxActions


class _FakeWidget:
    def __init__(self) -> None:
        self.bindings: list[tuple[str, object]] = []
        self.generated_events: list[str] = []
        self.selection_ranges: list[tuple[object, object]] = []
        self.cursor_positions: list[object] = []
        self.focused = False
        self.rootx = 320
        self.rooty = 240
        self.height = 24

    def bind(self, sequence: str, handler: object) -> None:
        self.bindings.append((sequence, handler))

    def event_generate(self, sequence: str) -> None:
        self.generated_events.append(sequence)

    def selection_range(self, start: object, end: object) -> None:
        self.selection_ranges.append((start, end))

    def icursor(self, index: object) -> None:
        self.cursor_positions.append(index)

    def focus_set(self) -> None:
        self.focused = True

    def winfo_rootx(self) -> int:
        return self.rootx

    def winfo_rooty(self) -> int:
        return self.rooty

    def winfo_height(self) -> int:
        return self.height


class _FakeBox:
    def __init__(self) -> None:
        self.root = _FakeWidget()
        self.input_entry = _FakeWidget()
        self.commit_entry = _FakeWidget()
        self.candidate_text = _FakeWidget()
        self.first_page_button = None
        self.prev_button = None
        self.next_button = None
        self.last_page_button = None
        self.toolbar_menu_button = None
        self._on_manual_input_key_press = object()
        self.added_to_user_lexicon = False
        self.deleted_from_user_lexicon = False
        self.page_size_var = _FakeVar(5)
        self.candidate_layout_var = _FakeVar("horizontal")
        self.wake_trigger_mode_var = _FakeVar("both")
        self.standby_trigger_mode_var = _FakeVar("both")
        self.mouse_wake_var = _FakeVar(True)
        self.mouse_standby_var = _FakeVar(True)
        self.ui_scale_var = _FakeVar(100)
        self.active_alpha_var = _FakeVar(97)
        self.foreground_color_var = _FakeVar("#111827")
        self.background_color_var = _FakeVar("#f0f0f0")
        self.active_topmost_var = _FakeVar(True)
        self.page_size_changes: list[int] = []
        self.layout_changes: list[str] = []
        self.wake_trigger_mode_changes: list[str] = []
        self.standby_trigger_mode_changes: list[str] = []
        self.mouse_wake_changes: list[bool] = []
        self.mouse_standby_changes: list[bool] = []
        self.ui_scale_changes: list[int] = []
        self.active_alpha_changes: list[int] = []
        self.foreground_color_changes: list[str] = []
        self.background_color_changes: list[str] = []
        self.active_topmost_changes: list[bool] = []
        self.reload_requested = False
        self.edit_requested = False
        self.import_requested = False
        self.export_requested = False
        self.open_dir_requested = False
        self.status = ""
        self.current_hotkey = "Ctrl+Alt+Insert"
        self.hotkey_change_requests: list[str] = []

    def clear_input(self) -> None:
        return None

    def add_input_to_user_lexicon_callback(self) -> bool:
        self.added_to_user_lexicon = True
        return True

    def delete_input_from_user_lexicon_callback(self) -> bool:
        self.deleted_from_user_lexicon = True
        return True

    def set_page_size(self, page_size: int) -> None:
        self.page_size_var.set(page_size)
        self.page_size_changes.append(page_size)

    def set_candidate_layout(self, layout: str) -> None:
        self.candidate_layout_var.set(layout)
        self.layout_changes.append(layout)

    def wake_trigger_mode_change_callback(self, mode: str) -> bool:
        self.wake_trigger_mode_var.set(mode)
        self.wake_trigger_mode_changes.append(mode)
        return True

    def standby_trigger_mode_change_callback(self, mode: str) -> bool:
        self.standby_trigger_mode_var.set(mode)
        self.standby_trigger_mode_changes.append(mode)
        return True

    def set_mouse_wake_enabled(self, enabled: bool) -> None:
        self.mouse_wake_var.set(enabled)
        self.mouse_wake_changes.append(enabled)

    def set_mouse_standby_enabled(self, enabled: bool) -> None:
        self.mouse_standby_var.set(enabled)
        self.mouse_standby_changes.append(enabled)

    def set_ui_scale(self, scale_percent: int) -> None:
        self.ui_scale_var.set(scale_percent)
        self.ui_scale_changes.append(scale_percent)

    def set_active_alpha_percent(self, alpha_percent: int) -> None:
        self.active_alpha_var.set(alpha_percent)
        self.active_alpha_changes.append(alpha_percent)

    def set_foreground_color(self, color: str) -> None:
        self.foreground_color_var.set(color)
        self.foreground_color_changes.append(color)

    def set_background_color(self, color: str) -> None:
        self.background_color_var.set(color)
        self.background_color_changes.append(color)

    def set_active_topmost_enabled(self, enabled: bool) -> None:
        self.active_topmost_var.set(enabled)
        self.active_topmost_changes.append(enabled)

    def foreground_color_change_callback(self, color: str) -> bool:
        self.foreground_color_var.set(color)
        self.foreground_color_changes.append(color)
        return True

    def background_color_change_callback(self, color: str) -> bool:
        self.background_color_var.set(color)
        self.background_color_changes.append(color)
        return True

    def set_status(self, text: str) -> None:
        self.status = text

    def reload_user_lexicon_callback(self) -> bool:
        self.reload_requested = True
        return True

    def edit_user_lexicon_callback(self) -> bool:
        self.edit_requested = True
        return True

    def import_user_lexicon_callback(self) -> bool:
        self.import_requested = True
        return True

    def export_user_lexicon_callback(self) -> bool:
        self.export_requested = True
        return True

    def open_user_data_dir_callback(self) -> bool:
        self.open_dir_requested = True
        return True

    def hotkey_summary_callback(self) -> str:
        return f"当前热键：{self.current_hotkey}"

    def hotkey_label_callback(self) -> str:
        return self.current_hotkey

    def hotkey_change_callback(self, hotkey: str) -> bool:
        self.current_hotkey = hotkey
        self.hotkey_change_requests.append(hotkey)
        return True


class _FakeVar:
    def __init__(self, value: object) -> None:
        self.value = value

    def get(self) -> object:
        return self.value

    def set(self, value: object) -> None:
        self.value = value


def test_bind_keys_wires_manual_input_keypress_handler() -> None:
    box = _FakeBox()

    CandidateBoxActions(box).bind_keys()

    assert ("<KeyPress>", box._on_manual_input_key_press) in box.input_entry.bindings
    assert ("<<Paste>>", CandidateBoxActions(box).on_paste) not in box.input_entry.bindings
    assert any(sequence == "<<Paste>>" for sequence, _ in box.input_entry.bindings)
    assert any(sequence == "<Shift-Insert>" for sequence, _ in box.input_entry.bindings)
    assert any(sequence == "<Button-3>" for sequence, _ in box.input_entry.bindings)


def test_bind_keys_wires_toolbar_menu_button() -> None:
    box = _FakeBox()
    box.toolbar_menu_button = _FakeWidget()

    CandidateBoxActions(box).bind_keys()

    assert any(sequence == "<Button-1>" for sequence, _ in box.toolbar_menu_button.bindings)


def test_input_context_menu_uses_chinese_labels_and_selects_input_text(monkeypatch) -> None:
    commands: list[tuple[str, object]] = []

    class _FakeMenu:
        def __init__(self, root: object, tearoff: bool) -> None:
            self.root = root
            self.tearoff = tearoff

        def add_command(self, label: str, command: object) -> None:
            commands.append((label, command))

    box = _FakeBox()
    actions = CandidateBoxActions(box)
    monkeypatch.setattr("yime.input_method.ui.candidate_box_actions.tk.Menu", _FakeMenu)

    actions._get_input_context_menu()

    assert [label for label, _ in commands] == ["粘贴", "复制", "全选", "加入用户词库", "从用户词库中删除"]

    commands[0][1]()
    commands[1][1]()
    commands[2][1]()
    commands[3][1]()
    commands[4][1]()

    assert box.input_entry.generated_events == ["<<Paste>>", "<<Copy>>"]
    assert box.input_entry.selection_ranges == [(0, "end")]
    assert box.input_entry.cursor_positions == ["end"]
    assert box.input_entry.focused is True
    assert box.added_to_user_lexicon is True
    assert box.deleted_from_user_lexicon is True


def test_toolbar_menu_uses_expected_labels_and_popup_position(monkeypatch) -> None:
    commands: list[tuple[str, object]] = []
    cascades: list[tuple[str, object]] = []
    popup_calls: list[tuple[int, int]] = []
    grab_release_calls: list[bool] = []
    radio_buttons: list[tuple[str, int, object, object]] = []
    check_buttons: list[tuple[str, object, object]] = []
    separators: list[bool] = []

    class _FakeMenu:
        def __init__(self, root: object, tearoff: bool) -> None:
            self.root = root
            self.tearoff = tearoff

        def add_command(self, label: str, command: object) -> None:
            commands.append((label, command))

        def add_cascade(self, label: str, menu: object) -> None:
            cascades.append((label, menu))

        def add_radiobutton(self, label: str, value: object, variable: object, command: object) -> None:
            radio_buttons.append((label, value, variable, command))

        def add_checkbutton(self, label: str, variable: object, command: object) -> None:
            check_buttons.append((label, variable, command))

        def add_separator(self) -> None:
            separators.append(True)

        def tk_popup(self, x_root: int, y_root: int) -> None:
            popup_calls.append((x_root, y_root))

        def grab_release(self) -> None:
            grab_release_calls.append(True)

    feedback_calls: list[tuple[str, str]] = []
    box = _FakeBox()
    box.toolbar_menu_button = _FakeWidget()
    box.feedback_callback = lambda title, message: feedback_calls.append((title, message))
    actions = CandidateBoxActions(box)
    monkeypatch.setattr("yime.input_method.ui.candidate_box_actions.tk.Menu", _FakeMenu)
    monkeypatch.setattr(
        "yime.input_method.ui.candidate_box_actions.simpledialog.askstring",
        lambda *args, **kwargs: "Ctrl+Shift+Y",
    )

    actions._get_toolbar_menu()

    command_labels = [label for label, _ in commands]
    assert command_labels == ["当前唤起热键：Ctrl+Alt+Insert", "修改热键", "打开设置文件并保存当前设置", "加入当前词条", "删除当前词条", "编辑用户词库", "重载用户词库", "导入用户词库", "导出用户词库", "帮助", "关于"]
    assert [label for label, _ in cascades] == ["候选列表", "唤起方式", "休眠方式", "交互", "前景颜色", "背景颜色", "字体大小", "主界面透明度", "外观", "设置", "编辑与重载", "导入与导出", "用户词库", "工具"]
    assert [label for label, _, _, _ in radio_buttons] == [
        "每页 5 个",
        "每页 6 个",
        "每页 7 个",
        "每页 8 个",
        "每页 9 个",
        "横排显示",
        "竖排显示",
        "仅热键",
        "仅鼠标",
        "热键 + 鼠标",
        "仅热键",
        "仅鼠标",
        "热键 + 鼠标",
        "默认前景",
        "石墨黑",
        "靛青蓝",
        "墨绿色",
        "赤陶棕",
        "紫檀色",
        "默认背景",
        "云雾灰",
        "米白",
        "浅青灰",
        "淡蓝灰",
        "浅杏色",
        "紧凑 90%",
        "标准 100%",
        "稍大 110%",
        "更大 120%",
        "85%",
        "92%",
        "97%",
    ]
    assert [label for label, _, _ in check_buttons] == ["活动窗始终置顶"]
    assert separators == [True, True, True]

    actions.show_toolbar_menu()

    assert popup_calls == [(320, 264)]
    assert grab_release_calls == [True]

    radio_buttons[2][3]()
    radio_buttons[6][3]()
    radio_buttons[8][3]()
    radio_buttons[12][3]()
    radio_buttons[16][3]()
    radio_buttons[19][3]()
    radio_buttons[28][3]()
    radio_buttons[29][3]()
    commands[0][1]()
    commands[1][1]()
    box.active_topmost_var.set(False)
    check_buttons[0][2]()
    commands[2][1]()
    commands[3][1]()
    commands[4][1]()
    commands[5][1]()
    commands[6][1]()
    commands[7][1]()
    commands[8][1]()
    commands[9][1]()
    commands[10][1]()

    assert feedback_calls == [
        (
            "快捷键",
            "当前热键：Ctrl+Alt+Insert",
        ),
        (
            "帮助",
            "当前推荐入口：python -m yime.input_method.app 或 python run_input_method.py。\n\n基本操作：数字键选词，Space/Enter 上屏，Home/PgUp/PgDn/End 翻页，Ctrl+Q 关闭窗口；待命时可点“音”图标或按热键唤醒。\n\n常用参数：--copy-only 只复制不回贴，--font-family 可指定候选框字体。\n\n用户词库：可右键输入框把当前汉字词语加入用户词库，也可删除当前词条；需要维护时，可用 tools/manage_user_lexicon.py 执行 list-recent、export、import、init-db、check、repair-all。\n\n常见问题：推荐环境是 Windows 10/11 + Python 3.12 + pywin32；若启动后提示“将使用手动输入模式”，先检查 Python 版本和 pywin32；若候选词为空或结果不完整，先看启动日志确认当前走的是运行时 JSON、SQLite runtime_candidates 视图，还是静态候选表。\n\n当前热键：Ctrl+Shift+Y",
        ),
        (
            "关于",
            "音元拼音输入法当前使用轻量候选窗界面。这个菜单入口用于集中承载设置、帮助和后续扩展功能。",
        ),
    ]
    assert box.page_size_changes == [7]
    assert box.page_size_var.get() == 7
    assert box.layout_changes == ["vertical"]
    assert box.wake_trigger_mode_changes == ["mouse"]
    assert box.standby_trigger_mode_changes == ["both"]
    assert box.foreground_color_changes == ["#166534"]
    assert box.background_color_changes == ["#f0f0f0"]
    assert box.ui_scale_changes == [120]
    assert box.active_alpha_changes == [85]
    assert box.active_topmost_changes == [False]
    assert box.hotkey_change_requests == ["Ctrl+Shift+Y"]
    assert box.added_to_user_lexicon is True
    assert box.deleted_from_user_lexicon is True
    assert box.edit_requested is True
    assert box.reload_requested is True
    assert box.import_requested is True
    assert box.export_requested is True
    assert box.open_dir_requested is True
    assert box.status == "活动窗置顶已关闭。"


def test_add_current_input_to_user_lexicon_uses_feedback_callback_when_unconfigured(monkeypatch) -> None:
    feedback_calls: list[tuple[str, str]] = []
    dialog_calls: list[tuple[str, str]] = []

    class _BoxWithoutLexiconHooks(_FakeBox):
        def __init__(self) -> None:
            super().__init__()
            self.feedback_callback = lambda title, message: feedback_calls.append((title, message))

        def add_input_to_user_lexicon_callback(self) -> bool:
            return False

    box = _BoxWithoutLexiconHooks()
    monkeypatch.setattr(
        "yime.input_method.ui.candidate_box_actions.messagebox.showinfo",
        lambda title, message, parent=None: dialog_calls.append((title, message)),
    )

    CandidateBoxActions(box).add_current_input_to_user_lexicon()

    assert feedback_calls == [("用户词库", "当前未配置用户词库写入入口。")]
    assert dialog_calls == []


def test_delete_current_input_from_user_lexicon_uses_feedback_callback_when_unconfigured(monkeypatch) -> None:
    feedback_calls: list[tuple[str, str]] = []
    dialog_calls: list[tuple[str, str]] = []

    class _BoxWithoutLexiconHooks(_FakeBox):
        def __init__(self) -> None:
            super().__init__()
            self.feedback_callback = lambda title, message: feedback_calls.append((title, message))

        def delete_input_from_user_lexicon_callback(self) -> bool:
            return False

    box = _BoxWithoutLexiconHooks()
    monkeypatch.setattr(
        "yime.input_method.ui.candidate_box_actions.messagebox.showinfo",
        lambda title, message, parent=None: dialog_calls.append((title, message)),
    )

    CandidateBoxActions(box).delete_current_input_from_user_lexicon()

    assert feedback_calls == [("用户词库", "当前未配置用户词库删除入口。")]
    assert dialog_calls == []


def test_commit_output_text_keeps_buffer_status_local() -> None:
    class _BoxWithCommit(_FakeBox):
        def __init__(self) -> None:
            super().__init__()
            self.status = ""
            self.commit_text = "安"
            self.commit_calls: list[str] = []
            self.feedback_calls: list[tuple[str, str]] = []
            self.feedback_callback = lambda title, message: self.feedback_calls.append((title, message))
            self.commit_text_callback = lambda text: self.commit_calls.append(text) or True

        def get_commit_text(self) -> str:
            return self.commit_text

        def set_status(self, text: str) -> None:
            self.status = text

    box = _BoxWithCommit()

    CandidateBoxActions(box).commit_output_text()

    assert box.commit_calls == ["安"]
    assert box.status == "已发送缓冲区内容: 安"
    assert box.feedback_calls == []
