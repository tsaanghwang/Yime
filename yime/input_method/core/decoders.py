"""
候选词解码器模块

提供三种解码器：
1. StaticCandidateDecoder - 静态拼音候选表解码
2. RuntimeCandidateDecoder - 运行时编码表解码
3. CompositeCandidateDecoder - 组合解码器（优先运行时，回退静态）
"""

from __future__ import annotations

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


def _format_char_prefix_status(
    matches: List[Tuple[str, List[CharCodeCandidate]]],
) -> str:
    if not matches:
        return "单字前缀暂无命中。"

    candidate_count = sum(len(candidates) for _, candidates in matches)
    samples: List[str] = []
    seen: set[str] = set()
    for _, candidates in matches:
        for candidate in candidates:
            if candidate.text in seen:
                continue
            seen.add(candidate.text)
            samples.append(candidate.text)
            if len(samples) >= 5:
                break
        if len(samples) >= 5:
            break

    sample_status = f"，示例: {' '.join(samples)}" if samples else ""
    return (
        f"单字前缀可继续：前 {len(matches)} 个编码含 "
        f"{candidate_count} 个候选{sample_status}。"
    )


def build_code_display(raw_text: str, canonical_code: str, active_code: str) -> str:
    if not active_code:
        return ""

    active_display = format_codepoints(active_code)
    if not canonical_code:
        return active_display

    if raw_text and raw_text != canonical_code:
        return (
            f"当前4码 {active_display} | 输入 {format_codepoints(raw_text)}"
            f" | 规范化后共 {len(canonical_code)} 码"
        )

    if active_code != canonical_code:
        return f"当前4码 {active_display} | 累计输入 {len(canonical_code)} 码"

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
        canonical = "".join(
            self.bmp_to_canonical.get(char, char) for char in text
        )
        if not canonical:
            return "", "", "", [], "请输入一个完整音节的 4 个码元。"

        if len(canonical) < 4:
            prefix_status = _format_char_prefix_status(
                self.get_char_candidates_by_prefix(canonical, limit=5)
            )
            return (
                canonical,
                canonical,
                "",
                [],
                f"当前 {len(canonical)}/4 码，继续输入。{prefix_status}",
            )

        active_code = canonical[-4:]
        mode_hint = ""
        if len(canonical) > 4:
            mode_hint = f"已自动截取最近 4 码，总输入 {len(canonical)} 码。"

        raw_candidates = self.by_code.get(active_code, [])
        texts: List[str] = []
        seen: set = set()
        pinyin_values: List[str] = []
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
        canonical = "".join(
            self.bmp_to_canonical.get(char, char) for char in text
        )
        if not canonical:
            return "", "", "", [], "请输入一个完整音节的 4 个码元。"

        if len(canonical) < 4:
            prefix_status = _format_char_prefix_status(
                self.get_char_candidates_by_prefix(canonical, limit=5)
            )
            return (
                canonical,
                canonical,
                "",
                [],
                f"当前 {len(canonical)}/4 码，继续输入。{prefix_status}",
            )

        active_code = canonical[-4:]
        mode_hint = ""
        if len(canonical) > 4:
            mode_hint = f"已自动截取最近 4 码，总输入 {len(canonical)} 码。"

        with self._connect() as conn:
            rows = conn.execute(
                """
                SELECT text, pinyin_tone, entry_type, sort_weight
                FROM runtime_candidates
                WHERE yime_code = ?
                ORDER BY entry_type, sort_weight DESC, text
                """,
                (active_code,),
            ).fetchall()

        texts: List[str] = []
        seen_texts: set[str] = set()
        pinyin_values: List[str] = []
        for row in rows:
            candidate_text = str(row["text"] or "").strip()
            if not candidate_text or candidate_text in seen_texts:
                continue
            seen_texts.add(candidate_text)
            texts.append(candidate_text)
            pinyin_value = str(row["pinyin_tone"] or "").strip()
            if pinyin_value and pinyin_value not in pinyin_values:
                pinyin_values.append(pinyin_value)

        display_pinyin = " / ".join(pinyin_values[:3])
        if texts:
            status = f"从数据库候选视图找到 {len(texts)} 个候选。"
            if mode_hint:
                status = f"{mode_hint} {status}"
            return canonical, active_code, display_pinyin, texts, status

        status = "数据库候选视图中未找到该 4 码候选。"
        if mode_hint:
            status = f"{mode_hint} {status}"
        return canonical, active_code, display_pinyin, [], status

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
