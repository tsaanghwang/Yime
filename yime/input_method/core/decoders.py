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
from typing import Dict, List, Tuple, Optional


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
        key_to_code_path = repo_root / "key_to_code.json"
        mapping_path = app_dir / "enhanced_yinjie_mapping.json"
        pinyin_hanzi_paths = [
            app_dir / "pinyin_hanzi.json",
            repo_root / "pinyin" / "hanzi_pinyin" / "pinyin_hanzi.json",
        ]

        self.bmp_to_canonical = self._build_bmp_to_canonical_map(
            projection_path, key_to_code_path
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
        self, projection_path: Path, key_to_code_path: Path
    ) -> Dict[str, str]:
        """构建BMP字符到规范字符的映射"""
        projection = self._load_json(projection_path)
        key_to_code = self._load_json(key_to_code_path)
        bmp_to_canonical: Dict[str, str] = {}

        for symbol_key, slot_info in projection["used_mapping"].items():
            bmp_char = slot_info["char"]
            canonical_char = key_to_code.get(symbol_key)
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
            app_dir.parent / "key_to_code.json",
        )
        self.by_code = self._load_runtime_candidates(self.runtime_path)

    def _load_json(self, path: Path) -> dict:
        """加载JSON文件"""
        with path.open("r", encoding="utf-8") as handle:
            return json.load(handle)

    def _build_bmp_to_canonical_map(
        self, projection_path: Path, key_to_code_path: Path
    ) -> Dict[str, str]:
        """构建BMP字符到规范字符的映射"""
        projection = self._load_json(projection_path)
        key_to_code = self._load_json(key_to_code_path)
        bmp_to_canonical: Dict[str, str] = {}

        for symbol_key, slot_info in projection["used_mapping"].items():
            bmp_char = slot_info["char"]
            canonical_char = key_to_code.get(symbol_key)
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


class CompositeCandidateDecoder:
    """组合候选词解码器（优先运行时，回退静态）"""

    def __init__(self, app_dir: Path) -> None:
        """
        初始化组合解码器

        Args:
            app_dir: 应用目录路径
        """
        self.runtime_decoder: Optional[RuntimeCandidateDecoder] = None
        self.runtime_load_error = ""
        try:
            self.runtime_decoder = RuntimeCandidateDecoder(app_dir)
        except (FileNotFoundError, ValueError, KeyError, json.JSONDecodeError) as exc:
            self.runtime_load_error = str(exc)
        self.static_decoder = StaticCandidateDecoder(app_dir)

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

        fallback = self.static_decoder.decode_text(text)
        if self.runtime_load_error:
            fallback_status = fallback[4]
            if fallback_status:
                fallback_status = (
                    f"{fallback_status} 运行时编码表未启用: {self.runtime_load_error}"
                )
            else:
                fallback_status = (
                    f"运行时编码表未启用: {self.runtime_load_error}"
                )
            return (
                fallback[0],
                fallback[1],
                fallback[2],
                fallback[3],
                fallback_status,
            )
        return fallback
