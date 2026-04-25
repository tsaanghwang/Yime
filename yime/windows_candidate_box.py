from __future__ import annotations

import argparse
import ctypes
from ctypes import wintypes
import json
from pathlib import Path
import tkinter as tk
from tkinter import ttk
import unicodedata


user32 = ctypes.WinDLL("user32", use_last_error=True)

SW_RESTORE = 9
VK_CONTROL = 0x11
VK_V = 0x56
VK_C = 0x43
VK_SHIFT = 0x10
VK_LEFT = 0x25
VK_BACK = 0x08
KEYEVENTF_KEYUP = 0x0002


def get_foreground_window() -> int | None:
    hwnd = user32.GetForegroundWindow()
    return int(hwnd) if hwnd else None


def restore_window(hwnd: int) -> None:
    user32.ShowWindow(wintypes.HWND(hwnd), SW_RESTORE)
    user32.SetForegroundWindow(wintypes.HWND(hwnd))


def send_ctrl_v() -> None:
    user32.keybd_event(VK_CONTROL, 0, 0, 0)
    user32.keybd_event(VK_V, 0, 0, 0)
    user32.keybd_event(VK_V, 0, KEYEVENTF_KEYUP, 0)
    user32.keybd_event(VK_CONTROL, 0, KEYEVENTF_KEYUP, 0)


def send_ctrl_c() -> None:
    user32.keybd_event(VK_CONTROL, 0, 0, 0)
    user32.keybd_event(VK_C, 0, 0, 0)
    user32.keybd_event(VK_C, 0, KEYEVENTF_KEYUP, 0)
    user32.keybd_event(VK_CONTROL, 0, KEYEVENTF_KEYUP, 0)


def send_shift_left(count: int) -> None:
    for _ in range(count):
        user32.keybd_event(VK_SHIFT, 0, 0, 0)
        user32.keybd_event(VK_LEFT, 0, 0, 0)
        user32.keybd_event(VK_LEFT, 0, KEYEVENTF_KEYUP, 0)
        user32.keybd_event(VK_SHIFT, 0, KEYEVENTF_KEYUP, 0)


def send_backspace(count: int) -> None:
    for _ in range(count):
        user32.keybd_event(VK_BACK, 0, 0, 0)
        user32.keybd_event(VK_BACK, 0, KEYEVENTF_KEYUP, 0)


class StaticCandidateDecoder:
    def __init__(self, app_dir: Path) -> None:
        repo_root = app_dir.parent
        projection_path = repo_root / "internal_data" / "bmp_pua_trial_projection.json"
        key_to_symbol_path = repo_root / "internal_data" / "key_to_symbol.json"
        mapping_path = app_dir / "enhanced_yinjie_mapping.json"
        pinyin_hanzi_paths = [
            app_dir / "pinyin_hanzi.json",
            repo_root / "pinyin" / "hanzi_pinyin" / "pinyin_hanzi.json",
        ]

        self.bmp_to_canonical = self._build_bmp_to_canonical_map(projection_path, key_to_symbol_path)
        self.code_mapping = self._load_json(mapping_path)["音元符号"]
        self.pinyin_hanzi = self._load_first_available_json(pinyin_hanzi_paths)

    def _load_json(self, path: Path) -> dict:
        with path.open("r", encoding="utf-8") as handle:
            return json.load(handle)

    def _load_first_available_json(self, paths: list[Path]) -> dict:
        for path in paths:
            if path.exists():
                return self._load_json(path)
        joined = ", ".join(str(path) for path in paths)
        raise FileNotFoundError(f"未找到候选数据文件: {joined}")

    def _build_bmp_to_canonical_map(self, projection_path: Path, key_to_symbol_path: Path) -> dict[str, str]:
        projection = self._load_json(projection_path)
        key_to_symbol = self._load_json(key_to_symbol_path)
        bmp_to_canonical: dict[str, str] = {}

        for symbol_key, slot_info in projection["used_mapping"].items():
            bmp_char = slot_info["char"]
            canonical_char = key_to_symbol.get(symbol_key)
            if canonical_char:
                bmp_to_canonical[bmp_char] = canonical_char

        return bmp_to_canonical

    def decode_text(self, text: str) -> tuple[str, str, str, list[str], str]:
        canonical = "".join(self.bmp_to_canonical.get(char, char) for char in text)
        if not canonical:
            return "", "", "", [], "请输入一个完整音节的 4 个码元。"

        if len(canonical) < 4:
            return canonical, canonical, "", [], f"当前 {len(canonical)}/4 码，继续输入。"

        active_code = canonical[-4:]
        mode_hint = ""
        if len(canonical) > 4:
            mode_hint = f"已自动截取最近 4 码，总输入 {len(canonical)} 码。"

        mapping = self.code_mapping.get(active_code)
        if not mapping:
            status = mode_hint or "未找到该 4 码对应的拼音映射。"
            if mode_hint:
                status = f"{mode_hint} 当前 4 码未找到拼音映射。"
            return canonical, active_code, "", [], status

        numeric_pinyin = mapping.get("数字标调", "")
        marked_pinyin = unicodedata.normalize("NFC", mapping.get("调号标调", ""))
        display_pinyin = marked_pinyin or numeric_pinyin
        candidates = self._lookup_candidates(numeric_pinyin, marked_pinyin)
        if candidates:
            status = f"找到 {len(candidates)} 个候选。"
            if mode_hint:
                status = f"{mode_hint} {status}"
            return canonical, active_code, display_pinyin, candidates, status

        status = "已解码出拼音，但当前候选表里没有对应汉字。"
        if mode_hint:
            status = f"{mode_hint} {status}"
        return canonical, active_code, display_pinyin, [], status

    def _lookup_candidates(self, numeric_pinyin: str, marked_pinyin: str) -> list[str]:
        candidate_keys: list[str] = []
        if marked_pinyin:
            candidate_keys.append(marked_pinyin)
        if numeric_pinyin:
            candidate_keys.append(numeric_pinyin)
            candidate_keys.append(numeric_pinyin[:-1])

        merged: list[str] = []
        seen: set[str] = set()
        for key in candidate_keys:
            for hanzi in self.pinyin_hanzi.get(key, []):
                if hanzi not in seen:
                    seen.add(hanzi)
                    merged.append(hanzi)

        return merged


class RuntimeCandidateDecoder:
    def __init__(self, app_dir: Path) -> None:
        self.runtime_path = app_dir / "reports" / "runtime_candidates_by_code_true.json"
        self.bmp_to_canonical = self._build_bmp_to_canonical_map(
            app_dir.parent / "internal_data" / "bmp_pua_trial_projection.json",
            app_dir.parent / "internal_data" / "key_to_symbol.json",
        )
        self.by_code = self._load_runtime_candidates(self.runtime_path)

    def _load_json(self, path: Path) -> dict:
        with path.open("r", encoding="utf-8") as handle:
            return json.load(handle)

    def _build_bmp_to_canonical_map(self, projection_path: Path, key_to_symbol_path: Path) -> dict[str, str]:
        projection = self._load_json(projection_path)
        key_to_symbol = self._load_json(key_to_symbol_path)
        bmp_to_canonical: dict[str, str] = {}

        for symbol_key, slot_info in projection["used_mapping"].items():
            bmp_char = slot_info["char"]
            canonical_char = key_to_symbol.get(symbol_key)
            if canonical_char:
                bmp_to_canonical[bmp_char] = canonical_char

        return bmp_to_canonical

    def _load_runtime_candidates(self, path: Path) -> dict[str, list[dict[str, object]]]:
        if not path.exists():
            raise FileNotFoundError(f"未找到运行时候选文件: {path}")
        payload = self._load_json(path)
        by_code = payload.get("by_code")
        if not isinstance(by_code, dict):
            raise ValueError(f"运行时候选文件格式无效: {path}")
        return by_code

    def decode_text(self, text: str) -> tuple[str, str, str, list[str], str]:
        canonical = "".join(self.bmp_to_canonical.get(char, char) for char in text)
        if not canonical:
            return "", "", "", [], "请输入一个完整音节的 4 个码元。"

        if len(canonical) < 4:
            return canonical, canonical, "", [], f"当前 {len(canonical)}/4 码，继续输入。"

        active_code = canonical[-4:]
        mode_hint = ""
        if len(canonical) > 4:
            mode_hint = f"已自动截取最近 4 码，总输入 {len(canonical)} 码。"

        raw_candidates = self.by_code.get(active_code, [])
        texts: list[str] = []
        seen: set[str] = set()
        pinyin_values: list[str] = []
        for candidate in raw_candidates:
            candidate_text = str(candidate.get("text", "")).strip()
            if not candidate_text or candidate_text in seen:
                continue
            seen.add(candidate_text)
            texts.append(candidate_text)
            pinyin_value = str(candidate.get("pinyin_tone", "")).strip()
            if pinyin_value and pinyin_value not in pinyin_values:
                pinyin_values.append(pinyin_value)

        display_pinyin = " / ".join(pinyin_values[:3])
        if texts:
            status = f"从运行时编码表找到 {len(texts)} 个候选。"
            if mode_hint:
                status = f"{mode_hint} {status}"
            return canonical, active_code, display_pinyin, texts, status

        status = "运行时编码表中未找到该 4 码候选。"
        if mode_hint:
            status = f"{mode_hint} {status}"
        return canonical, active_code, display_pinyin, [], status


class CompositeCandidateDecoder:
    def __init__(self, app_dir: Path) -> None:
        self.runtime_decoder: RuntimeCandidateDecoder | None = None
        self.runtime_load_error = ""
        try:
            self.runtime_decoder = RuntimeCandidateDecoder(app_dir)
        except (FileNotFoundError, ValueError, KeyError, json.JSONDecodeError) as exc:
            self.runtime_load_error = str(exc)
        self.static_decoder = StaticCandidateDecoder(app_dir)

    def decode_text(self, text: str) -> tuple[str, str, str, list[str], str]:
        if self.runtime_decoder is not None:
            canonical, active_code, pinyin, candidates, status = self.runtime_decoder.decode_text(text)
            if candidates:
                return canonical, active_code, pinyin, candidates, status
            if active_code:
                fallback = self.static_decoder.decode_text(text)
                if fallback[3]:
                    return fallback[0], fallback[1], fallback[2], fallback[3], f"{status} 已回退到静态拼音候选表。"
                return canonical, active_code, pinyin, candidates, status

        fallback = self.static_decoder.decode_text(text)
        if self.runtime_load_error:
            fallback_status = fallback[4]
            if fallback_status:
                fallback_status = f"{fallback_status} 运行时编码表未启用: {self.runtime_load_error}"
            else:
                fallback_status = f"运行时编码表未启用: {self.runtime_load_error}"
            return fallback[0], fallback[1], fallback[2], fallback[3], fallback_status
        return fallback


class CandidateBoxApp:
    def __init__(self, auto_paste: bool = True, font_family: str = "Noto Sans") -> None:
        self.auto_paste = auto_paste
        self.font_family = font_family
        self.decoder = CompositeCandidateDecoder(Path(__file__).resolve().parent)
        self.root = tk.Tk()
        self.root.title("音元候选框")
        self.root.geometry("640x280")
        self.root.attributes("-topmost", True)

        self.own_hwnd = self.root.winfo_id()
        self.last_external_hwnd = get_foreground_window()
        self.current_candidates: list[str] = []
        self.last_clipboard_text = ""
        self.last_replace_length = 0

        self._build_ui()
        self._bind_keys()
        self._poll_foreground_window()
        self.root.protocol("WM_DELETE_WINDOW", self._close)

    def _build_ui(self) -> None:
        frame = ttk.Frame(self.root, padding=12)
        frame.pack(fill=tk.BOTH, expand=True)

        ttk.Label(frame, text="输入音元码元").pack(anchor=tk.W)

        self.input_var = tk.StringVar()
        self.input_entry = ttk.Entry(frame, textvariable=self.input_var, font=(self.font_family, 14))
        self.input_entry.pack(fill=tk.X, pady=(4, 8))
        self.input_entry.focus_set()
        self.input_entry.bind("<KeyRelease>", self._on_input_change)

        self.pinyin_var = tk.StringVar(value="")
        ttk.Label(frame, textvariable=self.pinyin_var, foreground="#0b57d0").pack(anchor=tk.W)

        self.code_var = tk.StringVar(value="")
        ttk.Label(frame, textvariable=self.code_var, foreground="#666666").pack(anchor=tk.W, pady=(4, 0))

        ttk.Label(frame, text="候选汉字").pack(anchor=tk.W, pady=(10, 4))
        self.candidate_frame = ttk.Frame(frame)
        self.candidate_frame.pack(fill=tk.X)

        self.status_var = tk.StringVar(value="连续输入时自动取最近 4 码。请先复制编码，再点“读取剪贴板”。")
        ttk.Label(frame, textvariable=self.status_var, foreground="#666666").pack(anchor=tk.W, pady=(12, 0))

        button_row = ttk.Frame(frame)
        button_row.pack(fill=tk.X, pady=(12, 0))

        ttk.Button(button_row, text="读取剪贴板", command=self._decode_from_clipboard).pack(side=tk.LEFT, padx=8)
        ttk.Button(button_row, text="复制首选", command=self._copy_first_candidate).pack(side=tk.LEFT)
        ttk.Button(button_row, text="粘贴首选", command=self._paste_first_candidate).pack(side=tk.LEFT, padx=8)
        ttk.Button(button_row, text="清空", command=self._clear_input).pack(side=tk.LEFT)
        ttk.Button(button_row, text="退出", command=self._close).pack(side=tk.LEFT, padx=8)

    def _bind_keys(self) -> None:
        for index in range(1, 10):
            self.root.bind(str(index), lambda event, value=index: self._select_candidate_by_index(value - 1))
        self.root.bind("<Return>", lambda event: self._select_candidate_by_index(0))
        self.root.bind("<Escape>", lambda event: self._clear_input())
        self.root.bind("<Control-q>", lambda event: self._close())

    def _poll_foreground_window(self) -> None:
        foreground = get_foreground_window()
        if foreground and foreground != self.own_hwnd:
            self.last_external_hwnd = foreground
        self.root.after(250, self._poll_foreground_window)

    def _on_input_change(self, event: tk.Event | None = None) -> None:
        input_text = self.input_var.get()
        if not input_text:
            self.pinyin_var.set("")
            self.code_var.set("")
            self.current_candidates = []
            self.status_var.set("连续输入时自动取最近 4 码。请先复制编码，再点“读取剪贴板”。")
            self._render_candidates()
            return

        canonical_code, active_code, pinyin, candidates, status = self.decoder.decode_text(input_text)
        self.last_replace_length = min(4, len(input_text))
        self.pinyin_var.set(f"拼音: {pinyin}" if pinyin else "")
        if active_code and canonical_code and active_code != canonical_code:
            self.code_var.set(f"当前解码 4 码: {active_code} | 累计输入: {len(canonical_code)} 码")
        else:
            self.code_var.set(f"当前解码 4 码: {active_code}" if active_code else "")
        self.current_candidates = candidates[:9]
        self.status_var.set(status)
        self._render_candidates()

    def _render_candidates(self) -> None:
        for child in self.candidate_frame.winfo_children():
            child.destroy()

        if not self.current_candidates:
            ttk.Label(self.candidate_frame, text="无候选").pack(anchor=tk.W)
            return

        for index, hanzi in enumerate(self.current_candidates, start=1):
            button = ttk.Button(
                self.candidate_frame,
                text=f"{index}.{hanzi}",
                command=lambda value=index - 1: self._select_candidate_by_index(value),
                width=6,
            )
            button.pack(side=tk.LEFT, padx=(0, 6))

    def _clear_input(self) -> None:
        self.input_var.set("")
        self.pinyin_var.set("")
        self.code_var.set("")
        self.current_candidates = []
        self.last_replace_length = 0
        self.status_var.set("连续输入时自动取最近 4 码。请先复制编码，再点“读取剪贴板”。")
        self._render_candidates()
        self.input_entry.focus_set()

    def _decode_from_clipboard(self) -> None:
        try:
            captured = self.root.clipboard_get()
        except tk.TclError:
            self.status_var.set("剪贴板没有可读取文本。")
            return

        if not captured:
            self.status_var.set("剪贴板为空。")
            return

        self.input_var.set(captured)
        self.input_entry.focus_set()
        self._on_input_change()

    def _copy_first_candidate(self) -> None:
        self._copy_candidate(0)

    def _paste_first_candidate(self) -> None:
        self._select_candidate_by_index(0)

    def _select_candidate_by_index(self, index: int) -> None:
        if index < 0 or index >= len(self.current_candidates):
            return
        hanzi = self.current_candidates[index]
        self._copy_text(hanzi)
        self.status_var.set(f"已复制: {hanzi}")
        if self.auto_paste and self.last_external_hwnd and self.last_external_hwnd != self.own_hwnd:
            self.root.after(50, lambda: self._paste_to_previous_window(hanzi))
        self._clear_input()

    def _copy_candidate(self, index: int) -> None:
        if index < 0 or index >= len(self.current_candidates):
            return
        hanzi = self.current_candidates[index]
        self._copy_text(hanzi)
        self.status_var.set(f"已复制: {hanzi}")

    def _copy_text(self, text: str) -> None:
        self.root.clipboard_clear()
        self.root.clipboard_append(text)
        self.root.update()

    def _paste_to_previous_window(self, hanzi: str) -> None:
        if not self.last_external_hwnd:
            self.status_var.set(f"已复制: {hanzi}，未找到上一个窗口")
            return
        restore_window(self.last_external_hwnd)
        if self.last_replace_length > 0:
            self.root.after(80, lambda: send_backspace(self.last_replace_length))
            self.root.after(170, send_ctrl_v)
            self.root.after(280, lambda: self.status_var.set(f"已替换前一个窗口中的 {self.last_replace_length} 个编码字符: {hanzi}"))
            return
        self.root.after(80, send_ctrl_v)
        self.root.after(180, lambda: self.status_var.set(f"已回贴到前一个窗口: {hanzi}"))

    def run(self) -> None:
        self._render_candidates()
        self.root.mainloop()

    def _close(self) -> None:
        self.root.destroy()


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="音元输入法 Windows 候选框测试壳")
    parser.add_argument(
        "--copy-only",
        action="store_true",
        help="只复制候选字到剪贴板，不自动回贴到上一个窗口。",
    )
    parser.add_argument(
        "--font-family",
        default="YinYuan Regular",
        help="输入框字体名。默认: YinYuan Regular",
    )
    return parser.parse_args()


def main() -> None:
    if ctypes.sizeof(ctypes.c_void_p) == 0:
        raise SystemExit("Windows API 初始化失败")
    args = parse_args()
    app = CandidateBoxApp(auto_paste=not args.copy_only, font_family=args.font_family)
    app.run()


if __name__ == "__main__":
    main()
