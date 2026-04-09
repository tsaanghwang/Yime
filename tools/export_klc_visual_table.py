from __future__ import annotations

import json
from pathlib import Path


ROOT = Path(__file__).resolve().parent.parent
LAYOUT_PATH = ROOT / "internal_data" / "manual_key_layout.resolved.json"
OUTPUT_PATH = ROOT / "internal_data" / "klc_layout_visual_table.md"

ROW_ORDER = ["number", "top", "home", "bottom"]
ROW_KEYS = {
    "number": ["`", "1", "2", "3", "4", "5", "6", "7", "8", "9", "0", "-", "="],
    "top": ["q", "w", "e", "r", "t", "y", "u", "i", "o", "p", "[", "]", "\\"],
    "home": ["a", "s", "d", "f", "g", "h", "j", "k", "l", ";", "'"],
    "bottom": ["z", "x", "c", "v", "b", "n", "m", ",", ".", "/"],
}


def load_layout() -> dict:
    return json.loads(LAYOUT_PATH.read_text(encoding="utf-8"))


def build_lookup(layout: dict) -> dict[tuple[str, str], dict]:
    return {
        (entry["physical_key"], entry["output_layer"]): entry
        for entry in layout["layers"]
    }


def format_cell(entry: dict | None) -> str:
    if not entry:
        return ""
    if entry.get("symbol_key"):
        return f"{entry['symbol_key']} {entry['symbol_codepoint']}"
    if entry.get("literal_char"):
        return f"{entry['literal_char']} {entry['literal_codepoint']}"
    return ""


def render_grid(lookup: dict[tuple[str, str], dict], layer: str) -> list[str]:
    lines: list[str] = []
    for row_name in ROW_ORDER:
        keys = ROW_KEYS[row_name]
        lines.append(f"### {row_name.capitalize()} Row {layer.capitalize()}")
        lines.append("| Key | Value |")
        lines.append("| --- | --- |")
        for key in keys:
            lines.append(f"| {key} | {format_cell(lookup.get((key, layer)))} |")
        lines.append("")
    return lines


def render_category_table(layout: dict, category: str) -> list[str]:
    lines = [f"## {category.capitalize()} Only", "| Key | Layer | Symbol | Codepoint |", "| --- | --- | --- | --- |"]
    for entry in layout["layers"]:
        if entry.get("resolved_category") != category:
            continue
        lines.append(
            f"| {entry['physical_key']} | {entry['output_layer']} | {entry.get('symbol_key') or entry.get('literal_char')} | {entry['resolved_codepoint']} |"
        )
    lines.append("")
    return lines


def render_literal_table(layout: dict) -> list[str]:
    lines = ["## Literal Only", "| Key | Layer | Value | Codepoint |", "| --- | --- | --- | --- |"]
    for entry in layout["layers"]:
        if entry.get("resolved_category") != "literal":
            continue
        lines.append(
            f"| {entry['physical_key']} | {entry['output_layer']} | {entry['literal_char']} | {entry['literal_codepoint']} |"
        )
    lines.append("")
    return lines


def main() -> None:
    layout = load_layout()
    lookup = build_lookup(layout)

    lines = [
        "# KLC Visual Table",
        "",
        "来源：`internal_data/manual_key_layout.resolved.json`",
        "",
        "说明：默认按标准 48 键观察，不包含 `DECIMAL`。单元格显示 `symbol_key + codepoint`。",
        "",
        "## Summary",
        f"- Assigned slots: {layout['stats']['assigned_slots']}",
        f"- Unassigned slots: {layout['stats']['unassigned_slots']}",
        "",
        "## Base Layer",
        "",
    ]
    lines.extend(render_grid(lookup, "base"))
    lines.append("## Shift Layer")
    lines.append("")
    lines.extend(render_grid(lookup, "shift"))
    lines.append("## AltGr Layer")
    lines.append("")
    lines.extend(render_grid(lookup, "altgr"))
    lines.extend(render_literal_table(layout))
    lines.extend(render_category_table(layout, "noise"))
    lines.extend(render_category_table(layout, "musical"))

    OUTPUT_PATH.write_text("\n".join(lines), encoding="utf-8")
    print(f"Wrote {OUTPUT_PATH.relative_to(ROOT)}")


if __name__ == "__main__":
    main()
