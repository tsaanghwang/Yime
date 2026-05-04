from yime.input_method.ui.candidate_box_actions import CandidateBoxActions


class _FakeWidget:
    def __init__(self) -> None:
        self.bindings: list[tuple[str, object]] = []
        self.generated_events: list[str] = []
        self.selection_ranges: list[tuple[object, object]] = []
        self.cursor_positions: list[object] = []
        self.focused = False

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
        self._on_manual_input_key_press = object()
        self.added_to_user_lexicon = False
        self.deleted_from_user_lexicon = False

    def clear_input(self) -> None:
        return None

    def add_input_to_user_lexicon_callback(self) -> bool:
        self.added_to_user_lexicon = True
        return True

    def delete_input_from_user_lexicon_callback(self) -> bool:
        self.deleted_from_user_lexicon = True
        return True


def test_bind_keys_wires_manual_input_keypress_handler() -> None:
    box = _FakeBox()

    CandidateBoxActions(box).bind_keys()

    assert ("<KeyPress>", box._on_manual_input_key_press) in box.input_entry.bindings
    assert ("<<Paste>>", CandidateBoxActions(box).on_paste) not in box.input_entry.bindings
    assert any(sequence == "<<Paste>>" for sequence, _ in box.input_entry.bindings)
    assert any(sequence == "<Shift-Insert>" for sequence, _ in box.input_entry.bindings)
    assert any(sequence == "<Button-3>" for sequence, _ in box.input_entry.bindings)


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
