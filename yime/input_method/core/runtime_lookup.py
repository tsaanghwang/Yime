from __future__ import annotations

from dataclasses import dataclass
from typing import List


RECENT_SYLLABLE_PREFIX_CANDIDATE_LIMIT = 64
LONG_CONTEXT_PREFIX_1_CANDIDATE_LIMIT = 32
LONG_CONTEXT_PREFIX_2_CANDIDATE_LIMIT = 24
LONG_CONTEXT_PREFIX_3_CANDIDATE_LIMIT = 16


@dataclass(frozen=True)
class RuntimeLookupPlan:
    """Resolved runtime lookup target for the current input buffer."""

    stage: str
    phrase_prefix_pool: str
    phrase_prefix_limit: int
    lookup_code: str
    context_code: str
    active_code: str
    syllable_count: int
    trailing_code_count: int
    truncated_to_recent: bool
    phrase_mode: bool


def split_complete_syllables(canonical: str) -> List[str]:
    complete_length = (len(canonical) // 4) * 4
    return [canonical[index:index + 4] for index in range(0, complete_length, 4)]


def resolve_long_context_prefix_pool(
    recent_syllables: List[str],
    trailing_prefix: str,
) -> tuple[str, str, int]:
    normalized_trailing_prefix = str(trailing_prefix or "").strip()
    if not normalized_trailing_prefix:
        return "", "", 0

    window_syllable_count = min(max(len(recent_syllables), 1), 3)
    if window_syllable_count == 1:
        return (
            "long-context-prefix-1",
            recent_syllables[-1] + normalized_trailing_prefix,
            LONG_CONTEXT_PREFIX_1_CANDIDATE_LIMIT,
        )
    if window_syllable_count == 2:
        return (
            "long-context-prefix-2",
            "".join(recent_syllables[-2:]) + normalized_trailing_prefix,
            LONG_CONTEXT_PREFIX_2_CANDIDATE_LIMIT,
        )
    return (
        "long-context-prefix-3",
        "".join(recent_syllables[-3:]) + normalized_trailing_prefix,
        LONG_CONTEXT_PREFIX_3_CANDIDATE_LIMIT,
    )


def build_runtime_lookup_plan(canonical: str) -> RuntimeLookupPlan:
    syllables = split_complete_syllables(canonical)
    trailing_code_count = len(canonical) % 4
    if not syllables:
        return RuntimeLookupPlan(
            stage="A",
            phrase_prefix_pool="",
            phrase_prefix_limit=0,
            lookup_code="",
            context_code=canonical,
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
            stage="D",
            phrase_prefix_pool="",
            phrase_prefix_limit=0,
            lookup_code="".join(recent_syllables),
            context_code="".join(recent_syllables),
            active_code="".join(recent_syllables),
            syllable_count=len(recent_syllables),
            trailing_code_count=0,
            truncated_to_recent=truncated_to_recent,
            phrase_mode=True,
        )

    if trailing_code_count == 0:
        lookup_code = recent_syllables[-1]
        return RuntimeLookupPlan(
            stage="B",
            phrase_prefix_pool="recent-syllable-prefix",
            phrase_prefix_limit=RECENT_SYLLABLE_PREFIX_CANDIDATE_LIMIT,
            lookup_code=lookup_code,
            context_code=lookup_code,
            active_code=lookup_code,
            syllable_count=1,
            trailing_code_count=0,
            truncated_to_recent=truncated_to_recent,
            phrase_mode=False,
        )

    lookup_code = recent_syllables[-1]
    trailing_prefix = canonical[len(syllables) * 4 :]
    phrase_prefix_pool, context_code, phrase_prefix_limit = resolve_long_context_prefix_pool(
        recent_syllables,
        trailing_prefix,
    )

    return RuntimeLookupPlan(
        stage="C",
        phrase_prefix_pool=phrase_prefix_pool,
        phrase_prefix_limit=phrase_prefix_limit,
        lookup_code=lookup_code,
        context_code=context_code,
        active_code=lookup_code,
        syllable_count=len(recent_syllables),
        trailing_code_count=trailing_code_count,
        truncated_to_recent=truncated_to_recent,
        phrase_mode=False,
    )


def build_runtime_mode_hint(canonical: str, plan: RuntimeLookupPlan) -> str:
    if plan.trailing_code_count and canonical:
        completed = len(split_complete_syllables(canonical))
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


def should_expand_phrase_prefix(plan: RuntimeLookupPlan) -> bool:
    return plan.stage == "B" and len(plan.lookup_code) == 4


def build_phrase_tree_lookup(canonical: str, plan: RuntimeLookupPlan) -> str:
    normalized_canonical = str(canonical or "").strip()
    if not normalized_canonical:
        return ""
    if len(normalized_canonical) < 4:
        return normalized_canonical
    if plan.stage == "C":
        return plan.context_code
    if should_expand_phrase_prefix(plan):
        return plan.lookup_code
    if plan.trailing_code_count <= 0:
        return ""

    completed_syllables = split_complete_syllables(normalized_canonical)
    trailing_prefix = normalized_canonical[len(completed_syllables) * 4 :]
    if not trailing_prefix:
        return ""
    return "".join(completed_syllables[-3:]) + trailing_prefix
