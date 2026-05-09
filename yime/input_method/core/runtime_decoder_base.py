from __future__ import annotations

from functools import lru_cache
import json
import os
from pathlib import Path
import unicodedata
from typing import Dict, List, Tuple

from .runtime_lookup import (
    RuntimeLookupPlan,
    build_runtime_lookup_plan,
    build_runtime_mode_hint,
)
from .runtime_ranking import (
    RuntimeCandidateRecord,
    build_runtime_candidate_records,
    format_runtime_debug_summary,
    load_local_phrase_priority_rules,
    rank_runtime_candidates,
)
from ..utils.user_lexicon import UserLexiconStore


def canonicalize_runtime_input(text: str, bmp_to_canonical: Dict[str, str]) -> str:
    return "".join(bmp_to_canonical.get(char, char) for char in text)


def _load_numeric_yime_code_map(repo_root: Path) -> Dict[str, str]:
    payload = json.loads(
        (repo_root / "syllable_codec" / "yinjie_code.json").read_text(encoding="utf-8")
    )
    return {
        str(pinyin_tone).strip(): str(yime_code)
        for pinyin_tone, yime_code in payload.items()
        if str(pinyin_tone).strip() and str(yime_code)
    }


@lru_cache(maxsize=None)
def load_numeric_to_marked_pinyin_map(mapping_path: str) -> Dict[str, str]:
    payload = json.loads(Path(mapping_path).read_text(encoding="utf-8"))
    return {
        str(numeric).strip(): unicodedata.normalize("NFC", str(marked))
        for numeric, marked in payload.items()
        if str(numeric).strip() and str(marked).strip()
    }


def format_marked_pinyin_display(
    numeric_pinyin: str,
    numeric_to_marked: Dict[str, str],
) -> str:
    normalized = " ".join(str(numeric_pinyin or "").split())
    if not normalized:
        return ""

    return " ".join(
        numeric_to_marked.get(syllable, syllable)
        for syllable in normalized.split(" ")
    )


def build_pinyin_to_canonical_code_map(
    repo_root: Path,
    bmp_to_canonical: Dict[str, str],
) -> Dict[str, str]:
    numeric_to_runtime = _load_numeric_yime_code_map(repo_root)
    return {
        pinyin_tone: canonicalize_runtime_input(runtime_code, bmp_to_canonical)
        for pinyin_tone, runtime_code in numeric_to_runtime.items()
    }


def resolve_canonical_code_from_pinyin_tone(
    pinyin_tone: str,
    pinyin_to_canonical: Dict[str, str],
) -> str:
    syllables = [syllable for syllable in pinyin_tone.split() if syllable]
    if not syllables:
        return ""

    canonical_parts: List[str] = []
    for syllable in syllables:
        canonical_code = pinyin_to_canonical.get(syllable)
        if not canonical_code:
            return ""
        canonical_parts.append(canonical_code)
    return "".join(canonical_parts)


def merge_runtime_candidate_maps(
    base_by_code: Dict[str, List[Dict[str, object]]],
    overlay_by_code: Dict[str, List[Dict[str, object]]],
) -> Dict[str, List[Dict[str, object]]]:
    merged = {code: list(candidates) for code, candidates in base_by_code.items()}
    for code, candidates in overlay_by_code.items():
        merged.setdefault(code, []).extend(candidates)
    return merged


class RuntimeDecoderBase:
    """Shared runtime-decoder pipeline independent from the backing store."""

    runtime_source_label = "运行时编码表"

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

    def _init_runtime_decoder_common(
        self,
        app_dir: Path,
        user_db_path: Path | None = None,
    ) -> None:
        self.bmp_to_canonical = self._build_bmp_to_canonical_map(
            app_dir.parent / "internal_data" / "bmp_pua_trial_projection.json",
            app_dir.parent / "internal_data" / "key_to_symbol.json",
        )
        self.pinyin_to_canonical = build_pinyin_to_canonical_code_map(
            app_dir.parent,
            self.bmp_to_canonical,
        )
        self.numeric_to_marked_pinyin = load_numeric_to_marked_pinyin_map(
            str(app_dir / "pinyin_normalized.json")
        )
        self._local_phrase_priority_rules = load_local_phrase_priority_rules(
            app_dir.parent / "internal_data" / "local_phrase_priority_rules.json",
            self.pinyin_to_canonical,
            resolve_canonical_code_from_pinyin_tone,
        )
        self._continuous_input_priority_rules = load_local_phrase_priority_rules(
            app_dir.parent / "internal_data" / "continuous_input_priority_rules.json",
            self.pinyin_to_canonical,
            resolve_canonical_code_from_pinyin_tone,
            expected_lookup_code_length=None,
            min_lookup_code_length=5,
        )
        self.user_lexicon = UserLexiconStore(user_db_path or app_dir / "user_lexicon.db")
        self._user_freq_by_candidate = self.user_lexicon.load_candidate_frequency()
        self.debug_runtime_ranking = os.environ.get(
            "YIME_DEBUG_RUNTIME_RANKING",
            "",
        ).strip().lower() in {"1", "true", "yes", "on"}

    def _lookup_runtime_candidates_for_decode(
        self,
        canonical: str,
        plan: RuntimeLookupPlan,
    ) -> tuple[List[Dict[str, object]], str]:
        raise NotImplementedError

    def decode_text(
        self, text: str
    ) -> Tuple[str, str, str, List[str], str]:
        canonical = canonicalize_runtime_input(text, self.bmp_to_canonical)
        if not canonical:
            return "", "", "", [], "请输入一个完整音节的 4 个码元。"

        plan = build_runtime_lookup_plan(canonical)
        mode_hint = build_runtime_mode_hint(canonical, plan)
        raw_candidates, priority_lookup_code = self._lookup_runtime_candidates_for_decode(
            canonical,
            plan,
        )
        records = self._rank_runtime_candidates(
            self._payload_to_runtime_candidates(
                plan.lookup_code,
                raw_candidates,
                stage=plan.stage,
                priority_lookup_code=priority_lookup_code,
            )
        )
        texts = [record.text for record in records]
        pinyin_values: List[str] = []
        numeric_to_marked_pinyin = getattr(self, "numeric_to_marked_pinyin", {})
        for record in records:
            display_pinyin = format_marked_pinyin_display(
                record.pinyin_tone,
                numeric_to_marked_pinyin,
            )
            if display_pinyin and display_pinyin not in pinyin_values:
                pinyin_values.append(display_pinyin)

        display_pinyin = " / ".join(pinyin_values[:3])
        if texts:
            status = f"从{self.runtime_source_label}找到 {len(texts)} 个候选。"
            debug_summary = format_runtime_debug_summary(records)
            if getattr(self, "debug_runtime_ranking", False) and debug_summary:
                pool_hint = ""
                if plan.phrase_prefix_pool:
                    pool_hint = f"[{plan.phrase_prefix_pool}] "
                status = f"{status} 调试: {pool_hint}{debug_summary}。"
            if mode_hint:
                status = f"{mode_hint} {status}"
            return canonical, plan.active_code, display_pinyin, texts, status

        if len(canonical) < 4:
            status = f"当前 {len(canonical)}/4 码，继续输入。"
            return canonical, canonical, display_pinyin, [], status

        if plan.phrase_mode:
            status = f"{self.runtime_source_label}中未找到该 {plan.syllable_count} 音节词语候选。"
        else:
            status = f"{self.runtime_source_label}中未找到该 4 码候选。"
        if mode_hint:
            status = f"{mode_hint} {status}"
        return canonical, plan.active_code, display_pinyin, [], status

    def record_selection(self, text: str, candidate_text: str) -> int:
        canonical = canonicalize_runtime_input(text, self.bmp_to_canonical)
        plan = build_runtime_lookup_plan(canonical)
        if not plan.lookup_code or not candidate_text.strip():
            return 0
        key = (plan.lookup_code, candidate_text.strip())
        user_lexicon = getattr(self, "user_lexicon", None)
        if user_lexicon is None:
            persisted_freq = int(self._user_freq_by_candidate.get(key, 0)) + 1
        else:
            persisted_freq = user_lexicon.record_candidate_selection(*key)
        self._user_freq_by_candidate[key] = persisted_freq
        return persisted_freq

    def _payload_to_runtime_candidates(
        self,
        lookup_code: str,
        raw_candidates: List[Dict[str, object]],
        stage: str = "",
        priority_lookup_code: str = "",
    ) -> List[RuntimeCandidateRecord]:
        return build_runtime_candidate_records(
            lookup_code,
            raw_candidates,
            stage=stage,
            priority_lookup_code=priority_lookup_code,
            char_sort_weight_by_text=getattr(self, "_char_sort_weight_by_text", {}),
            local_phrase_priority_rules=getattr(self, "_local_phrase_priority_rules", {}),
            continuous_input_priority_rules=getattr(self, "_continuous_input_priority_rules", {}),
        )

    def _rank_runtime_candidates(
        self,
        candidates: List[RuntimeCandidateRecord],
    ) -> List[RuntimeCandidateRecord]:
        return rank_runtime_candidates(candidates, self._user_freq_by_candidate)
