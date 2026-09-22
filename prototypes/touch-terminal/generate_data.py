#!/usr/bin/env python3
"""Generate traceable, offline-only touch-terminal fixtures from repository data.

The keyboard source is always internal_data/manual_key_layout.json. Generated
Rime dictionaries validate demo candidates; they never supply semantic IDs.
Text-source SHA-256 values cover UTF-8 content normalized to LF (without a BOM),
so Windows and Unix checkouts produce identical artifacts. No external source,
installed input method, user-data directory or network is accessed.
"""

from __future__ import annotations

import argparse
import csv
import hashlib
import io
import json
import sys
from pathlib import Path
from typing import Any

ROOT = Path(__file__).resolve().parents[2]
HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(ROOT))

from tools.resolve_manual_key_layout import build_resolved_layout  # noqa: E402
from yime.utils.yinyuan_id_chain import (  # noqa: E402
    expected_yinyuan_ids,
    layout_projection_digest,
    load_shared_layout_groups,
    load_yinyuan_id_to_layout_key,
)

MANUAL = "internal_data/manual_key_layout.json"
SYMBOLS = "internal_data/key_to_symbol.json"
PACKAGED = "go-backend/input_methods/yime/data/yime_yinyuan_layout.json"
CATALOG = "go-backend/input_methods/yime/data/trainer/yinyuan_catalog.json"
GROUPS = "go-backend/input_methods/yime/data/trainer/yinyuan_groups.json"
DECOMPOSITION = "internal_data/yime_syllable_decomposition.tsv"
PINYIN = "internal_data/hanzi_pinyin/pinyin.txt"
DICTIONARY = "go-backend/input_methods/yime/data/yime_full.dict.yaml"
LAYOUT_SOURCES = (MANUAL, SYMBOLS, PACKAGED, CATALOG, GROUPS)
DEMO_SOURCES = (DECOMPOSITION, PINYIN, DICTIONARY)
ID_ORDER = [*(f"N{i:02d}" for i in range(1, 28)), *(f"M{i:02d}" for i in range(1, 34))]
# These select attested records, not hand-authored encodings or candidate ranks.
DEMO_SELECTIONS = (("ni3", ("你", "妳", "拟")), ("hao3", ("好", "郝")),
                   ("shi4", ("是", "事", "市", "试", "世", "士", "氏", "式", "示", "势", "视", "侍", "室")))


def text_source(path: Path) -> str:
    return path.read_text(encoding="utf-8-sig").replace("\r\n", "\n").replace("\r", "\n")


def read_json(path: Path) -> Any:
    def unique_pairs(pairs: list[tuple[str, Any]]) -> dict[str, Any]:
        result: dict[str, Any] = {}
        for key, value in pairs:
            if key in result:
                raise ValueError(f"Duplicate JSON member {key!r}: {path}")
            result[key] = value
        return result
    return json.loads(text_source(path), object_pairs_hook=unique_pairs)


def source_records(root: Path, paths: tuple[str, ...]) -> list[dict[str, str]]:
    return [{"path": path, "sha256": hashlib.sha256(text_source(root / path).encode("utf-8")).hexdigest(),
             "hashMode": "utf8-lf-no-bom"} for path in paths]


def build_layout(root: Path = ROOT) -> dict[str, Any]:
    manual = read_json(root / MANUAL)
    symbols = read_json(root / SYMBOLS)
    if set(symbols) != expected_yinyuan_ids() or any(
        not isinstance(value, str) or len(value) != 1 for value in symbols.values()
    ) or len(set(symbols.values())) != 60:
        raise ValueError("Symbol source must contain 60 unique ID/symbol pairs")
    # Reuse both existing validators: physical slots and the controlled shared IDs.
    resolved = build_resolved_layout(manual, symbols)
    mapping = load_yinyuan_id_to_layout_key(root)
    packaged = read_json(root / PACKAGED)
    if packaged.get("yinyuan_id_to_key") != mapping:
        raise ValueError("Packaged layout projection differs from the canonical manual layout")

    entries = read_json(root / CATALOG).get("entries", [])
    catalog = {entry["id"]: entry for entry in entries}
    if len(entries) != 60 or set(catalog) != expected_yinyuan_ids():
        raise ValueError("Trainer catalog must cover each of the 60 IDs exactly once")
    group_source = read_json(root / GROUPS)
    groups, memberships = [], {}
    group_ids = set()
    for group in group_source["groups"]:
        if group["id"] in group_ids:
            raise ValueError(f"Duplicate trainer group: {group['id']}")
        group_ids.add(group["id"])
        ids = group["yinyuan_ids"]
        for yinyuan_id in ids:
            if yinyuan_id in memberships or yinyuan_id not in catalog:
                raise ValueError(f"Duplicate or unknown trainer group member: {yinyuan_id}")
            memberships[yinyuan_id] = group["id"]
        groups.append({"id": group["id"], "category": group["category"], "title": group["title"],
                       "description": group.get("description", ""), "ids": ids})
    if set(memberships) != expected_yinyuan_ids():
        raise ValueError("Trainer groups do not cover all 60 IDs")

    slots = {item["yinyuan_id"]: item for item in resolved["layers"] if item["yinyuan_id"]}
    shared: dict[str, list[str]] = {}
    for owner, members in load_shared_layout_groups(manual).items():
        for member in members:
            slots[member] = slots[owner]
            shared[member] = [other for other in members if other != member]
    keys = []
    grade_labels = {"high": "高", "mid": "中", "low": "低"}
    for yinyuan_id in ID_ORDER:
        entry, slot = catalog[yinyuan_id], slots[yinyuan_id]
        grade = entry.get("tone_grade", "")
        if entry["category"] == "shouyin":
            label = entry["reference_label"]
        elif entry["category"] == "yueyin" and grade in grade_labels:
            label = f"{entry['quality_group']}·{grade_labels[grade]}"
        else:
            raise ValueError(f"Unsupported trainer semantics: {yinyuan_id}")
        keys.append({"id": yinyuan_id, "label": label, "name": entry["display_name"],
                     "category": entry["category"], "key": mapping[yinyuan_id],
                     "physicalKey": slot["physical_key"], "shift": slot["output_layer"] == "shift",
                     "sharedWith": shared.get(yinyuan_id, []), "group": memberships[yinyuan_id],
                     "symbol": symbols[yinyuan_id], "toneGrade": grade})
    return {"formatVersion": 1, "layoutId": layout_projection_digest(root),
            "description": "生成的触摸呈现：60 个独立音元 ID，沿用当前 58 个大小写敏感键码投影。",
            "sources": source_records(root, LAYOUT_SOURCES), "keys": keys,
            "categories": group_source["categories"], "groups": groups}


def tsv_rows(root: Path, path: str) -> list[tuple[int, dict[str, str]]]:
    lines = text_source(root / path).splitlines()
    numbered = [(index + 1, line) for index, line in enumerate(lines) if line and not line.startswith("#")]
    reader = csv.DictReader(io.StringIO("\n".join(line for _, line in numbered)), delimiter="\t")
    return [(numbered[index + 1][0], row) for index, row in enumerate(reader)]


def build_demo(layout: dict[str, Any], root: Path = ROOT) -> dict[str, Any]:
    mapping = {entry["id"]: entry["key"] for entry in layout["keys"]}
    decomposition = {}
    for line, row in tsv_rows(root, DECOMPOSITION):
        if row["pinyin_tone"] in decomposition:
            raise ValueError(f"Duplicate decomposition: {row['pinyin_tone']}")
        decomposition[row["pinyin_tone"]] = (line, row)
    pinyin_rows = {row["hanzi"]: (line, row) for line, row in tsv_rows(root, PINYIN)}
    wanted_texts = {text for _, candidates in DEMO_SELECTIONS for text in candidates}
    dictionary_rows: dict[tuple[str, str], tuple[int, int]] = {}
    for line_number, line in enumerate(text_source(root / DICTIONARY).splitlines(), 1):
        columns = line.split("\t")
        if len(columns) >= 3 and columns[0] in wanted_texts:
            pair = (columns[0], columns[1])
            if pair in dictionary_rows:
                raise ValueError(f"Duplicate dictionary fixture row: {pair}")
            dictionary_rows[pair] = (line_number, int(columns[2]))
    examples = []
    for pinyin_tone, selected_texts in DEMO_SELECTIONS:
        line, row = decomposition[pinyin_tone]
        ids = [row[f"{slot}_id"] for slot in ("shouyin", "huyin", "zhuyin", "moyin")]
        if row["status"] != "ok" or any(yinyuan_id not in mapping for yinyuan_id in ids):
            raise ValueError(f"Invalid admitted decomposition for {pinyin_tone}")
        code = "".join(mapping[yinyuan_id] for yinyuan_id in ids)
        if code != row["layout_code"]:
            raise ValueError(f"Decomposition layout projection drift: {pinyin_tone}")
        candidates = []
        for text in selected_texts:
            pinyin_line, pinyin_row = pinyin_rows[text]
            if row["marked_pinyin"] not in pinyin_row["readings"].split(","):
                raise ValueError(f"Unattested demo pronunciation: {text} / {row['marked_pinyin']}")
            if (text, code) not in dictionary_rows:
                raise ValueError(f"Canonical dictionary does not attest fixture: {text} / {code}")
            dictionary_line, weight = dictionary_rows[(text, code)]
            candidates.append({"id": f"{pinyin_tone}-U{ord(text):04X}", "text": text,
                               "sourceWeight": weight,
                               "provenance": [{"path": PINYIN, "line": pinyin_line},
                                              {"path": DICTIONARY, "line": dictionary_line}]})
        # This subset uses source weights solely for repeatable demo presentation.
        candidates.sort(key=lambda candidate: (-candidate["sourceWeight"], candidate["text"]))
        examples.append({"id": pinyin_tone, "label": f"{candidates[0]['text']} · {row['marked_pinyin']}",
                         "ids": ids, "code": code, "text": candidates[0]["text"],
                         "pinyin": pinyin_tone, "markedPinyin": row["marked_pinyin"],
                         "candidates": candidates,
                         "provenance": [{"path": DECOMPOSITION, "line": line}]})
    return {"formatVersion": 1, "layoutId": layout["layoutId"], "mode": "demo-fixture-only",
            "description": "三个经来源核对的演示候选子集，不是真实后端、完整词库或真实候选排序；不学习、不联网。",
            "sources": source_records(root, DEMO_SOURCES), "examples": examples}


def build_artifacts(root: Path = ROOT) -> dict[str, str]:
    layout = build_layout(root)
    demo = build_demo(layout, root)
    return {name: json.dumps(payload, ensure_ascii=False, indent=2) + "\n"
            for name, payload in (("layout.json", layout), ("demo.json", demo))}


def check_artifacts(output: Path, expected: dict[str, str]) -> list[str]:
    return [name for name, content in expected.items()
            if not (output / name).is_file() or text_source(output / name) != content]


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true", help="Fail if checked-in artifacts drift; write nothing.")
    args = parser.parse_args()
    try:
        artifacts = build_artifacts()
        output = HERE / "data"
        if args.check:
            drift = check_artifacts(output, artifacts)
            if drift:
                raise ValueError(f"Generated artifact drift: {', '.join(drift)}; run generate_data.py")
            print("PASS: 60 IDs, canonical projection, attested demo fixtures and source hashes match")
        else:
            output.mkdir(parents=True, exist_ok=True)
            for name, content in artifacts.items():
                (output / name).write_text(content, encoding="utf-8", newline="\n")
            print("Generated data/layout.json and data/demo.json from repository sources")
    except (OSError, ValueError, KeyError, TypeError) as error:
        print(f"ERROR: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
