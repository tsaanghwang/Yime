from __future__ import annotations

import json
from pathlib import Path
import sqlite3


ROOT = Path(__file__).resolve().parent.parent
RUNTIME_PATH = ROOT / "syllable_codec" / "key_to_code.json"
CANONICAL_PATH = ROOT / "internal_data" / "key_to_symbol.json"
PROJECTION_PATH = ROOT / "internal_data" / "bmp_pua_trial_projection.json"
LAYOUT_PATH = ROOT / "internal_data" / "manual_key_layout.json"
DB_PATH = ROOT / "yime" / "pinyin_hanzi.db"
SHOUYIN_PATH = ROOT / "syllable" / "analysis" / "slice" / "yinyuan" / "shouyin_codepoint.json"
YINYUAN_PATH = ROOT / "syllable" / "analysis" / "slice" / "yinyuan" / "yinyuan_codepoint.json"
OUTPUT_JSON_PATH = ROOT / "internal_data" / "slot_symbol_crosswalk.json"
OUTPUT_MD_PATH = ROOT / "internal_data" / "slot_symbol_crosswalk.md"
OUTPUT_TABLE = "slot_xw"


def load_json(path: Path) -> object:
    return json.loads(path.read_text(encoding="utf-8"))


def format_codepoint(value: str) -> str:
    width = 6 if ord(value) > 0xFFFF else 4
    return f"U+{ord(value):0{width}X}"


def build_label_index() -> dict[str, str]:
    labels: dict[str, str] = {}

    shouyin_payload = load_json(SHOUYIN_PATH)
    shouyin_map = shouyin_payload.get("首音", {})
    for label, char in shouyin_map.items():
        labels[str(char)] = str(label)

    yinyuan_payload = load_json(YINYUAN_PATH)
    for namespace in ("zaoyin", "yueyin"):
        namespace_map = yinyuan_payload.get(namespace, {})
        for label, char in namespace_map.items():
            labels[str(char)] = str(label)

    return labels


def build_physical_key_index() -> dict[str, list[str]]:
    payload = load_json(LAYOUT_PATH)
    layers = payload.get("layers", [])
    physical: dict[str, list[str]] = {}

    for entry in layers:
        if not isinstance(entry, dict):
            continue
        slot_key = entry.get("symbol_key")
        if not slot_key:
            continue
        physical_key = str(entry.get("physical_key", "")).strip()
        output_layer = str(entry.get("output_layer", "")).strip()
        display_label = str(entry.get("display_label", "")).strip()
        binding = f"{physical_key}:{output_layer}:{display_label}"
        physical.setdefault(str(slot_key), []).append(binding)

    for bindings in physical.values():
        bindings.sort()

    return physical


def build_display_label_index() -> dict[str, list[str]]:
    payload = load_json(LAYOUT_PATH)
    layers = payload.get("layers", [])
    labels: dict[str, list[str]] = {}

    for entry in layers:
        if not isinstance(entry, dict):
            continue
        slot_key = entry.get("symbol_key")
        if not slot_key:
            continue
        display_label = str(entry.get("display_label", "")).strip()
        if not display_label:
            continue
        labels.setdefault(str(slot_key), []).append(display_label)

    for items in labels.values():
        items.sort()

    return labels


def slot_sort_key(slot_key: str) -> tuple[int, int]:
    prefix = 0 if slot_key.startswith("N") else 1
    return (prefix, int(slot_key[1:]))


def build_rows() -> list[dict[str, object]]:
    runtime_map = load_json(RUNTIME_PATH)
    canonical_map = load_json(CANONICAL_PATH)
    projection_payload = load_json(PROJECTION_PATH)
    projection_map = projection_payload.get("used_mapping", {})

    label_index = build_label_index()
    physical_index = build_physical_key_index()
    display_label_index = build_display_label_index()

    slot_keys = sorted(projection_map.keys(), key=slot_sort_key)
    rows: list[dict[str, object]] = []

    for slot_key in slot_keys:
        projection_entry = projection_map.get(slot_key, {})
        runtime_char = runtime_map.get(slot_key)
        projection_char = projection_entry.get("char")
        canonical_char = canonical_map.get(slot_key)
        slot_number = projection_entry.get("slot")

        category = "initial" if slot_key.startswith("N") else "musical"
        label = label_index.get(runtime_char or "") or label_index.get(projection_char or "") or ""
        physical_keys = physical_index.get(slot_key, [])
        display_labels = display_label_index.get(slot_key, [])

        issues: list[str] = []
        if runtime_char != projection_char:
            issues.append("runtime_bmp_differs_from_projection")
        if not canonical_char:
            issues.append("missing_canonical")
        if not physical_keys:
            issues.append("unmapped_physical_key")

        layer_relation = ""
        if runtime_char and canonical_char:
            if runtime_char == canonical_char:
                layer_relation = "runtime_bmp_equals_canonical"
            else:
                layer_relation = "runtime_bmp_differs_from_canonical"

        rows.append(
            {
                "slot_key": slot_key,
                "slot_number": slot_number,
                "category": category,
                "label": label,
                "display_labels": display_labels,
                "runtime_bmp_char": runtime_char,
                "runtime_bmp_codepoint": format_codepoint(runtime_char) if runtime_char else None,
                "projection_bmp_char": projection_char,
                "projection_bmp_codepoint": projection_entry.get("codepoint"),
                "projection_matches_runtime": runtime_char == projection_char,
                "canonical_spua_b_char": canonical_char,
                "canonical_spua_b_codepoint": format_codepoint(canonical_char) if canonical_char else None,
                "layer_relation": layer_relation,
                "physical_keys": physical_keys,
                "issue_count": len(issues),
                "issues": issues,
            }
        )

    return rows


def build_payload(rows: list[dict[str, object]]) -> dict[str, object]:
    runtime_projection_mismatches = sum(1 for row in rows if not row["projection_matches_runtime"])
    bmp_canonical_differences = sum(
        1 for row in rows if row["layer_relation"] == "runtime_bmp_differs_from_canonical"
    )
    rows_with_issues = sum(1 for row in rows if row["issue_count"])
    return {
        "metadata": {
            "description": "Slot/BMP/SPUA-B/physical-key crosswalk generated from current source JSON files.",
            "runtime_source": str(RUNTIME_PATH.relative_to(ROOT)),
            "canonical_source": str(CANONICAL_PATH.relative_to(ROOT)),
            "projection_source": str(PROJECTION_PATH.relative_to(ROOT)),
            "layout_source": str(LAYOUT_PATH.relative_to(ROOT)),
            "rows": len(rows),
            "runtime_projection_mismatches": runtime_projection_mismatches,
            "bmp_canonical_differences": bmp_canonical_differences,
            "rows_with_issues": rows_with_issues,
        },
        "rows": rows,
    }


def build_markdown(rows: list[dict[str, object]], payload: dict[str, object]) -> str:
    metadata = payload["metadata"]
    lines = [
        "# Slot Symbol Crosswalk",
        "",
        f"- Rows: {metadata['rows']}",
        f"- Runtime vs projection mismatches: {metadata['runtime_projection_mismatches']}",
        f"- Runtime BMP vs canonical SPUA-B differences: {metadata['bmp_canonical_differences']}",
        f"- Rows with issues: {metadata['rows_with_issues']}",
        "",
        "| Slot | Label | Physical Key | Runtime BMP | Projection BMP | Canonical SPUA-B | Layer Relation | Issues |",
        "| --- | --- | --- | --- | --- | --- | --- | --- |",
    ]

    for row in rows:
        physical = "<br>".join(row["physical_keys"]) if row["physical_keys"] else ""
        runtime_text = ""
        if row["runtime_bmp_char"]:
            runtime_text = f"{row['runtime_bmp_char']} ({row['runtime_bmp_codepoint']})"

        projection_text = ""
        if row["projection_bmp_char"]:
            projection_text = f"{row['projection_bmp_char']} ({row['projection_bmp_codepoint']})"

        canonical_text = ""
        if row["canonical_spua_b_char"]:
            canonical_text = f"{row['canonical_spua_b_char']} ({row['canonical_spua_b_codepoint']})"

        relation = str(row["layer_relation"] or "")
        issues = ", ".join(row["issues"]) if row["issues"] else ""
        lines.append(
            f"| {row['slot_key']} | {row['label']} | {physical} | {runtime_text} | {projection_text} | {canonical_text} | {relation} | {issues} |"
        )

    return "\n".join(lines) + "\n"


def write_sqlite(rows: list[dict[str, object]]) -> None:
    conn = sqlite3.connect(DB_PATH)
    try:
        cur = conn.cursor()
        cur.execute(
            f'''
            CREATE TABLE IF NOT EXISTS {OUTPUT_TABLE} (
                s TEXT PRIMARY KEY,
                i INTEGER,
                c TEXT,
                l TEXT,
                pk TEXT,
                dl TEXT,
                r TEXT,
                p TEXT,
                a TEXT,
                nt TEXT
            )
            '''
        )
        cur.execute(f'DELETE FROM {OUTPUT_TABLE}')
        cur.executemany(
            f'''
            INSERT INTO {OUTPUT_TABLE} (s, i, c, l, pk, dl, r, p, a, nt)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            ''',
            [
                (
                    row["slot_key"],
                    row["slot_number"],
                    row["category"],
                    row["label"],
                    " | ".join(row["physical_keys"]),
                    " | ".join(row["display_labels"]),
                    row["runtime_bmp_char"],
                    row["projection_bmp_char"],
                    row["canonical_spua_b_char"],
                    ", ".join(row["issues"]),
                )
                for row in rows
            ],
        )
        conn.commit()
    finally:
        conn.close()


def main() -> None:
    rows = build_rows()
    payload = build_payload(rows)

    OUTPUT_JSON_PATH.write_text(
        json.dumps(payload, ensure_ascii=False, indent=2),
        encoding="utf-8",
    )
    OUTPUT_MD_PATH.write_text(build_markdown(rows, payload), encoding="utf-8")
    write_sqlite(rows)

    print(f"json_output: {OUTPUT_JSON_PATH}")
    print(f"markdown_output: {OUTPUT_MD_PATH}")
    print(f"sqlite_table: {DB_PATH}::{OUTPUT_TABLE}")
    print(f"rows: {payload['metadata']['rows']}")
    print(f"runtime_projection_mismatches: {payload['metadata']['runtime_projection_mismatches']}")
    print(f"bmp_canonical_differences: {payload['metadata']['bmp_canonical_differences']}")
    print(f"rows_with_issues: {payload['metadata']['rows_with_issues']}")


if __name__ == "__main__":
    main()
