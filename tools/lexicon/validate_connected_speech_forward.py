#!/usr/bin/env python3
"""Read-only, Rime-free forward-source evidence for the 24 reviewed aliases.

This is not an alias generator or an admission decision. It checks reviewed
spellings against the in-repository pronunciation source, then calls the formal
single-syllable encoder before comparing downstream decomposition/layout data.
Only the explicitly requested, fresh outcome file may be written.
"""

from __future__ import annotations

import argparse
import csv
import hashlib
import json
import re
import stat
import sys
from pathlib import Path
from typing import Any, Callable, Iterable

# Set this before importing the formal chain: checking sources must not create
# __pycache__ files anywhere in the repository.
sys.dont_write_bytecode = True
REPO_ROOT = Path(__file__).resolve().parents[2]
REVIEW_IDS = tuple(f"T3-5B-{number:03d}" for number in range(1, 25))
SCHEMA_VERSION = "yimecore-speech-forward-source-v1"
REVIEW_HEADER = (
    "review_id", "text", "canonical_pinyin", "expected_surface_pinyin",
    "stage5a_record_id_snapshot", "priority_weight_snapshot", "evidence_class",
    "prosodic_status", "runtime_status", "source_ids", "note",
)
SOURCE_PATHS = {
    "review": "docs/project/connected_speech/third_tone_stage5b_review.tsv",
    "decisions": "docs/project/connected_speech/third_tone_stage5b_decisions.tsv",
    "rule_sources": "docs/project/connected_speech/third_tone_stage5b_sources.tsv",
    "scope": "docs/project/connected_speech/third_tone_sandhi_scope.tsv",
    "phrase_pronunciations": "internal_data/phrase_pinyin/phrase_pinyin.txt",
    "canonical_inventory": "internal_data/pinyin_source_db/lexicon_exports/pinyin_normalized.json",
    "canonical_decomposition": "internal_data/yime_syllable_decomposition.tsv",
    "packaged_decomposition": "go-backend/input_methods/yime/data/yime_syllable_decomposition.tsv",
    "canonical_layout": "internal_data/manual_key_layout.json",
    "packaged_layout": "go-backend/input_methods/yime/data/yime_yinyuan_layout.json",
    "semantic_initials": "syllable/yinyuan/zaoyin_yinyuan_enhanced.json",
    "semantic_musical": "syllable/yinyuan/yueyin_yinyuan_enhanced.json",
    "canonical_symbols": "internal_data/key_to_symbol.json",
    "initial_codepoints": "syllable/yinyuan/shouyin_codepoint.json",
    "initial_analysis": "syllable/pianyin/zaoyin_pianyin.json",
    "musical_attributes": "syllable/yinyuan/variables_of_attributes.json",
    "pianyin_sequence": "internal_data/yinyuan_derived/ganyin_to_pianyin_sequence.json",
    "marked_finals": "syllable/yinyuan/ganyin.json",
    "neutral_exceptions": "internal_data/pinyin_source_db/neutral_tone_encoding_exceptions.json",
    "formal_pipeline": "syllable/analysis/syllable_encoding_pipeline.py",
    "formal_splitter": "syllable/analysis/syllable_splitter.py",
    "formal_encoder": "syllable/codec/yinjie_encoder.py",
    "formal_initial_encoder": "syllable/analysis/shouyin_encoder.py",
    "formal_initial_source": "syllable/analysis/zaoyin_pianyin_source.py",
    "formal_musical_encoder": "syllable/analysis/ganyin_encoder.py",
    "formal_musical_mapper": "syllable/analysis/yueyin_mapper.py",
    "formal_id_chain": "yime/utils/yinyuan_id_chain.py",
    "validator": "tools/lexicon/validate_connected_speech_forward.py",
}
# The canonical packages import these compatibility/model modules even though
# this checker calls only the single-syllable path. Keep that import closure in
# the receipt too, so a stale proof cannot conceal a later source-code edit.
FORMAL_IMPORT_PATHS = (
    "syllable/__init__.py",
    "syllable/analysis/__init__.py",
    "syllable/analysis/ganyin_categorizer.py",
    "syllable/analysis/ganyin_yinyuan_slots.py",
    "syllable/analysis/segment_split.py",
    "syllable/analysis/syllable.py",
    "syllable/analysis/syllable_analyzer.py",
    "syllable/analysis/syllable_categorizer.py",
    "syllable/codec/__init__.py",
    "syllable/codec/input_shorthand/__init__.py",
    "syllable/codec/input_shorthand/tone_omission.py",
    "syllable/codec/model_full_code/__init__.py",
    "syllable/codec/model_full_code/structure.py",
    "syllable/codec/neutral_tone_encoding.py",
    "syllable/codec/paths.py",
    "syllable/codec/variable_length_yinyuan/__init__.py",
    "syllable/codec/variable_length_yinyuan/transform.py",
    "syllable/codec/yinjie.py",
    "syllable/codec/yinjie_api_manifest.py",
    "syllable/codec/yinjie_decoder.py",
    "yime/__init__.py",
    "yime/utils/__init__.py",
    "yime/utils/backup.py",
    "yime/utils/charfilter.py",
    "yime/utils/marked_pinyin.py",
    "yime/utils/pinyin_normalizer.py",
    "yime/utils/pinyin_zhuyin.py",
    "yime/utils/reverse_key_value_pairs.py",
)
SOURCE_PATHS.update({f"formal_import_{index:02d}": path for index, path in enumerate(FORMAL_IMPORT_PATHS, start=1)})


class ForwardValidationError(ValueError):
    """A privacy-safe, symbolic validation failure (never source text)."""


def _require(condition: bool, code: str) -> None:
    if not condition:
        raise ForwardValidationError(code)


def _no_links(path: Path) -> None:
    """Reject symlinks and Windows reparse points before resolving a path."""
    for component in (*reversed(path.parents), path):
        if not component.exists() and not component.is_symlink():
            continue
        info = component.lstat()
        _require(
            not stat.S_ISLNK(info.st_mode)
            and not (getattr(info, "st_file_attributes", 0) & 0x400),
            "linked_path_rejected",
        )


def _input_path(repo: Path, relative: str) -> Path:
    path = repo / relative
    _no_links(path)
    _require(path.is_file() and path.resolve().is_relative_to(repo), "input_path_rejected")
    return path


def _sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def _reject_duplicate_keys(pairs: list[tuple[str, Any]]) -> dict[str, Any]:
    result: dict[str, Any] = {}
    for key, value in pairs:
        _require(key not in result, "duplicate_json_key")
        result[key] = value
    return result


def _load_json(path: Path) -> dict[str, Any]:
    value = json.loads(path.read_text(encoding="utf-8-sig"), object_pairs_hook=_reject_duplicate_keys)
    _require(isinstance(value, dict), "json_object_required")
    return value


def _read_tsv(path: Path, header: Iterable[str] | None = None) -> list[dict[str, str]]:
    with path.open(encoding="utf-8-sig", newline="") as stream:
        reader = csv.DictReader(stream, delimiter="\t", quoting=csv.QUOTE_NONE)
        _require(reader.fieldnames is not None, "tsv_header_required")
        if header is not None:
            _require(tuple(reader.fieldnames) == tuple(header), "tsv_header_mismatch")
        rows = list(reader)
    _require(all(None not in row and all(value is not None for value in row.values()) for row in rows), "tsv_row_shape")
    return rows


def _review_records(rows: list[dict[str, str]]) -> tuple[list[dict[str, str]], set[str]]:
    _require(len(rows) == 24, "review_record_count")
    _require(sorted(row["review_id"] for row in rows) == list(REVIEW_IDS), "review_id_set")
    _require(len({row["text"] for row in rows}) == 24, "review_duplicate_text")
    syllables: set[str] = set()
    for row in rows:
        _require(len(row["text"]) == 2, "review_text_shape")
        for field in ("canonical_pinyin", "expected_surface_pinyin"):
            value = row[field]
            _require(re.fullmatch(r"[a-züê]+[1-5] [a-züê]+[1-5]", value) is not None, "review_reading_shape")
            syllables.update(value.split(" "))
    _require(len(syllables) == 50, "review_syllable_count")
    return sorted(rows, key=lambda row: row["review_id"]), syllables


def _check_phrase_records(
    rows: list[dict[str, str]],
    source_path: Path,
    normalize: Callable[[str], str],
) -> int:
    wanted = {row["text"]: row for row in rows}
    found: set[str] = set()
    with source_path.open(encoding="utf-8-sig", newline="") as stream:
        reader = csv.DictReader((line for line in stream if not line.startswith("#")), delimiter="\t", quoting=csv.QUOTE_NONE)
        _require(reader.fieldnames == ["phrase", "phrase_len", "common_reading", "readings"], "phrase_header_mismatch")
        for source in reader:
            if source.get("phrase") not in wanted:
                continue
            text = source["phrase"]
            _require(text not in found, "duplicate_phrase_source")
            _require(None not in source and all(value is not None for value in source.values()), "phrase_row_shape")
            _require(source["phrase_len"] == "2", "phrase_length_mismatch")
            expected = wanted[text]["canonical_pinyin"]
            readings = source["readings"].split("|")
            # Do not make the review snapshot the pronunciation source: start
            # with the source's marked syllables and normalize in source order.
            observed = [" ".join(normalize(syllable) for syllable in reading.split()) for reading in readings]
            common = " ".join(normalize(syllable) for syllable in source["common_reading"].split())
            _require(common == expected and expected in observed, "canonical_phrase_source_mismatch")
            found.add(text)
    _require(found == set(wanted), "canonical_phrase_source_missing")
    return len(found)


def _check_decomposition(
    rows: list[dict[str, str]],
    required: set[str],
    encoded: dict[str, tuple[str, ...]],
    inventory: dict[str, str],
    layout: dict[str, str],
) -> int:
    indexed: dict[str, dict[str, str]] = {}
    for row in rows:
        key = row.get("pinyin_tone", "")
        _require(bool(key) and key not in indexed, "decomposition_duplicate_or_missing_key")
        indexed[key] = row
    for syllable in required:
        _require(syllable in indexed, "decomposition_syllable_missing")
        row = indexed[syllable]
        ids = tuple(row.get(field, "") for field in ("shouyin_id", "huyin_id", "zhuyin_id", "moyin_id"))
        _require(len(encoded[syllable]) == 4 and ids == encoded[syllable], "formal_decomposition_mismatch")
        _require(row.get("marked_pinyin") == inventory[syllable] and row.get("status") == "ok", "decomposition_inventory_mismatch")
        _require(row.get("layout_code") == "".join(layout[item] for item in encoded[syllable]), "decomposition_layout_mismatch")
    return len(required)


def _check_semantic_tone_substitutions(
    rows: list[dict[str, str]],
    encoded: dict[str, tuple[str, ...]],
    registry: dict[str, dict[str, str]],
) -> int:
    """Check the reviewed 3+3 -> 2+3 substitution using declared semantics.

    The source registry explicitly identifies quality and grade in semantic_code.
    Neither the spelling/number of a Yinyuan ID nor its projected key is evidence
    for either attribute. Both tuples have already come from the formal encoder.
    """
    attributes: dict[str, tuple[str, str]] = {}
    for unit_id, entry in registry.items():
        if entry.get("category") != "musical":
            continue
        match = re.fullmatch(r"(YPY_[A-Z_]+)_(HIGH|MID|LOW)", entry.get("semantic_code", ""))
        _require(match is not None, "musical_semantic_attributes_missing")
        assert match is not None
        attributes[unit_id] = (match[1], match[2])
    for row in rows:
        canonical_reading = row["canonical_pinyin"].split(" ")
        surface_reading = row["expected_surface_pinyin"].split(" ")
        _require(
            len(canonical_reading) == len(surface_reading) == 2
            and canonical_reading[0].endswith("3")
            and canonical_reading[1].endswith("3")
            and surface_reading[0] == canonical_reading[0][:-1] + "2"
            and surface_reading[1] == canonical_reading[1],
            "reviewed_tone_substitution_scope_mismatch",
        )
        before = encoded[canonical_reading[0]]
        after = encoded[surface_reading[0]]
        _require(len(before) == len(after) == 4, "semantic_tuple_length_mismatch")
        _require(before[0] == after[0], "semantic_initial_changed")
        _require(
            encoded[canonical_reading[1]] == encoded[surface_reading[1]],
            "semantic_second_syllable_changed",
        )
        for position, expected_grade in enumerate(("LOW", "MID", "HIGH"), start=1):
            _require(before[position] in attributes and after[position] in attributes, "semantic_musical_position_missing")
            before_quality, before_grade = attributes[before[position]]
            after_quality, after_grade = attributes[after[position]]
            _require(before_quality == after_quality, "semantic_musical_quality_changed")
            _require(before_grade == "LOW" and after_grade == expected_grade, "semantic_tone_grade_mismatch")
    return len(rows)


def validate_forward_sources(repo_root: Path) -> dict[str, Any]:
    _require(repo_root.is_absolute(), "absolute_repo_required")
    _no_links(repo_root)
    repo = repo_root.resolve(strict=True)
    # The formal encoder is module-relative. Never accept a different input
    # checkout while accidentally encoding against this checkout's internals.
    _require(repo == REPO_ROOT, "repo_must_match_validator_checkout")
    _require((repo / "internal_data/pinyin_source_db").is_dir(), "formal_root_marker_missing")
    paths = {role: _input_path(repo, relative) for role, relative in SOURCE_PATHS.items()}
    before = {role: _sha256(path) for role, path in paths.items()}
    if str(repo) not in sys.path:
        sys.path.insert(0, str(repo))
    # Modules already cached by unrelated code (other tests sharing this
    # process, etc.) are out of scope; only this import's own closure counts.
    modules_before_import = set(sys.modules)
    from syllable.analysis.syllable_encoding_pipeline import SyllableEncodingPipeline
    from syllable.codec.yinjie_encoder import YinjieEncoder
    from yime.utils.yinyuan_id_chain import (
        encode_numeric_pinyin_to_yinyuan_ids,
        load_semantic_yinyuan_registry,
        load_yinyuan_id_to_layout_key,
    )

    declared_python = {path.resolve() for path in paths.values() if path.suffix == ".py"}
    for name in set(sys.modules) - modules_before_import:
        if name in {"syllable", "yime"} or name.startswith(("syllable.", "yime.")):
            module = sys.modules[name]
            filename = getattr(module, "__file__", None)
            _require(bool(filename) and Path(filename).resolve() in declared_python, "formal_import_outside_declared_sources")

    rows, required = _review_records(_read_tsv(paths["review"], REVIEW_HEADER))
    inventory = _load_json(paths["canonical_inventory"])
    _require(all(isinstance(key, str) and isinstance(value, str) for key, value in inventory.items()), "inventory_value_shape")
    _require(required <= inventory.keys(), "syllable_not_in_canonical_inventory")
    phrase_count = _check_phrase_records(rows, paths["phrase_pronunciations"], SyllableEncodingPipeline.normalize_syllable)
    layout = load_yinyuan_id_to_layout_key(repo_root=repo)
    packaged_layout = _load_json(paths["packaged_layout"])
    _require(packaged_layout.get("format_version") == 1 and packaged_layout.get("yinyuan_id_to_key") == layout, "layout_projection_mismatch")
    encoder = YinjieEncoder()
    _require(encoder.project_root.resolve() == repo, "formal_encoder_root_mismatch")
    encoded = {
        syllable: encode_numeric_pinyin_to_yinyuan_ids(syllable, repo_root=repo, encoder=encoder)
        for syllable in sorted(required)
    }
    semantic_count = _check_semantic_tone_substitutions(rows, encoded, load_semantic_yinyuan_registry(repo_root=repo))
    for role in ("canonical_decomposition", "packaged_decomposition"):
        _check_decomposition(_read_tsv(paths[role]), required, encoded, inventory, layout)
    after = {role: _sha256(_input_path(repo, SOURCE_PATHS[role])) for role in paths}
    _require(before == after, "input_changed_during_validation")
    return {
        "schema_version": SCHEMA_VERSION,
        "passed": True,
        "record_count": len(rows),
        "syllable_count": len(required),
        "checks": {
            "canonical_phrase_source": phrase_count == 24,
            "canonical_inventory_membership": True,
            "formal_four_id_decomposition": True,
            "semantic_tone_substitutions": semantic_count == 24,
            "canonical_layout_projection": True,
            "inputs_unchanged": True,
            "rime_executed": False,
            "aliases_generated": False,
        },
        "record_ids": [row["review_id"] for row in rows],
        "input_sha256": {
            SOURCE_PATHS[role]: before[role] for role in sorted(paths)
        },
        "inputs": [
            {"role": role, "path": SOURCE_PATHS[role], "sha256": before[role]}
            for role in sorted(paths)
        ],
    }


def reserve_output(repo: Path, output: Path) -> Path:
    _require(repo.is_absolute() and output.is_absolute(), "absolute_paths_required")
    _no_links(repo)
    _no_links(output)
    resolved_repo = repo.resolve(strict=True)
    expected_parent = resolved_repo / ".tmp" / "yimecore-experiment"
    _require(output.name == "forward-source.json", "output_filename_rejected")
    # _no_links already rejected any symlink in output's ancestry, so resolving
    # here only normalizes case/short-name (e.g. Windows 8.3 "RUNNER~1") drift
    # against the already-resolved expected_parent, not a symlink escape.
    _require(output.parent.parent.resolve() == expected_parent, "output_parent_rejected")
    _require(re.fullmatch(r"speech-admission-[A-Za-z0-9][A-Za-z0-9-]{7,100}", output.parent.name) is not None, "output_directory_rejected")
    _require(not output.parent.exists(), "output_directory_must_be_new")
    expected_parent.mkdir(parents=True, exist_ok=True)
    _no_links(expected_parent)
    output.parent.mkdir(exist_ok=False)
    _no_links(output.parent)
    return output


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--repo", required=True, type=Path)
    parser.add_argument("--output", required=True, type=Path)
    args = parser.parse_args(argv)
    try:
        # Validate root identity before making even an isolated output folder.
        _require(args.repo.is_absolute(), "absolute_repo_required")
        _no_links(args.repo)
        _require(args.repo.resolve(strict=True) == REPO_ROOT, "repo_must_match_validator_checkout")
        output = reserve_output(args.repo, args.output)
    except (OSError, ValueError):
        print("FAIL: forward-source path validation.", file=sys.stderr)
        return 1
    try:
        report = validate_forward_sources(args.repo)
    except Exception:
        # Do not echo decoder exceptions: their messages can contain input text.
        report = {"schema_version": SCHEMA_VERSION, "passed": False, "failure_count": 1}
    with output.open("x", encoding="utf-8", newline="\n") as stream:
        json.dump(report, stream, ensure_ascii=True, indent=2)
        stream.write("\n")
    print("PASS: forward-source checks." if report["passed"] else "FAIL: forward-source checks.")
    return 0 if report["passed"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
