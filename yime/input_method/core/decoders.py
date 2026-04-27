"""
候选词解码器模块

提供三种解码器：
1. StaticCandidateDecoder - 静态拼音候选表解码
2. RuntimeCandidateDecoder - 运行时编码表解码
3. CompositeCandidateDecoder - 组合解码器（优先运行时，回退静态）
"""

from __future__ import annotations

from dataclasses import dataclass
import json
import sqlite3
from pathlib import Path
import unicodedata
from typing import Dict, List, Tuple, Optional

from .char_code_index import CharCodeCandidate, CharCodeIndex


def format_codepoints(text: str) -> str:
    if not text:
        return ""
    return " ".join(
        f"U+{ord(char):06X}" if ord(char) > 0xFFFF else f"U+{ord(char):04X}"
        for char in text
    )


def _as_float_value(value: object) -> float:
    try:
        return float(value)
    except (TypeError, ValueError):
        return 0.0


def _as_bool_value(value: object) -> bool:
    if isinstance(value, bool):
        return value
    if isinstance(value, (int, float)):
        return bool(value)
    if isinstance(value, str):
        return value.strip().lower() in {"1", "true", "yes", "on"}
    return False


@dataclass(frozen=True)
class RuntimeCandidateRecord:
    """Normalized runtime candidate used for phrase-aware ranking."""

    lookup_code: str
    text: str
    entry_type: str
    pinyin_tone: str = ""
    sort_weight: float = 0.0
    text_length: int = 0
    is_common: bool = False


@dataclass(frozen=True)
class RuntimeLookupPlan:
    """Resolved runtime lookup target for the current input buffer."""

    lookup_code: str
    active_code: str
    syllable_count: int
    trailing_code_count: int
    truncated_to_recent: bool
    phrase_mode: bool


def _canonicalize_runtime_input(text: str, bmp_to_canonical: Dict[str, str]) -> str:
    return "".join(bmp_to_canonical.get(char, char) for char in text)


def _split_complete_syllables(canonical: str) -> List[str]:
    complete_length = (len(canonical) // 4) * 4
    return [canonical[index:index + 4] for index in range(0, complete_length, 4)]


def _build_runtime_lookup_plan(canonical: str) -> RuntimeLookupPlan:
    syllables = _split_complete_syllables(canonical)
    trailing_code_count = len(canonical) % 4
    if not syllables:
        return RuntimeLookupPlan(
            lookup_code="",
            active_code=canonical,
            syllable_count=0,
            trailing_code_count=trailing_code_count,
            truncated_to_recent=False,
            phrase_mode=False,
        )

    recent_syllables = syllables[-4:]
    truncated_to_recent = len(syllables) > len(recent_syllables)
    phrase_mode = trailing_code_count == 0 and len(recent_syllables) >= 2
    if phrase_mode:
        return RuntimeLookupPlan(
            lookup_code=" ".join(recent_syllables),
            active_code="".join(recent_syllables),
            syllable_count=len(recent_syllables),
            trailing_code_count=0,
            truncated_to_recent=truncated_to_recent,
            phrase_mode=True,
        )

    return RuntimeLookupPlan(
        lookup_code=recent_syllables[-1],
        active_code=recent_syllables[-1],
        syllable_count=1,
        trailing_code_count=trailing_code_count,
        truncated_to_recent=truncated_to_recent,
        phrase_mode=False,
    )


def _build_runtime_mode_hint(canonical: str, plan: RuntimeLookupPlan) -> str:
    if plan.trailing_code_count and canonical:
        completed = len(_split_complete_syllables(canonical))
        if completed:
            return (
                f"已完成 {completed} 个音节，当前第 {completed + 1} 个音节"
                f"输入到 {plan.trailing_code_count}/4 码。"
            )
        return f"当前 {plan.trailing_code_count}/4 码，继续输入。"

    if plan.phrase_mode:
        if plan.truncated_to_recent:
            return f"已自动截取最近 {plan.syllable_count} 个完整音节进行词语查找。"
        return f"按 {plan.syllable_count} 个完整音节进行词语查找。"

    if len(canonical) > 4:
        return f"已自动截取最近 4 码，总输入 {len(canonical)} 码。"

    return ""


def _runtime_candidate_priority(candidate: RuntimeCandidateRecord) -> int:
    if candidate.entry_type == "phrase" and 2 <= candidate.text_length <= 4:
        return 0
    if candidate.entry_type == "char":
        return 1
    return 2


def _runtime_candidate_sort_key(
    candidate: RuntimeCandidateRecord,
    user_freq: int,
) -> tuple[int, float, int, str, str]:
    return (
        _runtime_candidate_priority(candidate),
        -candidate.sort_weight,
        -user_freq,
        candidate.text,
        candidate.pinyin_tone,
    )


def build_code_display(raw_text: str, canonical_code: str, active_code: str) -> str:
    if not active_code:
        return ""

    active_display = format_codepoints(active_code)
    if len(active_code) > 4 and len(active_code) % 4 == 0:
        active_label = f"当前{len(active_code) // 4}音节码"
    else:
        active_label = "当前4码"

    if not canonical_code:
        return active_display

    if raw_text and raw_text != canonical_code:
        return (
            f"{active_label} {active_display} | 输入 {format_codepoints(raw_text)}"
            f" | 规范化后共 {len(canonical_code)} 码"
        )

    if active_code != canonical_code:
        return f"{active_label} {active_display} | 累计输入 {len(canonical_code)} 码"

    return active_display


def _load_visual_json(path: Path) -> dict:
    with path.open("r", encoding="utf-8") as handle:
        return json.load(handle)


def build_input_visual_map(repo_root: Path) -> Dict[str, str]:
    projection = _load_visual_json(
        repo_root / "internal_data" / "bmp_pua_trial_projection.json"
    )
    key_to_symbol = _load_visual_json(repo_root / "internal_data" / "key_to_symbol.json")
    shouyin_payload = _load_visual_json(
        repo_root / "syllable" / "analysis" / "slice" / "yinyuan" / "shouyin_codepoint.json"
    )
    yinyuan_payload = _load_visual_json(
        repo_root / "syllable" / "analysis" / "slice" / "yinyuan" / "yinyuan_codepoint.json"
    )

    label_by_bmp: Dict[str, str] = {}
    for label, char in shouyin_payload.get("首音", {}).items():
        label_by_bmp[str(char)] = str(label)
    for namespace in ("zaoyin", "yueyin"):
        for label, char in yinyuan_payload.get(namespace, {}).items():
            label_by_bmp[str(char)] = str(label)

    visual_map: Dict[str, str] = {}
    for slot_key, slot_info in projection.get("used_mapping", {}).items():
        bmp_char = str(slot_info.get("char", ""))
        canonical_char = str(key_to_symbol.get(slot_key, ""))
        label = label_by_bmp.get(bmp_char) or slot_key
        token = f"[{slot_key} {label}]"
        if bmp_char:
            visual_map[bmp_char] = token
        if canonical_char:
            visual_map[canonical_char] = token

    for reserved in projection.get("reserved_slots", []):
        bmp_char = str(reserved.get("char", ""))
        slot_key = str(reserved.get("label") or "reserved").split("_", 1)[0]
        if bmp_char:
            visual_map[bmp_char] = f"[{slot_key}]"

    return visual_map


def build_input_outline(text: str, visual_map: Dict[str, str]) -> str:
    if not text:
        return ""

    tokens: List[str] = []
    for char in text:
        token = visual_map.get(char)
        if token:
            tokens.append(token)
            continue

        codepoint = ord(char)
        fallback = f"U+{codepoint:06X}" if codepoint > 0xFFFF else f"U+{codepoint:04X}"
        tokens.append(f"[{fallback}]")

    return " ".join(tokens)


def _strip_slot_from_visual_token(token: str) -> str:
    body = token.strip()
    if body.startswith("[") and body.endswith("]"):
        body = body[1:-1].strip()

    slot, separator, label = body.partition(" ")
    if (
        separator
        and len(slot) == 3
        and slot[0] in {"N", "M"}
        and slot[1:].isdigit()
    ):
        return label.strip()
    if len(body) == 3 and body[0] in {"N", "M"} and body[1:].isdigit():
        return ""
    return body


def build_input_sound_notes(text: str, visual_map: Dict[str, str]) -> str:
    if not text:
        return ""

    notes: List[str] = []
    for char in text:
        token = visual_map.get(char)
        if token:
            notes.append(_strip_slot_from_visual_token(token))
            continue

        codepoint = ord(char)
        notes.append(f"U+{codepoint:06X}" if codepoint > 0xFFFF else f"U+{codepoint:04X}")

    return "".join(note for note in notes if note)


def build_physical_input_map(repo_root: Path) -> Dict[str, str]:
    manual_layout = _load_visual_json(repo_root / "internal_data" / "manual_key_layout.json")
    slot_to_bmp = _load_visual_json(repo_root / "key_to_code.json")

    physical_map: Dict[str, str] = {}
    for row in manual_layout.get("layers", []):
        if row.get("output_layer") != "base":
            continue
        physical_key = str(row.get("physical_key", ""))
        symbol_key = row.get("symbol_key")
        if not physical_key or not symbol_key:
            continue
        bmp_char = slot_to_bmp.get(str(symbol_key))
        if bmp_char:
            physical_map[physical_key] = str(bmp_char)

    return physical_map


def project_physical_input(text: str, physical_map: Dict[str, str]) -> str:
    if not text:
        return ""

    projected_chars: List[str] = []
    for char in text:
        projected_chars.append(physical_map.get(char, char))
    return "".join(projected_chars)


def build_projected_to_physical_map(
    physical_map: Dict[str, str]
) -> Dict[str, str]:
    return {projected: physical for physical, projected in physical_map.items()}


def unproject_physical_input(
    text: str, projected_to_physical_map: Dict[str, str]
) -> str:
    if not text:
        return ""

    physical_chars: List[str] = []
    for char in text:
        physical_chars.append(projected_to_physical_map.get(char, char))
    return "".join(physical_chars)


class StaticCandidateDecoder:
    """静态候选词解码器（基于拼音候选表）"""

    def __init__(self, app_dir: Path) -> None:
        """
        初始化静态解码器

        Args:
            app_dir: 应用目录路径
        """
        repo_root = app_dir.parent
        projection_path = repo_root / "internal_data" / "bmp_pua_trial_projection.json"
        key_to_symbol_path = repo_root / "internal_data" / "key_to_symbol.json"
        mapping_path = app_dir / "enhanced_yinjie_mapping.json"
        pinyin_hanzi_paths = [
            app_dir / "pinyin_hanzi.json",
            repo_root / "pinyin" / "hanzi_pinyin" / "pinyin_hanzi.json",
        ]

        self.bmp_to_canonical = self._build_bmp_to_canonical_map(
            projection_path, key_to_symbol_path
        )
        self.code_mapping = self._load_json(mapping_path)["音元符号"]
        self.pinyin_hanzi = self._load_first_available_json(pinyin_hanzi_paths)

    def _load_json(self, path: Path) -> dict:
        """加载JSON文件"""
        with path.open("r", encoding="utf-8") as handle:
            return json.load(handle)

    def _load_first_available_json(self, paths: List[Path]) -> dict:
        """加载第一个可用的JSON文件"""
        for path in paths:
            if path.exists():
                return self._load_json(path)
        joined = ", ".join(str(path) for path in paths)
        raise FileNotFoundError(f"未找到候选数据文件: {joined}")

    def _build_bmp_to_canonical_map(
        self, projection_path: Path, key_to_symbol_path: Path
    ) -> Dict[str, str]:
        """构建BMP字符到规范字符的映射"""
        projection = self._load_json(projection_path)
        key_to_symbol = self._load_json(key_to_symbol_path)
        bmp_to_canonical: Dict[str, str] = {}

        for symbol_key, slot_info in projection["used_mapping"].items():
            bmp_char = slot_info["char"]
            canonical_char = key_to_symbol.get(symbol_key)
            if canonical_char:
                bmp_to_canonical[bmp_char] = canonical_char

        return bmp_to_canonical

    def decode_text(
        self, text: str
    ) -> Tuple[str, str, str, List[str], str]:
        """
        解码文本

        Args:
            text: 输入的音元码元文本

        Returns:
            (规范编码, 当前4码, 拼音显示, 候选词列表, 状态消息)
        """
        canonical = "".join(
            self.bmp_to_canonical.get(char, char) for char in text
        )
        if not canonical:
            return "", "", "", [], "请输入一个完整音节的 4 个码元。"

        if len(canonical) < 4:
            return (
                canonical,
                canonical,
                "",
                [],
                f"当前 {len(canonical)}/4 码，继续输入。",
            )

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

    def _lookup_candidates(
        self, numeric_pinyin: str, marked_pinyin: str
    ) -> List[str]:
        """查找候选词"""
        candidate_keys: List[str] = []
        if marked_pinyin:
            candidate_keys.append(marked_pinyin)
        if numeric_pinyin:
            candidate_keys.append(numeric_pinyin)
            candidate_keys.append(numeric_pinyin[:-1])

        merged: List[str] = []
        seen: set = set()
        for key in candidate_keys:
            for hanzi in self.pinyin_hanzi.get(key, []):
                if hanzi not in seen:
                    seen.add(hanzi)
                    merged.append(hanzi)

        return merged


class RuntimeCandidateDecoder:
    """运行时候选词解码器（基于运行时编码表）"""

    def __init__(self, app_dir: Path) -> None:
        """
        初始化运行时解码器

        Args:
            app_dir: 应用目录路径
        """
        self.runtime_path = (
            app_dir / "reports" / "runtime_candidates_by_code_true.json"
        )
        self.bmp_to_canonical = self._build_bmp_to_canonical_map(
            app_dir.parent / "internal_data" / "bmp_pua_trial_projection.json",
            app_dir.parent / "internal_data" / "key_to_symbol.json",
        )
        self.by_code = self._load_runtime_candidates(self.runtime_path)
        self.char_code_index = CharCodeIndex.from_runtime_candidates(self.by_code)
        self._user_freq_by_candidate: dict[tuple[str, str], int] = {}

    def _load_json(self, path: Path) -> dict:
        """加载JSON文件"""
        raw_text = path.read_text(encoding="utf-8")
        stripped = raw_text.lstrip()
        if stripped.startswith("version https://git-lfs.github.com/spec/v1"):
            raise ValueError(f"运行时候选文件是 Git LFS 指针，未拉取实际内容: {path}")
        return json.loads(raw_text)

    def _build_bmp_to_canonical_map(
        self, projection_path: Path, key_to_symbol_path: Path
    ) -> Dict[str, str]:
        """构建BMP字符到规范字符的映射"""
        projection = self._load_json(projection_path)
        key_to_symbol = self._load_json(key_to_symbol_path)
        bmp_to_canonical: Dict[str, str] = {}

        for symbol_key, slot_info in projection["used_mapping"].items():
            bmp_char = slot_info["char"]
            canonical_char = key_to_symbol.get(symbol_key)
            if canonical_char:
                bmp_to_canonical[bmp_char] = canonical_char

        return bmp_to_canonical

    def _load_runtime_candidates(
        self, path: Path
    ) -> Dict[str, List[Dict[str, object]]]:
        """加载运行时候选词"""
        if not path.exists():
            raise FileNotFoundError(f"未找到运行时候选文件: {path}")
        payload = self._load_json(path)
        by_code = payload.get("by_code")
        if not isinstance(by_code, dict):
            raise ValueError(f"运行时候选文件格式无效: {path}")
        return by_code

    def decode_text(
        self, text: str
    ) -> Tuple[str, str, str, List[str], str]:
        """
        解码文本

        Args:
            text: 输入的音元码元文本

        Returns:
            (规范编码, 当前4码, 拼音显示, 候选词列表, 状态消息)
        """
        canonical = _canonicalize_runtime_input(text, self.bmp_to_canonical)
        if not canonical:
            return "", "", "", [], "请输入一个完整音节的 4 个码元。"

        if len(canonical) < 4:
            return (
                canonical,
                canonical,
                "",
                [],
                f"当前 {len(canonical)}/4 码，继续输入。",
            )

        plan = _build_runtime_lookup_plan(canonical)
        mode_hint = _build_runtime_mode_hint(canonical, plan)
        records = self._rank_runtime_candidates(
            self._payload_to_runtime_candidates(
                plan.lookup_code,
                self.by_code.get(plan.lookup_code, []),
            )
        )
        texts = [record.text for record in records]
        pinyin_values: List[str] = []
        for record in records:
            if record.pinyin_tone and record.pinyin_tone not in pinyin_values:
                pinyin_values.append(record.pinyin_tone)

        display_pinyin = " / ".join(pinyin_values[:3])
        if texts:
            status = f"从运行时编码表找到 {len(texts)} 个候选。"
            if mode_hint:
                status = f"{mode_hint} {status}"
            return canonical, plan.active_code, display_pinyin, texts, status

        if plan.phrase_mode:
            status = f"运行时编码表中未找到该 {plan.syllable_count} 音节词语候选。"
        else:
            status = "运行时编码表中未找到该 4 码候选。"
        if mode_hint:
            status = f"{mode_hint} {status}"
        return canonical, plan.active_code, display_pinyin, [], status

    def record_selection(self, text: str, candidate_text: str) -> None:
        canonical = _canonicalize_runtime_input(text, self.bmp_to_canonical)
        plan = _build_runtime_lookup_plan(canonical)
        if not plan.lookup_code or not candidate_text.strip():
            return
        key = (plan.lookup_code, candidate_text.strip())
        self._user_freq_by_candidate[key] = self._user_freq_by_candidate.get(key, 0) + 1

    def get_char_candidates(self, code: str) -> List[CharCodeCandidate]:
        """按完整音元编码读取单字候选。"""
        return self.char_code_index.get_exact(code)

    def get_char_candidates_by_prefix(
        self,
        prefix: str,
        limit: int = 0,
    ) -> List[Tuple[str, List[CharCodeCandidate]]]:
        """按编码前缀读取可能的单字候选。"""
        return self.char_code_index.get_with_prefix(prefix, limit=limit)

    def _payload_to_runtime_candidates(
        self,
        lookup_code: str,
        raw_candidates: List[Dict[str, object]],
    ) -> List[RuntimeCandidateRecord]:
        records: List[RuntimeCandidateRecord] = []
        for candidate in raw_candidates:
            text = str(candidate.get("text", "")).strip()
            if not text:
                continue
            text_length = int(candidate.get("text_length") or len(text))
            records.append(
                RuntimeCandidateRecord(
                    lookup_code=lookup_code,
                    text=text,
                    entry_type=str(candidate.get("entry_type", "")).strip(),
                    pinyin_tone=str(candidate.get("pinyin_tone", "")).strip(),
                    sort_weight=_as_float_value(candidate.get("sort_weight", 0.0)),
                    text_length=text_length,
                    is_common=_as_bool_value(candidate.get("is_common", False)),
                )
            )
        return records

    def _rank_runtime_candidates(
        self,
        candidates: List[RuntimeCandidateRecord],
    ) -> List[RuntimeCandidateRecord]:
        best_by_text: dict[str, RuntimeCandidateRecord] = {}
        for candidate in candidates:
            if candidate.entry_type == "phrase" and not (2 <= candidate.text_length <= 4):
                continue
            existing = best_by_text.get(candidate.text)
            candidate_freq = self._user_freq_by_candidate.get(
                (candidate.lookup_code, candidate.text),
                0,
            )
            if existing is None:
                best_by_text[candidate.text] = candidate
                continue
            existing_freq = self._user_freq_by_candidate.get(
                (existing.lookup_code, existing.text),
                0,
            )
            if _runtime_candidate_sort_key(candidate, candidate_freq) < _runtime_candidate_sort_key(existing, existing_freq):
                best_by_text[candidate.text] = candidate

        ranked = list(best_by_text.values())
        ranked.sort(
            key=lambda candidate: _runtime_candidate_sort_key(
                candidate,
                self._user_freq_by_candidate.get(
                    (candidate.lookup_code, candidate.text),
                    0,
                ),
            )
        )
        return ranked


class SQLiteRuntimeCandidateDecoder:
    """直接从 SQLite runtime_candidates 视图读取候选。"""

    def __init__(self, app_dir: Path) -> None:
        self.db_path = app_dir / "pinyin_hanzi.db"
        if not self.db_path.exists():
            raise FileNotFoundError(f"未找到输入法数据库: {self.db_path}")
        self.bmp_to_canonical = self._build_bmp_to_canonical_map(
            app_dir.parent / "internal_data" / "bmp_pua_trial_projection.json",
            app_dir.parent / "internal_data" / "key_to_symbol.json",
        )
        self._validate_runtime_candidates_view()
        self._user_freq_by_candidate: dict[tuple[str, str], int] = {}

    def _load_json(self, path: Path) -> dict:
        with path.open("r", encoding="utf-8") as handle:
            return json.load(handle)

    def _build_bmp_to_canonical_map(
        self, projection_path: Path, key_to_symbol_path: Path
    ) -> Dict[str, str]:
        projection = self._load_json(projection_path)
        key_to_symbol = self._load_json(key_to_symbol_path)
        bmp_to_canonical: Dict[str, str] = {}

        for symbol_key, slot_info in projection["used_mapping"].items():
            bmp_char = slot_info["char"]
            canonical_char = key_to_symbol.get(symbol_key)
            if canonical_char:
                bmp_to_canonical[bmp_char] = canonical_char

        return bmp_to_canonical

    def _connect(self) -> sqlite3.Connection:
        connection = sqlite3.connect(f"file:{self.db_path}?mode=ro", uri=True)
        connection.row_factory = sqlite3.Row
        return connection

    def _validate_runtime_candidates_view(self) -> None:
        with self._connect() as conn:
            row = conn.execute(
                "SELECT type FROM sqlite_master WHERE name = 'runtime_candidates'"
            ).fetchone()
            if row is None:
                raise ValueError("数据库中缺少 runtime_candidates 视图")

    def decode_text(
        self, text: str
    ) -> Tuple[str, str, str, List[str], str]:
        canonical = _canonicalize_runtime_input(text, self.bmp_to_canonical)
        if not canonical:
            return "", "", "", [], "请输入一个完整音节的 4 个码元。"

        if len(canonical) < 4:
            return (
                canonical,
                canonical,
                "",
                [],
                f"当前 {len(canonical)}/4 码，继续输入。",
            )

        plan = _build_runtime_lookup_plan(canonical)
        mode_hint = _build_runtime_mode_hint(canonical, plan)

        with self._connect() as conn:
            rows = conn.execute(
                """
                SELECT text, pinyin_tone, entry_type, sort_weight, text_length, is_common
                FROM runtime_candidates
                WHERE yime_code = ?
                """,
                (plan.lookup_code,),
            ).fetchall()

        records = self._rank_runtime_candidates(
            [self._row_to_runtime_candidate(plan.lookup_code, row) for row in rows]
        )
        texts = [record.text for record in records]
        pinyin_values: List[str] = []
        for record in records:
            if record.pinyin_tone and record.pinyin_tone not in pinyin_values:
                pinyin_values.append(record.pinyin_tone)

        display_pinyin = " / ".join(pinyin_values[:3])
        if texts:
            status = f"从数据库候选视图找到 {len(texts)} 个候选。"
            if mode_hint:
                status = f"{mode_hint} {status}"
            return canonical, plan.active_code, display_pinyin, texts, status

        if plan.phrase_mode:
            status = f"数据库候选视图中未找到该 {plan.syllable_count} 音节词语候选。"
        else:
            status = "数据库候选视图中未找到该 4 码候选。"
        if mode_hint:
            status = f"{mode_hint} {status}"
        return canonical, plan.active_code, display_pinyin, [], status

    def record_selection(self, text: str, candidate_text: str) -> None:
        canonical = _canonicalize_runtime_input(text, self.bmp_to_canonical)
        plan = _build_runtime_lookup_plan(canonical)
        if not plan.lookup_code or not candidate_text.strip():
            return
        key = (plan.lookup_code, candidate_text.strip())
        self._user_freq_by_candidate[key] = self._user_freq_by_candidate.get(key, 0) + 1

    def get_char_candidates(self, code: str) -> List[CharCodeCandidate]:
        """按完整音元编码读取单字候选。"""
        with self._connect() as conn:
            rows = conn.execute(
                """
                SELECT entry_id, text, pinyin_tone, yime_code, sort_weight, is_common
                FROM runtime_candidates
                WHERE entry_type = 'char'
                  AND yime_code = ?
                ORDER BY sort_weight DESC, text
                """,
                (code,),
            ).fetchall()

        return [self._row_to_char_candidate(row) for row in rows]

    def get_char_candidates_by_prefix(
        self,
        prefix: str,
        limit: int = 0,
    ) -> List[Tuple[str, List[CharCodeCandidate]]]:
        """按编码前缀读取可能的单字候选。"""
        with self._connect() as conn:
            if limit > 0:
                code_rows = conn.execute(
                    """
                    SELECT DISTINCT yime_code
                    FROM runtime_candidates
                    WHERE entry_type = 'char'
                      AND yime_code LIKE ?
                    ORDER BY yime_code
                    LIMIT ?
                    """,
                    (f"{prefix}%", limit),
                ).fetchall()
                codes = [str(row["yime_code"] or "").strip() for row in code_rows]
                codes = [code for code in codes if code]
                if not codes:
                    return []
                placeholders = ", ".join("?" for _ in codes)
                rows = conn.execute(
                    f"""
                    SELECT entry_id, text, pinyin_tone, yime_code, sort_weight, is_common
                    FROM runtime_candidates
                    WHERE entry_type = 'char'
                      AND yime_code IN ({placeholders})
                    ORDER BY yime_code, sort_weight DESC, text
                    """,
                    tuple(codes),
                ).fetchall()
            else:
                rows = conn.execute(
                    """
                    SELECT entry_id, text, pinyin_tone, yime_code, sort_weight, is_common
                    FROM runtime_candidates
                    WHERE entry_type = 'char'
                      AND yime_code LIKE ?
                    ORDER BY yime_code, sort_weight DESC, text
                    """,
                    (f"{prefix}%",),
                ).fetchall()

        grouped: dict[str, List[CharCodeCandidate]] = {}
        for row in rows:
            candidate = self._row_to_char_candidate(row)
            if candidate.code not in grouped and limit > 0 and len(grouped) >= limit:
                break
            grouped.setdefault(candidate.code, []).append(candidate)
        return [(code, candidates) for code, candidates in grouped.items()]

    def _row_to_char_candidate(self, row: sqlite3.Row) -> CharCodeCandidate:
        return CharCodeCandidate(
            text=str(row["text"] or "").strip(),
            code=str(row["yime_code"] or "").strip(),
            entry_id=str(row["entry_id"] or "").strip(),
            pinyin_tone=str(row["pinyin_tone"] or "").strip(),
            sort_weight=_as_float_value(row["sort_weight"]),
            is_common=_as_bool_value(row["is_common"]),
        )

    def _row_to_runtime_candidate(
        self,
        lookup_code: str,
        row: sqlite3.Row,
    ) -> RuntimeCandidateRecord:
        text = str(row["text"] or "").strip()
        text_length = int(row["text_length"] or len(text))
        return RuntimeCandidateRecord(
            lookup_code=lookup_code,
            text=text,
            entry_type=str(row["entry_type"] or "").strip(),
            pinyin_tone=str(row["pinyin_tone"] or "").strip(),
            sort_weight=_as_float_value(row["sort_weight"]),
            text_length=text_length,
            is_common=_as_bool_value(row["is_common"]),
        )

    def _rank_runtime_candidates(
        self,
        candidates: List[RuntimeCandidateRecord],
    ) -> List[RuntimeCandidateRecord]:
        best_by_text: dict[str, RuntimeCandidateRecord] = {}
        for candidate in candidates:
            if not candidate.text:
                continue
            if candidate.entry_type == "phrase" and not (2 <= candidate.text_length <= 4):
                continue
            existing = best_by_text.get(candidate.text)
            candidate_freq = self._user_freq_by_candidate.get(
                (candidate.lookup_code, candidate.text),
                0,
            )
            if existing is None:
                best_by_text[candidate.text] = candidate
                continue
            existing_freq = self._user_freq_by_candidate.get(
                (existing.lookup_code, existing.text),
                0,
            )
            if _runtime_candidate_sort_key(candidate, candidate_freq) < _runtime_candidate_sort_key(existing, existing_freq):
                best_by_text[candidate.text] = candidate

        ranked = list(best_by_text.values())
        ranked.sort(
            key=lambda candidate: _runtime_candidate_sort_key(
                candidate,
                self._user_freq_by_candidate.get(
                    (candidate.lookup_code, candidate.text),
                    0,
                ),
            )
        )
        return ranked


class CompositeCandidateDecoder:
    """组合候选词解码器（优先运行时，回退静态）"""

    def __init__(self, app_dir: Path) -> None:
        """
        初始化组合解码器

        Args:
            app_dir: 应用目录路径
        """
        self.runtime_decoder: Optional[
            RuntimeCandidateDecoder | SQLiteRuntimeCandidateDecoder
        ] = None
        self.runtime_load_error = ""
        self.runtime_source = ""
        try:
            self.runtime_decoder = RuntimeCandidateDecoder(app_dir)
            self.runtime_source = "json"
        except (FileNotFoundError, ValueError, KeyError, json.JSONDecodeError) as exc:
            self.runtime_load_error = str(exc)
            try:
                self.runtime_decoder = SQLiteRuntimeCandidateDecoder(app_dir)
                self.runtime_source = "sqlite"
                self.runtime_load_error = ""
            except (FileNotFoundError, ValueError, sqlite3.Error) as db_exc:
                self.runtime_load_error = (
                    f"JSON导出不可用: {exc}; SQLite回退不可用: {db_exc}"
                )
        self.static_decoder = StaticCandidateDecoder(app_dir)

    def get_runtime_warning(self) -> str:
        """返回运行时编码表告警，供上层决定是否展示。"""
        return self.runtime_load_error

    def get_runtime_source(self) -> str:
        """返回当前启用的运行时候选来源。"""
        return self.runtime_source

    def get_char_candidates(self, code: str) -> List[CharCodeCandidate]:
        """按完整音元编码读取单字候选。"""
        if self.runtime_decoder is None:
            return []
        return self.runtime_decoder.get_char_candidates(code)

    def get_char_candidates_by_prefix(
        self,
        prefix: str,
        limit: int = 0,
    ) -> List[Tuple[str, List[CharCodeCandidate]]]:
        """按编码前缀读取可能的单字候选。"""
        if self.runtime_decoder is None:
            return []
        return self.runtime_decoder.get_char_candidates_by_prefix(prefix, limit=limit)

    def record_selection(self, text: str, candidate_text: str) -> None:
        """Record a user selection so runtime ranking can adapt in-process."""
        if self.runtime_decoder is None:
            return
        if hasattr(self.runtime_decoder, "record_selection"):
            self.runtime_decoder.record_selection(text, candidate_text)

    def decode_text(
        self, text: str
    ) -> Tuple[str, str, str, List[str], str]:
        """
        解码文本（优先运行时，回退静态）

        Args:
            text: 输入的音元码元文本

        Returns:
            (规范编码, 当前4码, 拼音显示, 候选词列表, 状态消息)
        """
        if self.runtime_decoder is not None:
            canonical, active_code, pinyin, candidates, status = (
                self.runtime_decoder.decode_text(text)
            )
            if candidates:
                return canonical, active_code, pinyin, candidates, status
            if active_code:
                fallback = self.static_decoder.decode_text(text)
                if fallback[3]:
                    return (
                        fallback[0],
                        fallback[1],
                        fallback[2],
                        fallback[3],
                        f"{status} 已回退到静态拼音候选表。",
                    )
                return canonical, active_code, pinyin, candidates, status

        return self.static_decoder.decode_text(text)
