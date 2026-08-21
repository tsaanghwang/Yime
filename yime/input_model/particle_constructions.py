"""Policy-backed evidence for Mandarin particle construction components."""

from __future__ import annotations

import json
from dataclasses import asdict, dataclass
from enum import StrEnum
from functools import lru_cache
from pathlib import Path
from typing import Any, Iterable


DEFAULT_POLICY_PATH = (
    Path(__file__).resolve().parents[2]
    / "internal_data"
    / "particle_construction_policy.json"
)


class ParticleSystem(StrEnum):
    STRUCTURAL = "structural_particles"
    ASPECTUAL = "aspectual_particles"
    MODAL = "modal_particles"


@dataclass(frozen=True)
class ParticleConstructionEvidence:
    system: ParticleSystem
    construction_id: str
    marker: str
    numeric_pinyin: str
    marker_index: int
    attachment: str
    left_requirement: str
    right_requirement: str
    interface: str

    def to_dict(self) -> dict[str, Any]:
        payload = asdict(self)
        payload["system"] = self.system.value
        return payload


@dataclass(frozen=True)
class ParticleConstructionReview:
    text: str
    numeric_pinyin: str
    evidence: tuple[ParticleConstructionEvidence, ...]
    suggested_role: str
    theoretical_basis: str

    @property
    def systems(self) -> tuple[str, ...]:
        return tuple(sorted({item.system.value for item in self.evidence}))

    @property
    def construction_ids(self) -> tuple[str, ...]:
        return tuple(sorted({item.construction_id for item in self.evidence}))

    @property
    def interfaces(self) -> tuple[str, ...]:
        return tuple(sorted({item.interface for item in self.evidence}))


@lru_cache(maxsize=8)
def load_particle_construction_policy(
    path: Path = DEFAULT_POLICY_PATH,
) -> dict[str, Any]:
    payload = json.loads(path.read_text(encoding="utf-8"))
    if payload.get("schema_version") != 1:
        raise ValueError("unsupported particle construction policy schema")
    safeguards = payload.get("safeguards", {})
    required = (
        "source_readings_only",
        "lexical_decisions_override_construction_inference",
        "homographs_require_reading_match",
        "typed_interface_required_for_core_admission",
        "frequency_is_utility_not_grammaticality",
    )
    if any(safeguards.get(key) is not True for key in required):
        raise ValueError("particle policy is missing a required safeguard")
    return payload


def _tokens(numeric_pinyin: str) -> tuple[str, ...]:
    return tuple(token for token in str(numeric_pinyin).split() if token)


def classify_particle_constructions(
    text: str,
    numeric_pinyin: str,
    *,
    policy_path: Path = DEFAULT_POLICY_PATH,
) -> tuple[ParticleConstructionEvidence, ...]:
    """Return possible typed constructions; never decide lexical identity."""

    normalized = str(text or "").strip()
    readings = _tokens(numeric_pinyin)
    if not normalized or len(readings) != len(normalized):
        return ()
    policy = load_particle_construction_policy(policy_path)
    result: list[ParticleConstructionEvidence] = []
    for system_name, system in policy["systems"].items():
        particle_system = ParticleSystem(system_name)
        for construction_id, config in system["constructions"].items():
            marker = str(config["marker"])
            allowed_readings = set(config["numeric_pinyin"])
            position = str(config["marker_position"])
            for index, (char, reading) in enumerate(zip(normalized, readings)):
                if char != marker or reading not in allowed_readings:
                    continue
                if position == "noninitial" and index == 0:
                    continue
                if position == "final" and index != len(normalized) - 1:
                    continue
                result.append(
                    ParticleConstructionEvidence(
                        system=particle_system,
                        construction_id=str(construction_id),
                        marker=marker,
                        numeric_pinyin=reading,
                        marker_index=index,
                        attachment=str(config["attachment"]),
                        left_requirement=str(config["left_requirement"]),
                        right_requirement=str(config["right_requirement"]),
                        interface=str(config["interface"]),
                    )
                )
    return tuple(
        sorted(
            result,
            key=lambda item: (
                item.marker_index,
                item.system.value,
                item.construction_id,
            ),
        )
    )


def _build_review(
    *,
    text: str,
    numeric_pinyin: str,
    evidence: tuple[ParticleConstructionEvidence, ...],
    maximum_component_length: int,
) -> ParticleConstructionReview:
    normalized = str(text or "").strip()
    if not normalized:
        raise ValueError("text must be non-empty")
    if maximum_component_length < 1:
        raise ValueError("maximum_component_length must be positive")
    if not evidence:
        role = "unclassified_particle_signal"
        basis = (
            "字形没有得到相同位置、相同来源读音的助词构式支持；"
            "必须按词汇或同形异读项另行审查。"
        )
    elif len(normalized) > maximum_component_length:
        role = "dynamic_sentence_candidate"
        basis = (
            "存在有类型的助词构式证据，但长度超过核心部件上限；"
            "保留为动态恢复与运行回放证据。"
        )
    else:
        systems = {item.system for item in evidence}
        if len(systems) > 1:
            role = "polyfunctional_particle_candidate"
        elif ParticleSystem.STRUCTURAL in systems:
            role = "structural_component_candidate"
        elif ParticleSystem.ASPECTUAL in systems:
            role = "aspectual_component_candidate"
        else:
            role = "modal_component_candidate"
        basis = (
            "来源读音与有类型的助词构式匹配；进入核心的理由是稳定语法接口"
            "和更大单位的组合价值，不是把该字串先验认定为独立词。"
        )
    return ParticleConstructionReview(
        text=normalized,
        numeric_pinyin=str(numeric_pinyin),
        evidence=evidence,
        suggested_role=role,
        theoretical_basis=basis,
    )


def review_particle_construction(
    text: str,
    numeric_pinyin: str,
    *,
    maximum_component_length: int = 4,
    policy_path: Path = DEFAULT_POLICY_PATH,
) -> ParticleConstructionReview:
    """Explain why a particle-bearing form merits role review, not invalidation."""

    evidence = classify_particle_constructions(
        text,
        numeric_pinyin,
        policy_path=policy_path,
    )
    return _build_review(
        text=text,
        numeric_pinyin=numeric_pinyin,
        evidence=evidence,
        maximum_component_length=maximum_component_length,
    )


def review_particle_construction_readings(
    text: str,
    numeric_pinyin_readings: Iterable[str],
    *,
    maximum_component_length: int = 4,
    policy_path: Path = DEFAULT_POLICY_PATH,
) -> ParticleConstructionReview:
    """Merge construction evidence across attested readings of one text."""

    readings = tuple(
        sorted({str(item).strip() for item in numeric_pinyin_readings if str(item).strip()})
    )
    unique: dict[
        tuple[str, str, int, str],
        ParticleConstructionEvidence,
    ] = {}
    for reading in readings:
        for item in classify_particle_constructions(
            text,
            reading,
            policy_path=policy_path,
        ):
            key = (
                item.system.value,
                item.construction_id,
                item.marker_index,
                item.numeric_pinyin,
            )
            unique[key] = item
    evidence = tuple(
        sorted(
            unique.values(),
            key=lambda item: (
                item.marker_index,
                item.system.value,
                item.construction_id,
            ),
        )
    )
    return _build_review(
        text=text,
        numeric_pinyin="; ".join(readings),
        evidence=evidence,
        maximum_component_length=maximum_component_length,
    )
