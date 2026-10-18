"""Fail closed when a keyboard-layout change bypasses the semantic chain."""

from __future__ import annotations

import argparse
import csv
import hashlib
import json
import sys
from dataclasses import asdict
from pathlib import Path
from typing import Any, cast


ROOT = Path(__file__).resolve().parent.parent
if str(ROOT) not in sys.path:
    sys.path.insert(0, str(ROOT))

from syllable.codec.yinjie_encoder import YinjieEncoder
from tools.resolve_manual_key_layout import build_resolved_layout
from yime.asset_paths import resolve_lexicon_source_db_path
from yime.utils.yinyuan_id_chain import (
    encode_numeric_pinyin_to_yinyuan_ids,
    load_semantic_yinyuan_registry,
    load_symbol_to_yinyuan_id,
    load_yinyuan_id_to_layout_key,
    layout_projection_digest,
    symbol_code_to_yinyuan_ids,
)
from yime.utils.syllable_encoding_provenance import (
    SyllableEncodingProvenanceRow,
    build_syllable_encoding_provenance_rows,
    load_rule_catalog,
    load_source_attestations,
)


LOCK_PATH = Path("internal_data/layout_change_lock.json")
LAYOUT_PATH = Path("internal_data/manual_key_layout.json")
RESOLVED_LAYOUT_PATH = Path("internal_data/manual_key_layout.resolved.json")
PACKAGED_LAYOUT_PATH = Path(
    "go-backend/input_methods/yime/data/yime_yinyuan_layout.json"
)
TARGET_LOCK_PATH = Path("tools/lexicon/data/yime_core_target.lock.json")
CANONICAL_SYMBOL_PATH = Path("internal_data/key_to_symbol.json")
PINYIN_INVENTORY_PATH = Path(
    "internal_data/pinyin_source_db/lexicon_exports/pinyin_normalized.json"
)
YINJIE_CODE_PATH = Path("syllable/codec/yinjie_code.json")
SYLLABLE_RULE_CATALOG_PATH = Path("internal_data/syllable_encoding_rule_catalog.json")
SYLLABLE_PROVENANCE_PATH = Path("internal_data/yime_syllable_encoding_provenance.tsv")


def _load_json(path: Path) -> dict[str, Any]:
    return cast(dict[str, Any], json.loads(path.read_text(encoding="utf-8")))


def semantic_registry_digest(repo_root: Path = ROOT) -> str:
    registry = load_semantic_yinyuan_registry(repo_root)
    protected_rows = [
        {
            "yinyuan_id": yinyuan_id,
            "category": entry["category"],
            "label": entry["label"],
            "semantic_code": entry["semantic_code"],
            "runtime_codepoint": f"U+{ord(entry['runtime_char']):04X}",
        }
        for yinyuan_id, entry in sorted(registry.items())
    ]
    serialized = json.dumps(
        protected_rows,
        ensure_ascii=False,
        sort_keys=True,
        separators=(",", ":"),
    ).encode("utf-8")
    return hashlib.sha256(serialized).hexdigest()


def pinyin_yinyuan_chain_digest(repo_root: Path = ROOT) -> str:
    """Digest every reviewed numeric-Pinyin -> four-Yinyuan-ID result."""
    inventory = _load_json(repo_root / PINYIN_INVENTORY_PATH)
    encoder = YinjieEncoder()
    protected_rows = [
        [
            pinyin_tone,
            *encode_numeric_pinyin_to_yinyuan_ids(
                pinyin_tone,
                repo_root=repo_root,
                encoder=encoder,
            ),
        ]
        for pinyin_tone in sorted(inventory)
    ]
    serialized = json.dumps(
        protected_rows,
        ensure_ascii=False,
        separators=(",", ":"),
    ).encode("utf-8")
    return hashlib.sha256(serialized).hexdigest()


def syllable_rule_catalog_digest(repo_root: Path = ROOT) -> str:
    catalog = load_rule_catalog(repo_root / SYLLABLE_RULE_CATALOG_PATH)
    serialized = json.dumps(
        catalog,
        ensure_ascii=False,
        sort_keys=True,
        separators=(",", ":"),
    ).encode("utf-8")
    return hashlib.sha256(serialized).hexdigest()


def _load_committed_syllable_provenance_rows(
    repo_root: Path,
) -> list[dict[str, Any]]:
    """Load the locked audit artifact without treating it as a production source."""
    path = repo_root / SYLLABLE_PROVENANCE_PATH
    expected_fields = list(SyllableEncodingProvenanceRow.__dataclass_fields__)
    with path.open("r", encoding="utf-8", newline="") as file:
        reader = csv.DictReader(file, delimiter="\t")
        if reader.fieldnames != expected_fields:
            raise ValueError(
                "syllable provenance audit has unexpected columns: "
                f"expected {expected_fields}, got {reader.fieldnames}"
            )
        rows: list[dict[str, Any]] = []
        for line_number, raw in enumerate(reader, start=2):
            reviewed_patch = raw["reviewed_patch"]
            if reviewed_patch not in {"True", "False"}:
                raise ValueError(
                    "syllable provenance audit has invalid reviewed_patch "
                    f"at line {line_number}: {reviewed_patch!r}"
                )
            parsed = dict(raw)
            parsed["char_occurrences"] = int(raw["char_occurrences"])
            parsed["phrase_occurrences"] = int(raw["phrase_occurrences"])
            parsed["reviewed_patch"] = reviewed_patch == "True"
            rows.append(asdict(SyllableEncodingProvenanceRow(**parsed)))
    return rows


def _syllable_provenance_rows(repo_root: Path) -> list[dict[str, Any]]:
    source_db = resolve_lexicon_source_db_path(repo_root)
    if not source_db.is_file():
        # A clean checkout intentionally has no multi-gigabyte generated source
        # database. In that environment, verify the committed audit through its
        # locked digest. When the production database exists, the branch below
        # still regenerates every row from the canonical source.
        return _load_committed_syllable_provenance_rows(repo_root)

    inventory = cast(
        dict[str, str],
        _load_json(repo_root / PINYIN_INVENTORY_PATH),
    )
    attestations = load_source_attestations(
        char_source_path=repo_root / "internal_data/hanzi_pinyin/pinyin.txt",
        phrase_source_path=repo_root / "internal_data/phrase_pinyin/phrase_pinyin.txt",
        patch_path=repo_root / "internal_data/pinyin_source_db/pinyin_normalized_patch.json",
    )
    catalog = load_rule_catalog(repo_root / SYLLABLE_RULE_CATALOG_PATH)
    return [
        asdict(row)
        for row in build_syllable_encoding_provenance_rows(
            inventory,
            attestations=attestations,
            catalog=catalog,
            repo_root=repo_root,
        )
    ]


def syllable_provenance_digest(repo_root: Path = ROOT) -> str:
    serialized = json.dumps(
        _syllable_provenance_rows(repo_root),
        ensure_ascii=False,
        sort_keys=True,
        separators=(",", ":"),
    ).encode("utf-8")
    return hashlib.sha256(serialized).hexdigest()


def _check_semantic_lock(repo_root: Path, lock: dict[str, Any], issues: list[str]) -> None:
    expected_digest = str(lock.get("semantic_registry_sha256") or "")
    actual_digest = semantic_registry_digest(repo_root)
    if actual_digest != expected_digest:
        issues.append(
            "semantic Yinyuan registry changed during a layout change: "
            f"expected {expected_digest}, got {actual_digest}. "
            "A semantic change requires a separate reviewed change, never a layout shortcut."
        )
    expected_chain_digest = str(lock.get("pinyin_yinyuan_chain_sha256") or "")
    actual_chain_digest = pinyin_yinyuan_chain_digest(repo_root)
    if actual_chain_digest != expected_chain_digest:
        issues.append(
            "numeric-Pinyin -> Yinyuan-ID semantics changed during a layout change: "
            f"expected {expected_chain_digest}, got {actual_chain_digest}. "
            "Do not update this digest as part of a keyboard-layout change."
        )
    expected_catalog_digest = str(lock.get("syllable_rule_catalog_sha256") or "")
    actual_catalog_digest = syllable_rule_catalog_digest(repo_root)
    if actual_catalog_digest != expected_catalog_digest:
        issues.append(
            "syllable encoding rule catalog changed: "
            f"expected {expected_catalog_digest}, got {actual_catalog_digest}. "
            "Review the semantic/provenance rule change separately from keyboard layout."
        )
    expected_provenance_digest = str(lock.get("syllable_provenance_sha256") or "")
    actual_provenance_digest = syllable_provenance_digest(repo_root)
    if actual_provenance_digest != expected_provenance_digest:
        issues.append(
            "syllable source/rule provenance changed: "
            f"expected {expected_provenance_digest}, got {actual_provenance_digest}. "
            "Regenerate the audit and review the upstream semantic change."
        )


def _check_single_layout_source(repo_root: Path, lock: dict[str, Any], issues: list[str]) -> None:
    canonical = str(lock.get("canonical_layout_source") or "")
    if canonical != LAYOUT_PATH.as_posix():
        issues.append(f"lock names an unexpected canonical layout source: {canonical}")
    for relative in cast(list[str], lock.get("forbidden_parallel_layout_sources", [])):
        if (repo_root / relative).exists():
            issues.append(f"parallel layout source is forbidden: {relative}")

    try:
        mapping = load_yinyuan_id_to_layout_key(repo_root)
    except Exception as exc:
        issues.append(f"canonical layout is invalid: {exc}")
        return
    if mapping.get("N25") != "`" or mapping.get("N27") != "`":
        issues.append("backtick must be shared only by N25 [ɥ] and N27 [z]/[ɹ]")
    if mapping.get("N12") != "'" or mapping.get("N26") != "'":
        issues.append("apostrophe must be shared only by N12 and N26 [ŋ]")
    candidate_tokens = set("!@#$%^&*(")
    occupied_candidates = sorted(candidate_tokens & set(mapping.values()))
    if occupied_candidates:
        issues.append(
            "Shift+1 through Shift+9 are candidate actions, not Yinyuan keys: "
            + ", ".join(occupied_candidates)
        )


def _check_resolved_layout(repo_root: Path, issues: list[str]) -> None:
    layout = _load_json(repo_root / LAYOUT_PATH)
    symbols = cast(dict[str, str], _load_json(repo_root / CANONICAL_SYMBOL_PATH))
    expected = build_resolved_layout(layout, symbols)
    resolved_path = repo_root / RESOLVED_LAYOUT_PATH
    if not resolved_path.exists():
        issues.append(f"missing derived layout: {RESOLVED_LAYOUT_PATH.as_posix()}")
        return
    actual = _load_json(resolved_path)
    if actual != expected:
        issues.append(
            "manual_key_layout.resolved.json is stale; run the locked layout pipeline"
        )


def _check_packaged_layout_projection(
    repo_root: Path,
    issues: list[str],
) -> None:
    """Require the Windows projection to be derived from the one editable source."""
    expected = load_yinyuan_id_to_layout_key(repo_root)
    packaged_path = repo_root / PACKAGED_LAYOUT_PATH
    if not packaged_path.is_file():
        issues.append(
            f"missing packaged layout projection: {PACKAGED_LAYOUT_PATH.as_posix()}"
        )
        return
    packaged = _load_json(packaged_path)
    actual = cast(dict[str, str], packaged.get("yinyuan_id_to_key") or {})
    if actual != expected:
        missing = sorted(set(expected) - set(actual))
        extra = sorted(set(actual) - set(expected))
        changed = sorted(
            yinyuan_id
            for yinyuan_id in set(expected) & set(actual)
            if expected[yinyuan_id] != actual[yinyuan_id]
        )
        issues.append(
            "packaged Windows layout is not the canonical projection: "
            f"missing={missing}, extra={extra}, changed={changed}"
        )

    target_lock = _load_json(repo_root / TARGET_LOCK_PATH)
    target = cast(dict[str, Any], target_lock.get("target") or {})
    expected_digest = str(target.get("layout_projection_sha256") or "")
    actual_digest = layout_projection_digest(repo_root)
    if actual_digest != expected_digest:
        issues.append(
            "canonical layout digest does not match the approved Windows target: "
            f"expected {expected_digest}, got {actual_digest}"
        )


def _check_full_pinyin_chain(repo_root: Path, issues: list[str]) -> None:
    inventory = _load_json(repo_root / PINYIN_INVENTORY_PATH)
    codebook = _load_json(repo_root / YINJIE_CODE_PATH)
    if set(inventory) != set(codebook):
        missing = sorted(set(inventory) - set(codebook))[:10]
        extra = sorted(set(codebook) - set(inventory))[:10]
        issues.append(f"pinyin inventory/codebook mismatch: missing={missing}, extra={extra}")
        return

    encoder = YinjieEncoder()
    for pinyin_tone in sorted(inventory):
        try:
            semantic_ids = encode_numeric_pinyin_to_yinyuan_ids(
                pinyin_tone,
                repo_root=repo_root,
                encoder=encoder,
            )
            stored_ids = symbol_code_to_yinyuan_ids(
                str(codebook[pinyin_tone]),
                repo_root=repo_root,
            )
        except Exception as exc:
            issues.append(f"numeric Pinyin chain failed for {pinyin_tone}: {exc}")
            if len(issues) >= 20:
                return
            continue
        mismatch = compare_pinyin_chain_entry(pinyin_tone, semantic_ids, stored_ids)
        if mismatch:
            issues.append(mismatch)
            if len(issues) >= 20:
                return


def _check_syllable_provenance_artifact(repo_root: Path, issues: list[str]) -> None:
    path = repo_root / SYLLABLE_PROVENANCE_PATH
    if not path.exists():
        issues.append(f"missing syllable provenance audit: {SYLLABLE_PROVENANCE_PATH.as_posix()}")
        return
    with path.open("r", encoding="utf-8", newline="") as file:
        actual = list(csv.DictReader(file, delimiter="\t"))
    expected = [
        {key: str(value) for key, value in row.items()}
        for row in _syllable_provenance_rows(repo_root)
    ]
    if actual != expected:
        issues.append(
            "syllable encoding provenance audit is stale; "
            "run tools/export_syllable_decomposition.py and review the rule changes"
        )


def compare_pinyin_chain_entry(
    pinyin_tone: str,
    semantic_ids: tuple[str, ...],
    stored_ids: tuple[str, ...],
) -> str:
    if semantic_ids == stored_ids:
        return ""
    return (
        f"middle-entry code detected for {pinyin_tone}: "
        f"semantic={semantic_ids}, stored={stored_ids}"
    )


def check_layout_change_lock(
    repo_root: Path = ROOT,
    *,
    include_derived_artifacts: bool = True,
) -> list[str]:
    lock = _load_json(repo_root / LOCK_PATH)
    issues: list[str] = []
    _check_semantic_lock(repo_root, lock, issues)
    _check_single_layout_source(repo_root, lock, issues)
    if include_derived_artifacts:
        if (repo_root / RESOLVED_LAYOUT_PATH).is_file():
            _check_resolved_layout(repo_root, issues)
        _check_packaged_layout_projection(repo_root, issues)
    _check_full_pinyin_chain(repo_root, issues)
    _check_syllable_provenance_artifact(repo_root, issues)
    return issues


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Enforce the numeric-Pinyin -> Yinyuan-ID -> canonical-layout chain."
    )
    parser.add_argument("--repo-root", type=Path, default=ROOT)
    parser.add_argument("--print-semantic-digest", action="store_true")
    parser.add_argument("--print-pinyin-chain-digest", action="store_true")
    parser.add_argument("--print-syllable-rule-catalog-digest", action="store_true")
    parser.add_argument("--print-syllable-provenance-digest", action="store_true")
    parser.add_argument(
        "--preflight",
        action="store_true",
        help="Check protected semantics and canonical source before regenerating derived artifacts.",
    )
    args = parser.parse_args()
    repo_root = args.repo_root.resolve()
    if args.print_semantic_digest:
        print(semantic_registry_digest(repo_root))
        return 0
    if args.print_pinyin_chain_digest:
        print(pinyin_yinyuan_chain_digest(repo_root))
        return 0
    if args.print_syllable_rule_catalog_digest:
        print(syllable_rule_catalog_digest(repo_root))
        return 0
    if args.print_syllable_provenance_digest:
        print(syllable_provenance_digest(repo_root))
        return 0
    issues = check_layout_change_lock(
        repo_root,
        include_derived_artifacts=not args.preflight,
    )
    if issues:
        print("layout change lock failed")
        for issue in issues:
            print(f"- {issue}")
        return 1
    print("layout change lock passed")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
