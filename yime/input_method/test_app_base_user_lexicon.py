from pathlib import Path

from yime.input_method.app_base import BaseInputMethodApp


class _FakeCandidateBox:
    def __init__(self, text: str) -> None:
        self._text = text
        self.statuses: list[str] = []
        self.root = object()

    def get_input(self) -> str:
        return self._text

    def set_status(self, status: str) -> None:
        self.statuses.append(status)


class _FakeReverseLookupRecord:
    def __init__(self, numeric_pinyin: str, marked_pinyin: str) -> None:
        self.numeric_pinyin = numeric_pinyin
        self.marked_pinyin = marked_pinyin


class _FakeReverseLookup:
    def __init__(self, record) -> None:
        self.record = record

    def lookup_first(self, text: str):
        return self.record


class _FakeUserLexiconStore:
    def __init__(self, action: str = "inserted") -> None:
        self.entries: list[dict[str, str]] = []
        self.action = action
        self.deleted_phrases: list[str] = []
        self.delete_result = True
        self.import_calls: list[dict[str, object]] = []
        self.meta: dict[str, str] = {}
        self.has_data = False

    def upsert_phrase(self, phrase: str, numeric_pinyin: str, **kwargs) -> None:
        self.entries.append(
            {
                "phrase": phrase,
                "numeric_pinyin": numeric_pinyin,
                "marked_pinyin": kwargs.get("marked_pinyin", ""),
                "yime_code": kwargs.get("yime_code", ""),
                "source_note": kwargs.get("source_note", ""),
            }
        )
        return self.action

    def delete_phrase(self, phrase: str) -> bool:
        self.deleted_phrases.append(phrase)
        return self.delete_result

    def import_file(
        self,
        path: Path,
        *,
        replace_existing: bool = False,
        include_frequency: bool = True,
    ) -> dict[str, int]:
        self.import_calls.append(
            {
                "path": path,
                "replace_existing": replace_existing,
                "include_frequency": include_frequency,
            }
        )
        return {"phrase_entries": 2, "candidate_frequency": 1}

    def get_meta(self, key: str) -> str:
        return self.meta.get(key, "")

    def set_meta(self, key: str, value: str) -> None:
        self.meta[key] = value

    def has_user_data(self) -> bool:
        return self.has_data


class _ReloadableDecoder:
    def __init__(self) -> None:
        self.reload_calls = 0

    def reload_user_lexicon(self) -> None:
        self.reload_calls += 1


def test_add_current_input_to_user_lexicon_prompts_and_refreshes(monkeypatch) -> None:
    app = BaseInputMethodApp.__new__(BaseInputMethodApp)
    app.candidate_box = _FakeCandidateBox("日本")
    app.physical_input_map = {}
    app.runtime_reverse_lookup = _FakeReverseLookup(None)
    app.repo_root = Path(__file__).resolve().parents[2]
    app.user_lexicon_store = _FakeUserLexiconStore()
    app.decoder = _ReloadableDecoder()

    prompts = iter(["ri4 ben3", "rì běn"])
    monkeypatch.setattr(
        "yime.input_method.app_base.simpledialog.askstring",
        lambda *args, **kwargs: next(prompts),
    )
    monkeypatch.setattr(
        "yime.input_method.app_base.resolve_yime_code_from_numeric_pinyin",
        lambda repo_root, numeric_pinyin: "USERCODE",
    )

    refreshed: list[str] = []
    app._on_input_change = lambda event=None: refreshed.append("refreshed")
    info_calls: list[tuple[str, str]] = []
    monkeypatch.setattr(
        "yime.input_method.app_base.messagebox.showinfo",
        lambda title, message, parent=None: info_calls.append((title, message)),
    )

    BaseInputMethodApp._add_current_input_to_user_lexicon(app)

    assert app.user_lexicon_store.entries == [
        {
            "phrase": "日本",
            "numeric_pinyin": "ri4 ben3",
            "marked_pinyin": "rì běn",
            "yime_code": "USERCODE",
            "source_note": "ui_context_menu",
        }
    ]
    assert app.decoder.reload_calls == 1
    assert refreshed == ["refreshed"]
    assert app.candidate_box.statuses[0] == "已加入用户词库: 日本 | rì běn / ri4 ben3 | USERCODE"
    assert info_calls == [("加入用户词库", "已加入用户词库: 日本 | rì běn / ri4 ben3 | USERCODE")]


def test_add_current_input_to_user_lexicon_reports_update(monkeypatch) -> None:
    app = BaseInputMethodApp.__new__(BaseInputMethodApp)
    app.candidate_box = _FakeCandidateBox("日本")
    app.physical_input_map = {}
    app.runtime_reverse_lookup = _FakeReverseLookup(None)
    app.repo_root = Path(__file__).resolve().parents[2]
    app.user_lexicon_store = _FakeUserLexiconStore(action="updated")
    app.decoder = _ReloadableDecoder()

    prompts = iter(["ri4 ben3", "rì běn"])
    monkeypatch.setattr(
        "yime.input_method.app_base.simpledialog.askstring",
        lambda *args, **kwargs: next(prompts),
    )
    monkeypatch.setattr(
        "yime.input_method.app_base.resolve_yime_code_from_numeric_pinyin",
        lambda repo_root, numeric_pinyin: "USERCODE",
    )
    info_calls: list[tuple[str, str]] = []
    monkeypatch.setattr(
        "yime.input_method.app_base.messagebox.showinfo",
        lambda title, message, parent=None: info_calls.append((title, message)),
    )

    app._on_input_change = lambda event=None: None

    BaseInputMethodApp._add_current_input_to_user_lexicon(app)

    assert app.candidate_box.statuses[0] == "已更新用户词库: 日本 | rì běn / ri4 ben3 | USERCODE"
    assert info_calls == [("加入用户词库", "已更新用户词库: 日本 | rì běn / ri4 ben3 | USERCODE")]


def test_add_current_input_to_user_lexicon_allows_empty_marked_pinyin(monkeypatch) -> None:
    app = BaseInputMethodApp.__new__(BaseInputMethodApp)
    app.candidate_box = _FakeCandidateBox("他日")
    app.physical_input_map = {}
    app.runtime_reverse_lookup = _FakeReverseLookup(None)
    app.repo_root = Path(__file__).resolve().parents[2]
    app.user_lexicon_store = _FakeUserLexiconStore(action="inserted")
    app.decoder = _ReloadableDecoder()

    prompts = iter(["ta1 ri4", ""])
    monkeypatch.setattr(
        "yime.input_method.app_base.simpledialog.askstring",
        lambda *args, **kwargs: next(prompts),
    )
    monkeypatch.setattr(
        "yime.input_method.app_base.resolve_yime_code_from_numeric_pinyin",
        lambda repo_root, numeric_pinyin: "USERCODE",
    )

    refreshed: list[str] = []
    app._on_input_change = lambda event=None: refreshed.append("refreshed")
    info_calls: list[tuple[str, str]] = []
    monkeypatch.setattr(
        "yime.input_method.app_base.messagebox.showinfo",
        lambda title, message, parent=None: info_calls.append((title, message)),
    )

    BaseInputMethodApp._add_current_input_to_user_lexicon(app)

    assert app.user_lexicon_store.entries == [
        {
            "phrase": "他日",
            "numeric_pinyin": "ta1 ri4",
            "marked_pinyin": "",
            "yime_code": "USERCODE",
            "source_note": "ui_context_menu",
        }
    ]
    assert app.decoder.reload_calls == 1
    assert refreshed == ["refreshed"]
    assert app.candidate_box.statuses[0] == "已加入用户词库: 他日 | ta1 ri4 | USERCODE"
    assert info_calls == [("加入用户词库", "已加入用户词库: 他日 | ta1 ri4 | USERCODE")]


def test_add_current_input_to_user_lexicon_accepts_marked_pinyin_in_first_prompt(monkeypatch) -> None:
    app = BaseInputMethodApp.__new__(BaseInputMethodApp)
    app.candidate_box = _FakeCandidateBox("多日")
    app.physical_input_map = {}
    app.runtime_reverse_lookup = _FakeReverseLookup(None)
    app.repo_root = Path(__file__).resolve().parents[2]
    app.user_lexicon_store = _FakeUserLexiconStore(action="inserted")
    app.decoder = _ReloadableDecoder()

    prompts = iter(["duō rì", ""])
    monkeypatch.setattr(
        "yime.input_method.app_base.simpledialog.askstring",
        lambda *args, **kwargs: next(prompts),
    )

    refreshed: list[str] = []
    app._on_input_change = lambda event=None: refreshed.append("refreshed")
    info_calls: list[tuple[str, str]] = []
    monkeypatch.setattr(
        "yime.input_method.app_base.messagebox.showinfo",
        lambda title, message, parent=None: info_calls.append((title, message)),
    )

    BaseInputMethodApp._add_current_input_to_user_lexicon(app)

    assert app.user_lexicon_store.entries == [
        {
            "phrase": "多日",
            "numeric_pinyin": "duo1 ri4",
            "marked_pinyin": "duō rì",
            "yime_code": "",
            "source_note": "ui_context_menu",
        }
    ]
    assert app.decoder.reload_calls == 1
    assert refreshed == ["refreshed"]
    assert app.candidate_box.statuses[0] == "已加入用户词库: 多日 | duō rì / duo1 ri4 | "
    assert info_calls == [("加入用户词库", "已加入用户词库: 多日 | duō rì / duo1 ri4 | ")]


def test_add_current_input_to_user_lexicon_reports_invalid_first_prompt(monkeypatch) -> None:
    app = BaseInputMethodApp.__new__(BaseInputMethodApp)
    app.candidate_box = _FakeCandidateBox("多日")
    app.physical_input_map = {}
    app.runtime_reverse_lookup = _FakeReverseLookup(None)
    app.repo_root = Path(__file__).resolve().parents[2]
    app.user_lexicon_store = _FakeUserLexiconStore(action="inserted")
    app.decoder = _ReloadableDecoder()

    prompts = iter(["duori4"])
    monkeypatch.setattr(
        "yime.input_method.app_base.simpledialog.askstring",
        lambda *args, **kwargs: next(prompts),
    )
    error_calls: list[tuple[str, str]] = []
    monkeypatch.setattr(
        "yime.input_method.app_base.messagebox.showerror",
        lambda title, message, parent=None: error_calls.append((title, message)),
    )

    refreshed: list[str] = []
    app._on_input_change = lambda event=None: refreshed.append("refreshed")

    BaseInputMethodApp._add_current_input_to_user_lexicon(app)

    assert app.user_lexicon_store.entries == []
    assert app.decoder.reload_calls == 0
    assert refreshed == []
    assert app.candidate_box.statuses[0] == (
        "无法根据第一栏拼音推导音元编码。请在第一栏填写数字标调拼音，例如“duo1 ri4”；如果你输入的是“duō rì”，系统只会在能自动转换时接受。"
    )
    assert error_calls == [
        (
            "加入用户词库",
            "无法根据第一栏拼音推导音元编码。请在第一栏填写数字标调拼音，例如“duo1 ri4”；如果你输入的是“duō rì”，系统只会在能自动转换时接受。",
        )
    ]


def test_delete_current_input_from_user_lexicon_refreshes_and_reports(monkeypatch) -> None:
    app = BaseInputMethodApp.__new__(BaseInputMethodApp)
    app.candidate_box = _FakeCandidateBox("多日")
    app.physical_input_map = {}
    app.user_lexicon_store = _FakeUserLexiconStore()
    app.decoder = _ReloadableDecoder()

    monkeypatch.setattr(
        "yime.input_method.app_base.messagebox.askyesno",
        lambda title, message, parent=None: True,
    )
    info_calls: list[tuple[str, str]] = []
    monkeypatch.setattr(
        "yime.input_method.app_base.messagebox.showinfo",
        lambda title, message, parent=None: info_calls.append((title, message)),
    )

    refreshed: list[str] = []
    app._on_input_change = lambda event=None: refreshed.append("refreshed")

    BaseInputMethodApp._delete_current_input_from_user_lexicon(app)

    assert app.user_lexicon_store.deleted_phrases == ["多日"]
    assert app.decoder.reload_calls == 1
    assert refreshed == ["refreshed"]
    assert app.candidate_box.statuses[0] == "已从用户词库中删除: 多日"
    assert info_calls == [("从用户词库中删除", "已从用户词库中删除: 多日")]


def test_delete_current_input_from_user_lexicon_reports_missing(monkeypatch) -> None:
    app = BaseInputMethodApp.__new__(BaseInputMethodApp)
    app.candidate_box = _FakeCandidateBox("多日")
    app.physical_input_map = {}
    app.user_lexicon_store = _FakeUserLexiconStore()
    app.user_lexicon_store.delete_result = False
    app.decoder = _ReloadableDecoder()

    monkeypatch.setattr(
        "yime.input_method.app_base.messagebox.askyesno",
        lambda title, message, parent=None: True,
    )
    warning_calls: list[tuple[str, str]] = []
    monkeypatch.setattr(
        "yime.input_method.app_base.messagebox.showwarning",
        lambda title, message, parent=None: warning_calls.append((title, message)),
    )

    refreshed: list[str] = []
    app._on_input_change = lambda event=None: refreshed.append("refreshed")

    BaseInputMethodApp._delete_current_input_from_user_lexicon(app)

    assert app.user_lexicon_store.deleted_phrases == ["多日"]
    assert app.decoder.reload_calls == 0
    assert refreshed == []
    assert app.candidate_box.statuses[0] == "用户词库中未找到：多日"
    assert warning_calls == [("从用户词库中删除", "用户词库中未找到：多日")]


def test_maybe_import_seed_user_lexicon_imports_for_empty_store(tmp_path) -> None:
    app = BaseInputMethodApp.__new__(BaseInputMethodApp)
    app.user_lexicon_store = _FakeUserLexiconStore()
    app.user_lexicon_seed_path = tmp_path / "user_lexicon_seed.json"
    app.user_lexicon_seed_path.write_text("{}\n", encoding="utf-8")

    result = BaseInputMethodApp._maybe_import_seed_user_lexicon(app)

    assert result == {"phrase_entries": 2, "candidate_frequency": 1}
    assert app.user_lexicon_store.import_calls == [
        {
            "path": app.user_lexicon_seed_path,
            "replace_existing": False,
            "include_frequency": True,
        }
    ]
    assert app.user_lexicon_store.get_meta("seed_import_completed").startswith("imported:")


def test_maybe_import_seed_user_lexicon_skips_when_existing_user_data_present(tmp_path) -> None:
    app = BaseInputMethodApp.__new__(BaseInputMethodApp)
    app.user_lexicon_store = _FakeUserLexiconStore()
    app.user_lexicon_store.has_data = True
    app.user_lexicon_seed_path = tmp_path / "user_lexicon_seed.json"
    app.user_lexicon_seed_path.write_text("{}\n", encoding="utf-8")

    result = BaseInputMethodApp._maybe_import_seed_user_lexicon(app)

    assert result == {"phrase_entries": 0, "candidate_frequency": 0}
    assert app.user_lexicon_store.import_calls == []
    assert app.user_lexicon_store.get_meta("seed_import_completed") == "skipped_existing_user_data"
