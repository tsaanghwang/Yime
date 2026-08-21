"""Classify source-attested neutral tones before formal Yinjie encoding.

The policy deliberately stores no Yinyuan IDs or codes.  A regular neutral
tone is admitted when the same surface syllable has an attested lexical tone
in the current inventory.  A neutral-only form must be explicitly reviewed as
an exception.  Both routes still use :class:`YinjieEncoder` for the actual
four-Yinyuan encoding.
"""

from __future__ import annotations

import json
from dataclasses import dataclass
from pathlib import Path
from typing import Iterable, Mapping


REGULAR_NEUTRAL_ENCODING_RULE = "ENC-NEUTRAL-REGULAR-DERIVATION"
SPECIAL_NEUTRAL_ENCODING_RULE = "ENC-NEUTRAL-SPECIAL-EXCEPTION"
DEFAULT_NEUTRAL_EXCEPTION_PATH = (
    Path(__file__).resolve().parents[2]
    / "internal_data"
    / "pinyin_source_db"
    / "neutral_tone_encoding_exceptions.json"
)


@dataclass(frozen=True)
class NeutralToneException:
    syllable: str
    status: str
    rule_id: str
    decision_basis: str
    evidence: tuple[Mapping[str, str], ...]


@dataclass(frozen=True)
class NeutralToneResolution:
    syllable: str
    kind: str
    rule_id: str = ""
    lexical_tone_siblings: tuple[str, ...] = ()

    @property
    def admitted(self) -> bool:
        return self.kind in {"regular", "special_exception"}


def is_neutral_syllable(syllable: str) -> bool:
    return len(syllable) >= 2 and syllable.endswith("5")


def lexical_tone_siblings(
    syllable: str,
    inventory: Iterable[str],
) -> tuple[str, ...]:
    if not is_neutral_syllable(syllable):
        return ()
    inventory_set = inventory if isinstance(inventory, (set, frozenset)) else set(inventory)
    base = syllable[:-1]
    return tuple(
        f"{base}{tone}"
        for tone in range(1, 5)
        if f"{base}{tone}" in inventory_set
    )


def load_neutral_tone_exceptions(
    path: Path = DEFAULT_NEUTRAL_EXCEPTION_PATH,
) -> dict[str, NeutralToneException]:
    payload = json.loads(path.read_text(encoding="utf-8"))
    if payload.get("schema_version") != "neutral-tone-encoding-exceptions-v1":
        raise ValueError(f"unsupported neutral-tone exception schema: {path}")

    prohibited = {"yinyuan_ids", "symbol_code", "yime_code", "layout_key", "vk_key"}
    result: dict[str, NeutralToneException] = {}
    raw_exceptions = payload.get("exceptions", {})
    if not isinstance(raw_exceptions, dict):
        raise ValueError(f"neutral-tone exceptions must be an object: {path}")

    for raw_syllable, raw_entry in raw_exceptions.items():
        syllable = str(raw_syllable).strip()
        if not is_neutral_syllable(syllable):
            raise ValueError(f"neutral-tone exception is not a *5 syllable: {syllable}")
        if not isinstance(raw_entry, dict):
            raise ValueError(f"invalid neutral-tone exception: {syllable}")
        occupied = prohibited & set(raw_entry)
        if occupied:
            raise ValueError(
                f"neutral-tone exception {syllable} contains forbidden fields: "
                f"{sorted(occupied)}"
            )
        status = str(raw_entry.get("status", "")).strip()
        rule_id = str(raw_entry.get("rule_id", "")).strip()
        decision_basis = str(raw_entry.get("decision_basis", "")).strip()
        raw_evidence = raw_entry.get("evidence", [])
        if status != "approved" or rule_id != SPECIAL_NEUTRAL_ENCODING_RULE:
            raise ValueError(f"neutral-tone exception is not approved: {syllable}")
        if not decision_basis or not isinstance(raw_evidence, list) or not raw_evidence:
            raise ValueError(f"neutral-tone exception lacks evidence: {syllable}")
        evidence: list[Mapping[str, str]] = []
        for item in raw_evidence:
            if not isinstance(item, dict):
                raise ValueError(f"invalid evidence for neutral-tone exception: {syllable}")
            evidence.append({str(key): str(value) for key, value in item.items()})
        result[syllable] = NeutralToneException(
            syllable=syllable,
            status=status,
            rule_id=rule_id,
            decision_basis=decision_basis,
            evidence=tuple(evidence),
        )
    return result


class NeutralToneEncodingPolicy:
    """Resolve attested neutral tones to a regular or reviewed encoding route."""

    def __init__(
        self,
        inventory: Iterable[str],
        exceptions: Mapping[str, NeutralToneException] | None = None,
    ) -> None:
        self.inventory = frozenset(str(item) for item in inventory)
        self.exceptions = dict(
            load_neutral_tone_exceptions() if exceptions is None else exceptions
        )

    def resolve(self, syllable: str) -> NeutralToneResolution:
        normalized = str(syllable).strip()
        if not is_neutral_syllable(normalized):
            return NeutralToneResolution(normalized, "not_neutral")

        siblings = lexical_tone_siblings(normalized, self.inventory)
        if siblings:
            return NeutralToneResolution(
                normalized,
                "regular",
                REGULAR_NEUTRAL_ENCODING_RULE,
                siblings,
            )

        exception = self.exceptions.get(normalized)
        if exception is not None and exception.status == "approved":
            return NeutralToneResolution(
                normalized,
                "special_exception",
                exception.rule_id,
            )

        return NeutralToneResolution(normalized, "unhandled")

    def require_admitted(self, syllable: str) -> NeutralToneResolution:
        resolution = self.resolve(syllable)
        if not resolution.admitted:
            raise ValueError(f"unhandled source-attested neutral syllable: {syllable}")
        return resolution


__all__ = [
    "DEFAULT_NEUTRAL_EXCEPTION_PATH",
    "NeutralToneEncodingPolicy",
    "NeutralToneException",
    "NeutralToneResolution",
    "REGULAR_NEUTRAL_ENCODING_RULE",
    "SPECIAL_NEUTRAL_ENCODING_RULE",
    "is_neutral_syllable",
    "lexical_tone_siblings",
    "load_neutral_tone_exceptions",
]
