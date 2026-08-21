#!/usr/bin/env python3
"""Compare a read-only layout draft with the approved Windows layout."""

from __future__ import annotations

import argparse
import csv
import hashlib
import json
import sys
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Iterable

REPO_ROOT = Path(__file__).resolve().parents[2]
if str(REPO_ROOT) not in sys.path:
    sys.path.insert(0, str(REPO_ROOT))

from tools.evaluation.context import file_sha256, load_evaluation_context
from yime.utils.yinyuan_id_chain import expected_yinyuan_ids, load_shared_layout_groups


CANDIDATE_SELECTION_TOKENS = set("!@#$%^&*(")
LEFT_KEYS = set("`12345qwertasdfgzxcvb")
FINGER_BY_KEY = {
    **{key: "lp" for key in "`1qaz"},
    **{key: "lr" for key in "2wsx"},
    **{key: "lm" for key in "3edc"},
    **{key: "li" for key in "45rfvtgb"},
    **{key: "ri" for key in "67yuhjnm"},
    **{key: "rm" for key in "8ik,"},
    **{key: "rr" for key in "9ol."},
    **{key: "rp" for key in "0-p[]\\;'/="},
}
ROW_EFFORT = {"number": 1.25, "top": 1.05, "home": 1.0, "bottom": 1.15}


@dataclass(frozen=True)
class LayoutProjection:
    id_to_token: dict[str, str]
    id_to_slot: dict[str, dict[str, Any]]
    digest: str


def _load_json(path: Path) -> dict[str, Any]:
    value = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(value, dict):
        raise ValueError(f"layout root must be an object: {path}")
    return value


def _slot_identity(entry: dict[str, Any]) -> tuple[object, ...]:
    return tuple(
        entry.get(field)
        for field in (
            "order",
            "row",
            "physical_key",
            "output_layer",
            "display_label",
        )
    )


def validate_candidate_shape(
    candidate: dict[str, Any], canonical: dict[str, Any]
) -> None:
    if {key: value for key, value in candidate.items() if key != "layers"} != {
        key: value for key, value in canonical.items() if key != "layers"
    }:
        raise ValueError("layout draft changed metadata or shared layout policy")
    candidate_layers = candidate.get("layers")
    canonical_layers = canonical.get("layers")
    if not isinstance(candidate_layers, list) or not isinstance(canonical_layers, list):
        raise ValueError("candidate and canonical layouts must contain layers arrays")
    if len(candidate_layers) != len(canonical_layers):
        raise ValueError("layout draft changed the physical slot count")
    for index, (raw_candidate, raw_canonical) in enumerate(
        zip(candidate_layers, canonical_layers, strict=True)
    ):
        if not isinstance(raw_candidate, dict) or not isinstance(raw_canonical, dict):
            raise ValueError(f"layout slot {index} is not an object")
        if _slot_identity(raw_candidate) != _slot_identity(raw_canonical):
            raise ValueError(f"layout draft changed physical slot identity at index {index}")
        if {
            key: value for key, value in raw_candidate.items() if key != "yinyuan_id"
        } != {
            key: value for key, value in raw_canonical.items() if key != "yinyuan_id"
        }:
            raise ValueError(
                f"layout draft changed a non-assignment field at index {index}"
            )
        if (
            str(raw_candidate.get("output_layer") or "") == "altgr"
            or str(raw_candidate.get("display_label") or "")
            in CANDIDATE_SELECTION_TOKENS
        ) and raw_candidate.get("yinyuan_id") != raw_canonical.get("yinyuan_id"):
            raise ValueError(f"layout draft changed a locked slot at index {index}")
    if candidate.get("shared_yinyuan_key_groups") != canonical.get(
        "shared_yinyuan_key_groups"
    ):
        raise ValueError("layout draft changed the reviewed shared-key groups")


def project_layout(payload: dict[str, Any]) -> LayoutProjection:
    layers = payload.get("layers")
    if not isinstance(layers, list):
        raise ValueError("layout has no layers array")
    id_to_token: dict[str, str] = {}
    id_to_slot: dict[str, dict[str, Any]] = {}
    occupied_tokens: set[str] = set()
    for raw_entry in layers:
        if not isinstance(raw_entry, dict):
            continue
        yinyuan_id = str(raw_entry.get("yinyuan_id") or "")
        if not yinyuan_id:
            continue
        token = str(raw_entry.get("display_label") or "")
        layer = str(raw_entry.get("output_layer") or "")
        if yinyuan_id not in expected_yinyuan_ids():
            raise ValueError(f"unknown Yinyuan ID in layout draft: {yinyuan_id}")
        if layer not in {"base", "shift"} or len(token) != 1:
            raise ValueError(f"Yinyuan ID has an invalid physical slot: {yinyuan_id}")
        if yinyuan_id in id_to_token or token in occupied_tokens:
            raise ValueError(f"duplicate Yinyuan ID or key token: {yinyuan_id}/{token}")
        id_to_token[yinyuan_id] = token
        id_to_slot[yinyuan_id] = raw_entry
        occupied_tokens.add(token)

    for owner, members in load_shared_layout_groups(payload).items():
        if owner not in id_to_token:
            raise ValueError(f"shared-key owner has no slot: {owner}")
        for member in members:
            if member == owner:
                continue
            if member in id_to_token:
                raise ValueError(f"shared-key member has an independent slot: {member}")
            id_to_token[member] = id_to_token[owner]
            id_to_slot[member] = id_to_slot[owner]
    if set(id_to_token) != expected_yinyuan_ids():
        missing = sorted(expected_yinyuan_ids() - set(id_to_token))
        raise ValueError("layout draft does not cover all Yinyuan IDs: " + ", ".join(missing))
    normalized = json.dumps(
        sorted(id_to_token.items()), ensure_ascii=False, separators=(",", ":")
    ).encode("utf-8")
    return LayoutProjection(id_to_token, id_to_slot, hashlib.sha256(normalized).hexdigest())


def _transition_metrics(ids: Iterable[str], projection: LayoutProjection) -> tuple[int, int, float]:
    slots = [projection.id_to_slot[item] for item in ids]
    hands = [
        "left" if str(slot.get("physical_key") or "").lower() in LEFT_KEYS else "right"
        for slot in slots
    ]
    fingers = [FINGER_BY_KEY.get(str(slot.get("physical_key") or "").lower(), "") for slot in slots]
    alternations = sum(left != right for left, right in zip(hands, hands[1:]))
    same_finger = sum(
        bool(left) and left == right for left, right in zip(fingers, fingers[1:])
    )
    effort = sum(
        ROW_EFFORT.get(str(slot.get("row") or ""), 1.0)
        + (0.7 if str(slot.get("output_layer") or "") == "shift" else 0.0)
        for slot in slots
    )
    return alternations, same_finger, effort


def _load_frequencies(path: Path | None) -> dict[str, float]:
    if path is None:
        return {}
    result: dict[str, float] = {}
    with path.open(encoding="utf-8", newline="") as stream:
        for row in csv.DictReader(stream, delimiter="\t"):
            pinyin = str(row.get("pinyin_tone") or "").strip()
            if not pinyin:
                continue
            result[pinyin] = float(row.get("frequency") or 0.0)
    return result


def summarize_layout(
    projection: LayoutProjection,
    *,
    inventory_path: Path,
    frequencies: dict[str, float],
    included_pinyin: set[str],
) -> dict[str, object]:
    total_weight = 0.0
    weighted_effort = 0.0
    weighted_alternation = 0.0
    weighted_same_finger = 0.0
    syllable_count = 0
    with inventory_path.open(encoding="utf-8", newline="") as stream:
        for row in csv.DictReader(stream, delimiter="\t"):
            pinyin = str(row.get("pinyin_tone") or "").strip()
            if pinyin not in included_pinyin:
                continue
            ids = tuple(
                str(row.get(field) or "")
                for field in ("shouyin_id", "huyin_id", "zhuyin_id", "moyin_id")
            )
            if not pinyin or any(item not in projection.id_to_token for item in ids):
                raise ValueError(f"invalid materialized syllable inventory row: {pinyin}")
            weight = frequencies.get(pinyin, 1.0 if not frequencies else 0.0)
            alternations, same_finger, effort = _transition_metrics(ids, projection)
            total_weight += weight
            weighted_effort += weight * effort
            weighted_alternation += weight * alternations
            weighted_same_finger += weight * same_finger
            syllable_count += 1
    if total_weight <= 0:
        raise ValueError("syllable frequency input has no overlap with the formal inventory")
    return {
        "syllable_count": syllable_count,
        "frequency_weight_sum": total_weight,
        "mean_effort_per_syllable": weighted_effort / total_weight,
        "mean_hand_alternations_per_syllable": weighted_alternation / total_weight,
        "mean_same_finger_transitions_per_syllable": weighted_same_finger / total_weight,
    }


def verify_materialized_projection(
    projection: LayoutProjection,
    *,
    inventory_path: Path,
    pinyin_codes_path: Path,
) -> set[str]:
    materialized: dict[str, str] = {}
    with inventory_path.open(encoding="utf-8", newline="") as stream:
        for row in csv.DictReader(stream, delimiter="\t"):
            pinyin = str(row.get("pinyin_tone") or "").strip()
            ids = tuple(
                str(row.get(field) or "")
                for field in ("shouyin_id", "huyin_id", "zhuyin_id", "moyin_id")
            )
            projected = "".join(projection.id_to_token[item] for item in ids)
            if projected != str(row.get("layout_code") or ""):
                raise ValueError(f"materialized canonical layout code drifted: {pinyin}")
            materialized[pinyin] = projected
    packaged: dict[str, str] = {}
    with pinyin_codes_path.open(encoding="utf-8", newline="") as stream:
        for row in csv.DictReader(stream, delimiter="\t"):
            packaged[str(row.get("pinyin_tone") or "").strip()] = str(
                row.get("full") or ""
            )
    unexpected = sorted(set(packaged) - set(materialized))
    mismatches = sorted(
        pinyin
        for pinyin in set(packaged) & set(materialized)
        if packaged[pinyin] != materialized[pinyin]
    )
    if unexpected or mismatches:
        raise ValueError(
            "packaged Pinyin code map differs from the formal inventory: "
            f"unexpected={unexpected}, mismatches={mismatches}"
        )
    return set(packaged)


def compare_layouts(
    candidate_path: Path,
    *,
    frequency_path: Path | None = None,
) -> tuple[dict[str, object], dict[str, object]]:
    context = load_evaluation_context()
    canonical = _load_json(context.canonical_layout_path)
    candidate = _load_json(candidate_path)
    validate_candidate_shape(candidate, canonical)
    canonical_projection = project_layout(canonical)
    candidate_projection = project_layout(candidate)
    if canonical_projection.digest != context.layout_projection_sha256:
        raise ValueError("canonical layout digest left the approved target")
    frequencies = _load_frequencies(frequency_path)
    inventory = REPO_ROOT / "internal_data" / "yime_syllable_decomposition.tsv"
    with inventory.open(encoding="utf-8", newline="") as stream:
        formal_pinyin = {
            str(row.get("pinyin_tone") or "").strip()
            for row in csv.DictReader(stream, delimiter="\t")
        }
    packaged_pinyin = verify_materialized_projection(
        canonical_projection,
        inventory_path=inventory,
        pinyin_codes_path=context.artifacts["canonical_pinyin_code_map"],
    )
    baseline = summarize_layout(
        canonical_projection,
        inventory_path=inventory,
        frequencies=frequencies,
        included_pinyin=packaged_pinyin,
    )
    trial = summarize_layout(
        candidate_projection,
        inventory_path=inventory,
        frequencies=frequencies,
        included_pinyin=packaged_pinyin,
    )
    changes = []
    canonical_layers = {
        int(item["order"]): item
        for item in canonical["layers"]
        if isinstance(item, dict)
    }
    for item in candidate["layers"]:
        if not isinstance(item, dict):
            continue
        order = int(item["order"])
        before = canonical_layers[order].get("yinyuan_id")
        after = item.get("yinyuan_id")
        if before != after:
            changes.append(
                {
                    "order": order,
                    "physical_key": item.get("physical_key"),
                    "output_layer": item.get("output_layer"),
                    "display_label": item.get("display_label"),
                    "before_yinyuan_id": before,
                    "after_yinyuan_id": after,
                }
            )
    metric_names = (
        "mean_effort_per_syllable",
        "mean_hand_alternations_per_syllable",
        "mean_same_finger_transitions_per_syllable",
    )
    report = {
        "schema_version": "yime-target-locked-layout-experiment-v1",
        "evaluation_identity": context.identity(),
        "candidate_layout": {
            "path": str(candidate_path.resolve()),
            "file_sha256": file_sha256(candidate_path),
            "projection_sha256": candidate_projection.digest,
            "changed_slot_count": len(changes),
        },
        "frequency_source": (
            {"path": str(frequency_path.resolve()), "sha256": file_sha256(frequency_path)}
            if frequency_path
            else {"kind": "uniform_formal_syllable_inventory"}
        ),
        "syllable_inventory_scope": {
            "packaged_pinyin_count": len(packaged_pinyin),
            "excluded_formal_syllables": sorted(formal_pinyin - packaged_pinyin),
        },
        "baseline": baseline,
        "candidate": trial,
        "delta": {
            name: float(trial[name]) - float(baseline[name]) for name in metric_names
        },
        "canonical_layout_written": False,
    }
    patch = {
        "schema_version": "yime-layout-candidate-patch-v1",
        "base_layout_projection_sha256": canonical_projection.digest,
        "candidate_layout_projection_sha256": candidate_projection.digest,
        "changes": changes,
        "application": (
            "Review this proposal, edit only internal_data/manual_key_layout.json, "
            "then run the layout lock. This file is never applied automatically."
        ),
    }
    return report, patch


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--candidate-layout", type=Path, required=True)
    parser.add_argument("--syllable-frequency", type=Path)
    parser.add_argument(
        "--output-dir",
        type=Path,
        default=REPO_ROOT / ".generated" / "evaluation" / "layout_experiment",
    )
    args = parser.parse_args()
    report, patch = compare_layouts(
        args.candidate_layout.resolve(),
        frequency_path=(args.syllable_frequency.resolve() if args.syllable_frequency else None),
    )
    args.output_dir.mkdir(parents=True, exist_ok=True)
    (args.output_dir / "report.json").write_text(
        json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
    )
    (args.output_dir / "candidate.patch.json").write_text(
        json.dumps(patch, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
    )
    print(json.dumps(report, ensure_ascii=False, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
