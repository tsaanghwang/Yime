from yime.input_method.ui.candidate_box_actions import CandidateBoxActions
from yime.input_method.ui.candidate_box import CandidateBox


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
        self.clipboard_contents: list[str] = []
        self.clipboard_cleared = 0
        self.updated = False

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

    def clipboard_clear(self) -> None:
        self.clipboard_cleared += 1
        self.clipboard_contents.clear()

    def clipboard_append(self, text: str) -> None:
        self.clipboard_contents.append(text)

    def update_idletasks(self) -> None:
        self.updated = True


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
        self.reverse_lookup_display_mode_var = _FakeVar("default")
        self.page_size_changes: list[int] = []
        self.layout_changes: list[str] = []
        self.reverse_lookup_display_mode_changes: list[str] = []
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
        self.open_settings_requested = False
        self.open_runtime_data_requested = False
        self.open_troubleshooting_requested = False
        self.status = ""
        self.current_hotkey = "Ctrl+Alt+Insert"
        self.hotkey_change_requests: list[str] = []
        self.manual_input_enabled = False
        self.show_calls: list[bool] = []
        self.show_standby_calls = 0

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

    def reverse_lookup_display_mode_change_callback(self, mode: str) -> bool:
        self.reverse_lookup_display_mode_var.set(mode)
        self.reverse_lookup_display_mode_changes.append(mode)
        return True

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

    def set_manual_input_enabled(self, enabled: bool) -> None:
        self.manual_input_enabled = enabled

    def show(self, focus_input: bool = False) -> None:
        self.show_calls.append(focus_input)

    def show_standby(self) -> None:
        self.show_standby_calls += 1

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

    def open_settings_file_callback(self) -> bool:
        self.open_settings_requested = True
        return True

    def open_user_data_dir_callback(self) -> bool:
        return self.open_settings_file_callback()

    def open_runtime_data_dir_callback(self) -> bool:
        self.open_runtime_data_requested = True
        return True

    def open_troubleshooting_doc_callback(self) -> bool:
        self.open_troubleshooting_requested = True
        return True

    def hotkey_summary_callback(self) -> str:
        return f"当前热键：{self.current_hotkey}"

    def runtime_readiness_summary_callback(self) -> str:
        return (
            "当前模式：热键模式\n"
            "诊断结论：当前未发现警告或提示，共 5 项正常。\n"
            "已确认正常：\n"
            "- 唤起方式：正常。按 Ctrl+Shift+Y 或 点击右下角的'音'图标\n"
            "- 休眠方式：正常。再次按 Ctrl+Shift+Y 或 右键候选框\n"
            "- 热键状态：正常。已启用 Ctrl+Shift+Y\n"
            "- 候选来源：正常。运行时 JSON 导出文件\n"
            "- 当前版本：正常。git:abc1234"
        )

    def runtime_data_guidance_callback(self) -> str:
        return (
            "运行时数据指引：\n"
            "1. 先检查文件：C:/dev/Yime/yime/reports/runtime_candidates_by_code_true.json\n"
            "2. 若文件缺失、为空或明显过旧，可在仓库根目录运行：python -m yime.export_runtime_candidates_json"
        )

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
    commands: list[tuple[str, object, str]] = []

    class _FakeMenu:
        def __init__(self, root: object, tearoff: bool) -> None:
            self.root = root
            self.tearoff = tearoff

        def add_command(self, label: str, command: object, state: str = "normal") -> None:
            commands.append((label, command, state))

    box = _FakeBox()
    actions = CandidateBoxActions(box)
    monkeypatch.setattr("yime.input_method.ui.candidate_box_actions.tk.Menu", _FakeMenu)

    actions._get_input_context_menu()

    assert [label for label, _, _ in commands] == ["粘贴", "复制", "全选", "添加当前词条", "删除当前词条"]
    assert [state for _, _, state in commands] == ["normal", "normal", "normal", "normal", "normal"]

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
    commands: list[tuple[str, object, str]] = []
    cascades: list[tuple[str, object, str]] = []
    popup_calls: list[tuple[int, int]] = []
    grab_release_calls: list[bool] = []
    radio_buttons: list[tuple[str, int, object, object]] = []
    check_buttons: list[tuple[str, object, object]] = []
    separators: list[bool] = []

    class _FakeMenu:
        def __init__(self, root: object, tearoff: bool) -> None:
            self.root = root
            self.tearoff = tearoff

        def add_command(self, label: str, command: object, state: str = "normal") -> None:
            commands.append((label, command, state))

        def add_cascade(self, label: str, menu: object, state: str = "normal") -> None:
            cascades.append((label, menu, state))

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

    command_labels = [label for label, _, _ in commands]
    assert command_labels == ["设置反查时显示哪些内容", "当前唤起热键：Ctrl+Alt+Insert", "修改热键", "添加当前词条", "删除当前词条", "编辑用户词库", "应用用户词库", "导入用户词库", "导出用户词库", "查看帮助", "查看试用反馈说明", "复制试用反馈模板", "查看诊断", "重新检查诊断", "复制诊断信息", "查看试用反馈说明", "复制试用反馈模板", "打开故障排查", "打开运行时数据目录", "打开设置文件", "打开帮助", "关于"]
    assert commands[2][2] == "disabled"
    assert [label for label, _, _ in cascades] == ["候选列表", "反查信息", "唤起方式", "休眠方式", "交互", "前景颜色", "背景颜色", "字体大小", "主界面透明度", "外观", "设置", "编辑与重载", "导入与导出", "用户词库", "工具", "帮助", "诊断"]
    assert all(state == "normal" for _, _, state in cascades)
    assert [label for label, _, _, _ in radio_buttons] == [
        "每页 5 个",
        "每页 6 个",
        "每页 7 个",
        "每页 8 个",
        "每页 9 个",
        "横排显示",
        "竖排显示",
        "默认（推荐：标准拼音 + 音元拼音）",
        "完整（标准拼音 + 数字标调 + 音元拼音 + 键位序列）",
        "隐藏反查信息（音元拼音熟练者可选）",
        "仅标准拼音",
        "仅音元拼音",
        "仅键位序列",
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
    assert separators == [True, True, True, True, True, True]

    actions.show_toolbar_menu()

    assert popup_calls == [(320, 264)]
    assert grab_release_calls == [True]

    radio_buttons[2][3]()
    radio_buttons[6][3]()
    radio_buttons[10][3]()
    radio_buttons[14][3]()
    radio_buttons[18][3]()
    radio_buttons[22][3]()
    radio_buttons[25][3]()
    radio_buttons[34][3]()
    radio_buttons[35][3]()
    commands[1][1]()
    box.active_topmost_var.set(False)
    check_buttons[0][2]()
    commands[3][1]()
    commands[4][1]()
    commands[5][1]()
    commands[6][1]()
    commands[7][1]()
    commands[8][1]()
    commands[9][1]()
    commands[10][1]()
    commands[11][1]()
    commands[12][1]()
    commands[13][1]()
    commands[14][1]()
    commands[15][1]()
    commands[16][1]()
    commands[17][1]()
    commands[18][1]()
    commands[19][1]()
    commands[20][1]()
    commands[21][1]()

    assert feedback_calls[0] == (
        "快捷键",
        "当前热键：Ctrl+Alt+Insert",
    )
    assert feedback_calls[1][0] == "帮助"
    assert "普通用户帮助" in feedback_calls[1][1]
    assert "推荐阅读顺序" in feedback_calls[1][1]
    assert "菜单与用户词库" in feedback_calls[1][1]
    assert feedback_calls[1][1].endswith("当前热键：Ctrl+Alt+Insert")
    assert feedback_calls[2][0] == "试用反馈说明"
    assert "如果你只想给我最短反馈，直接告诉我下面哪一种最接近：" in feedback_calls[2][1]
    assert feedback_calls[3] == ("试用反馈", "试用反馈模板已复制。现在可直接发给试用者填写。")
    assert feedback_calls[4][0] == "诊断"
    assert "当前模式：热键模式" in feedback_calls[4][1]
    assert "诊断结论：当前未发现警告或提示，共 5 项正常。" in feedback_calls[4][1]
    assert "已确认正常：" in feedback_calls[4][1]
    assert "- 候选来源：正常。运行时 JSON 导出文件" in feedback_calls[4][1]
    assert "- 当前版本：正常。git:abc1234" in feedback_calls[4][1]
    assert "运行时数据指引：" in feedback_calls[4][1]
    assert "python -m yime.export_runtime_candidates_json" in feedback_calls[4][1]
    assert feedback_calls[4][1].endswith("当前热键：Ctrl+Alt+Insert")
    assert feedback_calls[5][0] == "诊断"
    assert feedback_calls[5][1] == feedback_calls[4][1]
    assert box.status == "已重新检查诊断；可直接查看上面的结果。"
    assert feedback_calls[6] == ("诊断", "诊断信息已复制。现在可直接粘贴给 GitHub Copilot。")
    assert feedback_calls[7][0] == "试用反馈说明"
    assert "如果你只想给我最短反馈，直接告诉我下面哪一种最接近：" in feedback_calls[7][1]
    assert "- 能打开但唤不起候选框" in feedback_calls[7][1]
    assert "如果愿意再多写一句，补这 3 件事就够了：" in feedback_calls[7][1]
    assert feedback_calls[8] == ("试用反馈", "试用反馈模板已复制。现在可直接发给试用者填写。")
    assert box.root.clipboard_cleared == 3
    assert len(box.root.clipboard_contents) == 1
    assert box.root.clipboard_contents[0].startswith("【Yime 试用反馈模板】")
    assert "请先告诉我下面哪一种最接近：" in box.root.clipboard_contents[0]
    assert "- 能打开但唤不起候选框" in box.root.clipboard_contents[0]
    assert "再补充 3 件事：" in box.root.clipboard_contents[0]
    assert "如果方便，也请把下面这份诊断信息一起发来：" in box.root.clipboard_contents[0]
    assert "当前模式：热键模式" in box.root.clipboard_contents[0]
    assert "- 当前版本：正常。git:abc1234" in box.root.clipboard_contents[0]
    assert box.root.clipboard_contents[0].endswith("当前热键：Ctrl+Alt+Insert")
    assert box.root.updated is True
    assert box.open_troubleshooting_requested is True
    assert box.open_runtime_data_requested is True
    assert box.open_settings_requested is True
    assert feedback_calls[9][0] == "帮助"
    assert "普通用户帮助" in feedback_calls[9][1]
    assert feedback_calls[9][1].endswith("当前热键：Ctrl+Alt+Insert")
    assert feedback_calls[10] == (
        "关于",
        "音元拼音输入法当前使用轻量候选窗界面。这个菜单入口用于集中承载设置、帮助和后续扩展功能。",
    )
    assert box.page_size_changes == [7]
    assert box.page_size_var.get() == 7
    assert box.layout_changes == ["vertical"]
    assert box.reverse_lookup_display_mode_changes == ["marked"]
    assert box.wake_trigger_mode_changes == ["mouse"]
    assert box.standby_trigger_mode_changes == ["both"]
    assert box.foreground_color_changes == ["#166534"]
    assert box.background_color_changes == ["#f0f0f0"]
    assert box.ui_scale_changes == [120]
    assert box.active_alpha_changes == [85]
    assert box.active_topmost_changes == [False]
    assert box.hotkey_change_requests == []
    assert box.added_to_user_lexicon is True
    assert box.deleted_from_user_lexicon is True
    assert box.edit_requested is True
    assert box.reload_requested is True
    assert box.import_requested is True
    assert box.export_requested is True
    assert box.status == "已重新检查诊断；可直接查看上面的结果。"


def test_reverse_lookup_menu_includes_intro_item(monkeypatch) -> None:
    commands: list[tuple[str, object, str]] = []
    separators: list[bool] = []

    class _FakeMenu:
        def __init__(self, root: object, tearoff: bool) -> None:
            self.root = root
            self.tearoff = tearoff

        def add_command(self, label: str, command: object, state: str = "normal") -> None:
            commands.append((label, command, state))

        def add_separator(self) -> None:
            separators.append(True)

        def add_radiobutton(self, label: str, value: object, variable: object, command: object) -> None:
            return None

    monkeypatch.setattr("yime.input_method.ui.candidate_box_actions.tk.Menu", _FakeMenu)

    actions = CandidateBoxActions(_FakeBox())
    actions._get_reverse_lookup_display_menu()

    assert commands == [("设置反查时显示哪些内容", commands[0][1], "disabled")]
    assert separators == [True]


def test_set_reverse_lookup_display_mode_reports_clearer_status() -> None:
    box = _FakeBox()

    actions = CandidateBoxActions(box)
    actions.set_reverse_lookup_display_mode("default")
    assert box.status == "反查显示已设为默认：显示标准拼音和音元拼音，适合日常查看，例如“rì | 甲甲”。"

    actions.set_reverse_lookup_display_mode("all")
    assert box.status == "反查显示已设为完整：同时显示标准拼音、数字标调、音元拼音和键位序列，例如“rì | ri4 | 甲甲 | qj”。"

    actions.set_reverse_lookup_display_mode("none")
    assert box.status == "反查显示已设为隐藏：不显示反查信息，仅保留候选和状态，例如只看候选列表。"

    actions.set_reverse_lookup_display_mode("marked")
    assert box.status == "反查显示已设为仅标准拼音：只显示带声调的标准拼音，例如“rì”。"

    actions.set_reverse_lookup_display_mode("yime")
    assert box.status == "反查显示已设为仅音元拼音：只显示音元拼音编码，例如“甲甲”。"

    actions.set_reverse_lookup_display_mode("keys")
    assert box.status == "反查显示已设为仅键位序列：只显示需要敲的键位序列，例如“qj”。"


def test_visual_setting_statuses_use_user_facing_labels() -> None:
    box = _FakeBox()

    actions = CandidateBoxActions(box)

    actions.set_ui_scale(120)
    assert box.status == "界面字号已设为 120%。"

    actions.set_active_alpha(85)
    assert box.status == "候选窗透明度已设为 85%。"

    actions.set_foreground_color("#166534")
    assert box.status == "文字颜色已设为墨绿色。"

    actions.set_background_color("#f0f0f0")
    assert box.status == "界面底色已设为默认背景。"

    box.active_topmost_var.set(True)
    actions.toggle_active_topmost()
    assert box.status == "候选窗将保持在最前。"

    box.active_topmost_var.set(False)
    actions.toggle_active_topmost()
    assert box.status == "候选窗已取消置顶，可让其他窗口盖住它。"


def test_list_and_trigger_setting_statuses_use_direct_action_guidance() -> None:
    box = _FakeBox()

    actions = CandidateBoxActions(box)

    actions.set_candidate_page_size(7)
    assert box.status == "现在每页显示 7 个候选。"

    actions.set_candidate_layout("vertical")
    assert box.status == "候选现在按竖排显示。"

    actions.set_wake_trigger_mode("mouse")
    assert box.status == "之后可通过仅鼠标唤起候选窗。"

    actions.set_standby_trigger_mode("both")
    assert box.status == "之后可通过热键 + 鼠标让候选窗回到待命。"


def test_user_lexicon_menu_items_are_disabled_when_hooks_are_missing(monkeypatch) -> None:
    commands: list[tuple[str, object, str]] = []
    cascades: list[tuple[str, object, str]] = []

    class _FakeMenu:
        def __init__(self, root: object, tearoff: bool) -> None:
            self.root = root
            self.tearoff = tearoff

        def add_command(self, label: str, command: object, state: str = "normal") -> None:
            commands.append((label, command, state))

        def add_cascade(self, label: str, menu: object, state: str = "normal") -> None:
            cascades.append((label, menu, state))

        def add_radiobutton(self, label: str, value: object, variable: object, command: object) -> None:
            return None

        def add_checkbutton(self, label: str, variable: object, command: object) -> None:
            return None

        def add_separator(self) -> None:
            return None

    class _BoxWithoutLexiconHooks(_FakeBox):
        def __init__(self) -> None:
            super().__init__()
            self._on_add_input_to_user_lexicon = None
            self._on_delete_input_from_user_lexicon = None
            self._on_edit_user_lexicon = None
            self._on_reload_user_lexicon = None
            self._on_import_user_lexicon = None
            self._on_export_user_lexicon = None

    monkeypatch.setattr("yime.input_method.ui.candidate_box_actions.tk.Menu", _FakeMenu)

    actions = CandidateBoxActions(_BoxWithoutLexiconHooks())
    actions._get_input_context_menu()
    actions._get_user_lexicon_menu()
    actions._get_tools_menu()
    actions._get_toolbar_menu()

    lexicon_states = {
        label: state
        for label, _, state in commands
        if label
        in {
            "添加当前词条",
            "删除当前词条",
            "编辑用户词库",
            "应用用户词库",
            "导入用户词库",
            "导出用户词库",
        }
    }
    assert lexicon_states == {
        "添加当前词条": "disabled",
        "删除当前词条": "disabled",
        "编辑用户词库": "disabled",
        "应用用户词库": "disabled",
        "导入用户词库": "disabled",
        "导出用户词库": "disabled",
    }
    cascade_states = {
        label: state
        for label, _, state in cascades
        if label in {"编辑与重载", "导入与导出", "用户词库", "工具"}
    }
    assert cascade_states == {
        "编辑与重载": "disabled",
        "导入与导出": "disabled",
        "用户词库": "disabled",
        "工具": "disabled",
    }


def test_diagnostics_open_items_are_disabled_when_hooks_are_missing(monkeypatch) -> None:
    commands: list[tuple[str, object, str]] = []
    cascades: list[tuple[str, object, str]] = []

    class _FakeMenu:
        def __init__(self, root: object, tearoff: bool) -> None:
            self.root = root
            self.tearoff = tearoff

        def add_command(self, label: str, command: object, state: str = "normal") -> None:
            commands.append((label, command, state))

        def add_cascade(self, label: str, menu: object, state: str = "normal") -> None:
            cascades.append((label, menu, state))

        def add_radiobutton(self, label: str, value: object, variable: object, command: object) -> None:
            return None

        def add_checkbutton(self, label: str, variable: object, command: object) -> None:
            return None

        def add_separator(self) -> None:
            return None

    class _BoxWithoutDiagnosticOpenHooks(_FakeBox):
        def __init__(self) -> None:
            super().__init__()
            self._on_open_troubleshooting_doc = None
            self._on_open_runtime_data_dir = None
            self._on_open_settings_file = None
            self._on_open_user_data_dir = None

    monkeypatch.setattr("yime.input_method.ui.candidate_box_actions.tk.Menu", _FakeMenu)

    actions = CandidateBoxActions(_BoxWithoutDiagnosticOpenHooks())
    actions._get_diagnostics_menu()
    actions._get_toolbar_menu()

    diagnostic_states = {
        label: state
        for label, _, state in commands
        if label in {"打开故障排查", "打开运行时数据目录", "打开设置文件"}
    }
    assert diagnostic_states == {
        "打开故障排查": "disabled",
        "打开运行时数据目录": "disabled",
        "打开设置文件": "disabled",
    }
    top_level_states = {
        label: state for label, _, state in cascades if label in {"设置", "帮助", "诊断"}
    }
    assert top_level_states == {
        "设置": "normal",
        "帮助": "normal",
        "诊断": "normal",
    }


def test_edit_hotkey_menu_item_is_always_disabled(monkeypatch) -> None:
    commands: list[tuple[str, object, str]] = []
    cascades: list[tuple[str, object, str]] = []

    class _FakeMenu:
        def __init__(self, root: object, tearoff: bool) -> None:
            self.root = root
            self.tearoff = tearoff

        def add_command(self, label: str, command: object, state: str = "normal") -> None:
            commands.append((label, command, state))

        def add_separator(self) -> None:
            return None

        def add_cascade(self, label: str, menu: object, state: str = "normal") -> None:
            cascades.append((label, menu, state))

        def add_radiobutton(self, label: str, value: object, variable: object, command: object) -> None:
            return None

    monkeypatch.setattr("yime.input_method.ui.candidate_box_actions.tk.Menu", _FakeMenu)

    actions = CandidateBoxActions(_FakeBox())
    actions._get_interaction_menu()

    interaction_states = {
        label: state for label, _, state in commands if label in {"当前唤起热键：Ctrl+Alt+Insert", "修改热键"}
    }
    assert interaction_states == {
        "当前唤起热键：Ctrl+Alt+Insert": "normal",
        "修改热键": "disabled",
    }


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

    assert feedback_calls == [("用户词库", "当前不能直接添加当前词条；请先确认已启用用户词库功能。")]
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

    assert feedback_calls == [("用户词库", "当前不能直接删除当前词条；请先确认已启用用户词库功能。")]


def test_unconfigured_action_entries_offer_next_step_guidance(monkeypatch) -> None:
    feedback_calls: list[tuple[str, str]] = []

    class _BoxWithoutOptionalActions(_FakeBox):
        def __init__(self) -> None:
            super().__init__()
            self.feedback_callback = lambda title, message: feedback_calls.append((title, message))

        def reload_user_lexicon_callback(self) -> bool:
            return False

        def edit_user_lexicon_callback(self) -> bool:
            return False

        def import_user_lexicon_callback(self) -> bool:
            return False

        def export_user_lexicon_callback(self) -> bool:
            return False

        def open_settings_file_callback(self) -> bool:
            return False

        def open_user_data_dir_callback(self) -> bool:
            return False

        def open_runtime_data_dir_callback(self) -> bool:
            return False

        def open_troubleshooting_doc_callback(self) -> bool:
            return False

        def hotkey_change_callback(self, hotkey: str) -> bool:
            return False

    box = _BoxWithoutOptionalActions()
    actions = CandidateBoxActions(box)

    monkeypatch.setattr(
        "yime.input_method.ui.candidate_box_actions.simpledialog.askstring",
        lambda *args, **kwargs: "Ctrl+Shift+Y",
    )

    actions.reload_user_lexicon()
    actions.edit_user_lexicon()
    actions.import_user_lexicon()
    actions.export_user_lexicon()
    actions.open_settings_file()
    actions.open_runtime_data_dir()
    actions.open_troubleshooting_doc()

    original_hotkey_callback = box.hotkey_change_callback
    box.hotkey_change_callback = None  # type: ignore[assignment]
    try:
        actions.edit_hotkey()
    finally:
        box.hotkey_change_callback = original_hotkey_callback

    assert feedback_calls == [
        ("用户词库", "当前不能直接应用用户词库；请先确认已启用用户词库维护功能。"),
        ("用户词库", "当前不能直接编辑用户词库；请先改用导入、导出或手动维护文件。"),
        ("用户词库", "当前不能直接导入用户词库；请先确认已启用用户词库维护功能。"),
        ("用户词库", "当前不能直接导出用户词库；请先确认已启用用户词库维护功能。"),
        ("设置文件", "当前不能直接打开设置文件；请先从帮助或诊断里确认配置位置。"),
        ("运行时数据", "当前不能直接打开运行时数据目录；请先在诊断里查看运行时数据指引。"),
        ("故障排查", "当前不能直接打开故障排查文档；请先从帮助菜单查看相关说明。"),
        ("快捷键", "当前不能直接修改热键；请先记下当前热键，并到设置文件中调整。"),
    ]


def test_copy_actions_report_manual_fallback_when_clipboard_is_unavailable() -> None:
    feedback_calls: list[tuple[str, str]] = []

    class _RootWithoutClipboard:
        def update_idletasks(self) -> None:
            return None

    class _BoxWithoutClipboard(_FakeBox):
        def __init__(self) -> None:
            super().__init__()
            self.root = _RootWithoutClipboard()
            self.feedback_callback = lambda title, message: feedback_calls.append((title, message))

    box = _BoxWithoutClipboard()
    actions = CandidateBoxActions(box)

    actions.copy_diagnostics()
    actions.copy_trial_feedback_template()

    assert feedback_calls == [
        ("诊断", "当前环境暂时不能复制诊断信息；请先打开诊断窗口，再手动复制内容。"),
        ("试用反馈", "当前环境暂时不能复制试用反馈模板；请先打开“试用反馈说明”，再手动整理给试用者。"),
    ]


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
    assert box.status == "已上屏: 安。可继续输入下一词。"
    assert box.feedback_calls == []


def test_select_candidate_updates_status_with_next_step_guidance() -> None:
    class _BoxWithCandidate(_FakeBox):
        def __init__(self) -> None:
            super().__init__()
            self.current_candidates = ["安"]
            self.commit_text = ""
            self.selected: list[str] = []
            self.cleared_with_focus: list[bool] = []

        def get_candidate(self, index: int) -> object:
            if index == 0:
                return "安"
            return None

        def append_commit_text(self, text: str) -> None:
            self.commit_text += text

        def get_commit_text(self) -> str:
            return self.commit_text

        def on_select(self, text: str) -> None:
            self.selected.append(text)

        def clear_input(self, focus_input: bool = False) -> None:
            self.cleared_with_focus.append(focus_input)

        def is_manual_input_enabled(self) -> bool:
            return True

    box = _BoxWithCandidate()

    selected = CandidateBoxActions(box).select_candidate_by_index(0)

    assert selected is True
    assert box.selected == ["安"]
    assert box.commit_text == "安"
    assert box.cleared_with_focus == [True]
    assert box.status == "已加入待上屏内容: 安。可继续选词，或按空格/回车上屏。"


def test_standby_controls_fall_back_to_local_behavior_without_callbacks() -> None:
    class _BoxWithoutStandbyHooks(_FakeBox):
        def restore_from_standby_callback(self) -> bool:
            return False

        def toggle_standby_callback(self) -> bool:
            return False

    box = _BoxWithoutStandbyHooks()
    actions = CandidateBoxActions(box)

    assert actions.restore_from_standby() == "break"
    assert box.manual_input_enabled is True
    assert box.show_calls == [True]

    assert actions.request_standby() == "break"
    assert box.show_standby_calls == 1


def test_remove_last_commit_char_uses_user_facing_status() -> None:
    class _CommitVar:
        def __init__(self, value: str) -> None:
            self.value = value

        def get(self) -> str:
            return self.value

        def set(self, value: str) -> None:
            self.value = value

    class _FakeCandidateBox:
        def __init__(self, value: str) -> None:
            self.commit_var = _CommitVar(value)
            self.status = ""

        def set_status(self, text: str) -> None:
            self.status = text

    empty_box = _FakeCandidateBox("")
    CandidateBox.remove_last_commit_char(empty_box)
    assert empty_box.status == "当前没有可撤销的待上屏内容。"

    filled_box = _FakeCandidateBox("安心")
    CandidateBox.remove_last_commit_char(filled_box)
    assert filled_box.commit_var.get() == "安"
    assert filled_box.status == "已撤销最后一字。当前待上屏内容: 安"

    single_box = _FakeCandidateBox("安")
    CandidateBox.remove_last_commit_char(single_box)
    assert single_box.commit_var.get() == ""
    assert single_box.status == "已撤销最后一字；待上屏内容已清空。"


def test_edit_hotkey_updates_status_with_next_step_guidance(monkeypatch) -> None:
    box = _FakeBox()
    actions = CandidateBoxActions(box)

    monkeypatch.setattr(
        "yime.input_method.ui.candidate_box_actions.simpledialog.askstring",
        lambda *args, **kwargs: "Ctrl+Shift+Y",
    )

    actions.edit_hotkey()

    assert box.hotkey_change_requests == ["Ctrl+Shift+Y"]
    assert box.status == "之后可按Ctrl+Shift+Y唤起候选窗。"
