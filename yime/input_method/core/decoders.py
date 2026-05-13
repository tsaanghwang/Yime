"""
候选词解码器模块

提供三种解码器：
1. StaticCandidateDecoder - 静态拼音候选表解码
2. RuntimeCandidateDecoder - 运行时编码表解码
3. CompositeCandidateDecoder - 组合解码器（优先运行时，回退静态）
"""

from __future__ import annotations

import json
from pathlib import Path
import unicodedata
from typing import Dict, List, Tuple, Optional, cast

from ...asset_paths import resolve_runtime_candidates_json_path
from .char_code_index import CharCodeCandidate
from .runtime_decoder_base import (
    RuntimeDecoderBase as _RuntimeDecoderBase,
    build_pinyin_to_canonical_code_map as _build_pinyin_to_canonical_code_map,
    resolve_canonical_code_from_pinyin_tone as _resolve_canonical_code_from_pinyin_tone,
)
from .runtime_json_store import JSONRuntimeCandidateStore
from .runtime_lookup import (
    RuntimeLookupPlan,
    build_phrase_tree_lookup as _build_phrase_tree_lookup,
)
from .runtime_ranking import (
    RuntimeCandidateRecord,
    annotate_candidate_source as _annotate_candidate_source,
    annotate_phrase_prefix_candidate as _annotate_phrase_prefix_candidate,
)
from .sqlite_char_store import SQLiteCharCandidateStore
from .sqlite_phrase_store import SQLitePhraseCandidateStore
from .sqlite_runtime_source import SQLiteRuntimeSource


JSONDict = dict[str, object]
RuntimeCandidatePayload = Dict[str, List[JSONDict]]



class StaticCandidateDecoder:
    """静态候选词解码器（基于拼音候选表）"""

    def __init__(self, app_dir: Path) -> None:
        repo_root = app_dir.parent
        projection_path = repo_root / "internal_data" / "bmp_pua_trial_projection.json"
        key_to_symbol_path = repo_root / "internal_data" / "key_to_symbol.json"
        mapping_path = app_dir / "enhanced_yinjie_mapping.json"
        pinyin_hanzi_paths = [app_dir / "pinyin_hanzi.json"]

        self.bmp_to_canonical = self._build_bmp_to_canonical_map(
            projection_path,
            key_to_symbol_path,
        )
        self.pinyin_to_canonical = _build_pinyin_to_canonical_code_map(
            repo_root,
            self.bmp_to_canonical,
        )
        self.code_mapping = self._build_code_mapping(repo_root, mapping_path)
        self.pinyin_hanzi = self._load_first_available_json(pinyin_hanzi_paths)

    def _load_json(self, path: Path) -> JSONDict:
        with path.open("r", encoding="utf-8") as handle:
            payload = json.load(handle)
        return cast(JSONDict, payload)

    def _load_first_available_json(self, paths: List[Path]) -> JSONDict:
        for path in paths:
            if path.exists():
                return self._load_json(path)
        joined = ", ".join(str(path) for path in paths)
        raise FileNotFoundError(f"未找到候选数据文件: {joined}")

    def _build_bmp_to_canonical_map(
        self, projection_path: Path, key_to_symbol_path: Path
    ) -> Dict[str, str]:
        projection = self._load_json(projection_path)
        key_to_symbol = self._load_json(key_to_symbol_path)
        bmp_to_canonical: Dict[str, str] = {}
        used_mapping = projection.get("used_mapping")
        if not isinstance(used_mapping, dict):
            return bmp_to_canonical

        for symbol_key, slot_info in used_mapping.items():
            if not isinstance(slot_info, dict):
                continue
            bmp_char = str(slot_info.get("char", "") or "")
            canonical_char = str(key_to_symbol.get(str(symbol_key), "") or "")
            if canonical_char:
                bmp_to_canonical[bmp_char] = canonical_char

        return bmp_to_canonical

    def _build_code_mapping(
        self,
        repo_root: Path,
        mapping_path: Path,
    ) -> Dict[str, JSONDict]:
        mapping_payload = self._load_json(mapping_path)
        supplemental_mapping = mapping_payload.get("音元符号")
        supplemental_by_numeric: Dict[str, dict[str, object]] = {}
        if not isinstance(supplemental_mapping, dict):
            supplemental_mapping = {}
        for metadata in supplemental_mapping.values():
            if not isinstance(metadata, dict):
                continue
            numeric_pinyin = str(metadata.get("数字标调", "")).strip()
            if numeric_pinyin and numeric_pinyin not in supplemental_by_numeric:
                supplemental_by_numeric[numeric_pinyin] = cast(JSONDict, dict(metadata))

        code_mapping: Dict[str, JSONDict] = {}
        for numeric_pinyin, canonical_code in self.pinyin_to_canonical.items():
            metadata = dict(supplemental_by_numeric.get(numeric_pinyin, {}))
            metadata["数字标调"] = numeric_pinyin
            code_mapping[canonical_code] = metadata
        return code_mapping

    def decode_text(
        self, text: str
    ) -> Tuple[str, str, str, List[str], str]:
        """解码文本。"""
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

        numeric_pinyin = str(mapping.get("数字标调", "") or "")
        marked_pinyin = unicodedata.normalize(
            "NFC",
            str(mapping.get("调号标调", "") or ""),
        )
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
        candidate_keys: List[str] = []
        if marked_pinyin:
            candidate_keys.append(marked_pinyin)
        if numeric_pinyin:
            candidate_keys.append(numeric_pinyin)
            candidate_keys.append(numeric_pinyin[:-1])

        merged: List[str] = []
        seen: set[str] = set()
        for key in candidate_keys:
            hanzi_values = self.pinyin_hanzi.get(key, [])
            if not isinstance(hanzi_values, list):
                continue
            for hanzi in hanzi_values:
                if not isinstance(hanzi, str):
                    continue
                if hanzi not in seen:
                    seen.add(hanzi)
                    merged.append(hanzi)

        return merged


class RuntimeCandidateDecoder(_RuntimeDecoderBase):
    """运行时候选词解码器，JSON 导出为数据源。"""

    def __init__(self, app_dir: Path, user_db_path: Path | None = None) -> None:
        self.runtime_path = resolve_runtime_candidates_json_path(app_dir)
        self._init_runtime_decoder_common(app_dir, user_db_path)
        self._json_store = JSONRuntimeCandidateStore(
            self.runtime_path,
            self.pinyin_to_canonical,
            _resolve_canonical_code_from_pinyin_tone,
        )
        self._json_store.refresh(
            self.user_lexicon.load_phrase_candidates(self.pinyin_to_canonical),
        )
        self.by_code = self._json_store.by_code
        self._char_sort_weight_by_text = self._json_store.char_sort_weight_by_text
        self._phrase_prefix_index = self._json_store.phrase_prefix_index
        self.char_code_index = self._json_store.char_code_index
        self._user_freq_by_candidate = self.user_lexicon.load_candidate_frequency()

    def _load_runtime_candidates(
        self, path: Path
    ) -> RuntimeCandidatePayload:
        json_store = getattr(self, "_json_store", None)
        if json_store is not None:
            return json_store.load_runtime_candidates(path)

        if not path.exists():
            raise FileNotFoundError(f"未找到运行时候选文件: {path}")
        raw_text = path.read_text(encoding="utf-8")
        if raw_text.lstrip().startswith("version https://git-lfs.github.com/spec/v1"):
            raise ValueError(f"运行时候选文件是 Git LFS 指针，未拉取实际内容: {path}")

        payload = json.loads(raw_text)
        by_code = payload.get("by_code") if isinstance(payload, dict) else None
        if not isinstance(by_code, dict):
            raise ValueError(f"运行时候选文件格式无效: {path}")

        regrouped: RuntimeCandidatePayload = {}
        for raw_candidates in by_code.values():
            if not isinstance(raw_candidates, list):
                continue
            for candidate in raw_candidates:
                if not isinstance(candidate, dict):
                    continue
                canonical_code = str(candidate.get("yime_code", "") or "").strip()
                if not canonical_code:
                    pinyin_tone = str(candidate.get("pinyin_tone", "") or "").strip()
                    canonical_code = _resolve_canonical_code_from_pinyin_tone(
                        pinyin_tone,
                        self.pinyin_to_canonical,
                    )
                if not canonical_code:
                    continue
                regrouped.setdefault(canonical_code, []).append(
                    _annotate_candidate_source(candidate, "exact")
                )
        return regrouped

    def reload_user_lexicon(self) -> None:
        self._json_store.refresh(
            self.user_lexicon.load_phrase_candidates(self.pinyin_to_canonical),
        )
        self.by_code = self._json_store.by_code
        self._char_sort_weight_by_text = self._json_store.char_sort_weight_by_text
        self._phrase_prefix_index = self._json_store.phrase_prefix_index
        self.char_code_index = self._json_store.char_code_index
        self._user_freq_by_candidate = self.user_lexicon.load_candidate_frequency()

    def _load_phrase_prefix_candidates(
        self,
        lookup_code: str,
        *,
        limit: int = 0,
    ) -> List[JSONDict]:
        json_store = getattr(self, "_json_store", None)
        if json_store is not None:
            return json_store.load_phrase_prefix_candidates(lookup_code, limit=limit)

        normalized_code = str(lookup_code or "").strip()
        if not normalized_code:
            return []
        phrase_prefix_index = getattr(self, "_phrase_prefix_index", {})
        candidates = [
            _annotate_phrase_prefix_candidate(candidate, len(normalized_code))
            for candidate in phrase_prefix_index.get(normalized_code, [])
            if isinstance(candidate, dict)
        ]
        normalized_limit = max(int(limit or 0), 0)
        if normalized_limit > 0:
            return candidates[:normalized_limit]
        return candidates

    def _lookup_runtime_candidates_for_decode(
        self,
        canonical: str,
        plan: RuntimeLookupPlan,
    ) -> tuple[List[JSONDict], str]:
        raw_candidates: List[JSONDict] = []
        phrase_tree_lookup = _build_phrase_tree_lookup(canonical, plan)
        if phrase_tree_lookup:
            raw_candidates.extend(
                self._load_phrase_prefix_candidates(
                    phrase_tree_lookup,
                    limit=plan.phrase_prefix_limit,
                )
            )
        if plan.lookup_code and (plan.stage != "C" or not raw_candidates):
            raw_candidates.extend(
                _annotate_candidate_source(candidate, "exact")
                for candidate in self.by_code.get(plan.lookup_code, [])
                if isinstance(candidate, dict)
            )
        return raw_candidates, phrase_tree_lookup or plan.lookup_code

    def get_char_candidates(self, code: str) -> List[CharCodeCandidate]:
        """按完整音元编码读取单字候选。"""
        json_store = getattr(self, "_json_store", None)
        if json_store is not None:
            return json_store.get_char_candidates(code)
        return self.char_code_index.get_exact(code)

    def get_char_candidates_by_prefix(
        self,
        prefix: str,
        limit: int = 0,
    ) -> List[Tuple[str, List[CharCodeCandidate]]]:
        """按编码前缀读取可能的单字候选。"""
        json_store = getattr(self, "_json_store", None)
        if json_store is not None:
            return json_store.get_char_candidates_by_prefix(prefix, limit=limit)
        return self.char_code_index.get_with_prefix(prefix, limit=limit)

class SQLiteRuntimeCandidateDecoder(_RuntimeDecoderBase):
    """直接从 SQLite runtime_candidates 视图读取候选。"""

    def __init__(self, app_dir: Path, user_db_path: Path | None = None) -> None:
        self.db_path = app_dir / "pinyin_hanzi.db"
        self.runtime_source_label = "数据库候选视图"
        self._init_runtime_decoder_common(app_dir, user_db_path)
        self._sqlite_runtime_source = SQLiteRuntimeSource(self.db_path)
        self.runtime_table_name = self._sqlite_runtime_source.detect_runtime_candidate_table()
        self._char_store = SQLiteCharCandidateStore(self._sqlite_runtime_source, self.runtime_table_name)
        self._phrase_store = SQLitePhraseCandidateStore(self._sqlite_runtime_source, self.runtime_table_name)
        self._phrase_candidate_overlays = self.user_lexicon.load_phrase_candidates(
            self.pinyin_to_canonical,
        )
        self._char_sort_weight_by_text = self._char_store.load_char_sort_weight_index()
        self._user_freq_by_candidate = self.user_lexicon.load_candidate_frequency()

    def _lookup_runtime_candidates_for_decode(
        self,
        canonical: str,
        plan: RuntimeLookupPlan,
    ) -> tuple[List[JSONDict], str]:
        raw_candidates: List[JSONDict] = []
        in_memory_by_code = getattr(self, "by_code", None)
        phrase_tree_lookup = _build_phrase_tree_lookup(canonical, plan)
        if phrase_tree_lookup:
            raw_candidates.extend(
                self._phrase_store.load_phrase_prefix_candidates(
                    phrase_tree_lookup,
                    self._phrase_candidate_overlays,
                    limit=plan.phrase_prefix_limit,
                )
            )
        if plan.lookup_code and (plan.stage != "C" or not raw_candidates):
            if isinstance(in_memory_by_code, dict) and plan.lookup_code in in_memory_by_code:
                in_memory_candidates = in_memory_by_code.get(plan.lookup_code, [])
                if isinstance(in_memory_candidates, list):
                    raw_candidates.extend(
                        [
                            _annotate_candidate_source(candidate, "exact")
                            for candidate in in_memory_candidates
                            if isinstance(candidate, dict)
                        ]
                    )
            else:
                raw_candidates.extend(
                    self._phrase_store.load_runtime_candidates_for_code(
                        plan.lookup_code,
                        self._phrase_candidate_overlays,
                    )
                )
        return raw_candidates, phrase_tree_lookup or plan.lookup_code

    def get_char_candidates(self, code: str) -> List[CharCodeCandidate]:
        """按完整音元编码读取单字候选。"""
        return self._char_store.get_char_candidates(code)

    def get_char_candidates_by_prefix(
        self,
        prefix: str,
        limit: int = 0,
    ) -> List[Tuple[str, List[CharCodeCandidate]]]:
        """按编码前缀读取可能的单字候选。"""
        return self._char_store.get_char_candidates_by_prefix(prefix, limit=limit)

    def _load_runtime_candidates(self) -> RuntimeCandidatePayload:
        with self._sqlite_runtime_source.connect() as conn:
            rows = conn.execute(
                """
                SELECT entry_type, entry_id, text, pinyin_tone, yime_code, sort_weight, is_common, text_length, updated_at
                FROM runtime_candidates
                ORDER BY
                    CASE
                        WHEN entry_type = 'phrase' AND text_length BETWEEN 2 AND 4 THEN 0
                        WHEN entry_type = 'char' THEN 1
                        ELSE 2
                    END,
                    sort_weight DESC,
                    text,
                    pinyin_tone
                """
            ).fetchall()

        grouped: RuntimeCandidatePayload = {}
        for row in rows:
            pinyin_tone = str(row["pinyin_tone"] or "").strip()
            canonical_code = _resolve_canonical_code_from_pinyin_tone(
                pinyin_tone,
                self.pinyin_to_canonical,
            )
            if not canonical_code:
                continue
            grouped.setdefault(canonical_code, []).append(
                {
                    "text": row["text"],
                    "entry_type": row["entry_type"],
                    "entry_id": row["entry_id"],
                    "pinyin_tone": row["pinyin_tone"],
                    "yime_code": row["yime_code"],
                    "sort_weight": row["sort_weight"],
                    "is_common": row["is_common"],
                    "text_length": row["text_length"],
                    "updated_at": row["updated_at"],
                }
            )
        return grouped

    def reload_user_lexicon(self) -> None:
        self._phrase_candidate_overlays = self.user_lexicon.load_phrase_candidates(
            self.pinyin_to_canonical,
        )
        self._char_sort_weight_by_text = self._char_store.load_char_sort_weight_index()
        self._char_store.clear_caches()
        self._phrase_store.clear_caches()
        self._user_freq_by_candidate = self.user_lexicon.load_candidate_frequency()


class CompositeCandidateDecoder:
    """组合候选词解码器（优先运行时，回退静态）"""

    def __init__(self, app_dir: Path, user_db_path: Path | None = None) -> None:
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
            self.runtime_decoder = SQLiteRuntimeCandidateDecoder(app_dir, user_db_path=user_db_path)
            self.runtime_source = "sqlite"
        except (FileNotFoundError, ValueError) as exc:
            self.runtime_load_error = str(exc)
            try:
                self.runtime_decoder = RuntimeCandidateDecoder(app_dir, user_db_path=user_db_path)
                self.runtime_source = "json"
                self.runtime_load_error = ""
            except (FileNotFoundError, ValueError, KeyError, json.JSONDecodeError) as json_exc:
                self.runtime_load_error = (
                    f"SQLite 直查不可用: {exc}; JSON 导出不可用: {json_exc}"
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

    def record_selection(self, text: str, candidate_text: str) -> int:
        """Record a user selection so runtime ranking can adapt in-process."""
        if self.runtime_decoder is None:
            return 0
        if hasattr(self.runtime_decoder, "record_selection"):
            return int(self.runtime_decoder.record_selection(text, candidate_text) or 0)
        return 0

    def reload_user_lexicon(self) -> None:
        if self.runtime_decoder is None:
            return
        if hasattr(self.runtime_decoder, "reload_user_lexicon"):
            self.runtime_decoder.reload_user_lexicon()

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
