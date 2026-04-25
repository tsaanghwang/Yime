import argparse
import json
import sys
from collections import defaultdict
from pathlib import Path
from typing import Any


ROOT = Path(__file__).resolve().parent.parent
DEFAULT_LAYOUT_MAP = ROOT / "key_to_code.json"
DEFAULT_SHOUYIN_SOURCE = ROOT / "syllable" / "analysis" / "slice" / "yinyuan" / "zaoyin_yinyuan_enhanced.json"
DEFAULT_YUEYIN_SOURCE = ROOT / "syllable" / "analysis" / "slice" / "yinyuan" / "yueyin_yinyuan_enhanced.json"
DEFAULT_SHOUYIN_RUNTIME = ROOT / "syllable" / "analysis" / "slice" / "yinyuan" / "shouyin_codepoint.json"
DEFAULT_YINYUAN_RUNTIME = ROOT / "syllable" / "analysis" / "slice" / "yinyuan" / "yinyuan_codepoint.json"
DEFAULT_GANYIN_RUNTIME = ROOT / "syllable" / "analysis" / "slice" / "yinyuan" / "ganyin_to_fixed_length_yinyuan_sequence.json"


def load_json(path: Path) -> dict[str, Any]:
    with path.open("r", encoding="utf-8") as handle:
        return json.load(handle)


def collect_duplicates(values: dict[str, str], label: str, source_name: str) -> list[str]:
    reverse: dict[str, list[str]] = defaultdict(list)
    for key, value in values.items():
        reverse[value].append(key)

    issues: list[str] = []
    for value, keys in sorted(reverse.items()):
        if len(keys) > 1:
            issues.append(
                f"{source_name}: duplicate {label} {value!r} shared by {', '.join(sorted(keys))}"
            )
    return issues


def validate_source_entries(
    source_name: str,
    source_path: Path,
    layout_map: dict[str, str],
    runtime_maps: dict[str, dict[str, str]],
) -> tuple[list[str], dict[str, str]]:
    issues: list[str] = []
    source_data = load_json(source_path)
    entries = source_data.get("entries", {})
    if not isinstance(entries, dict) or not entries:
        return [f"{source_name}: source file has no usable entries: {source_path}"], {}

    semantic_codes: dict[str, str] = {}
    runtime_chars: dict[str, str] = {}
    layout_slots: dict[str, str] = {}

    for entry_name, entry in entries.items():
        if not isinstance(entry, dict):
            issues.append(f"{source_name}: source entry is not an object: {entry_name}")
            continue

        semantic_code = entry.get("semantic_code", "")
        runtime_char = entry.get("runtime_char", "")
        layout_slot = entry.get("layout_slot", "")

        if not semantic_code:
            issues.append(f"{source_name}: missing semantic_code: {entry_name}")
        else:
            semantic_codes[entry_name] = semantic_code

        if not runtime_char:
            issues.append(f"{source_name}: missing runtime_char: {entry_name}")
        else:
            runtime_chars[entry_name] = runtime_char

        if not layout_slot:
            issues.append(f"{source_name}: missing layout_slot: {entry_name}")
        else:
            layout_slots[entry_name] = layout_slot
            mapped_char = layout_map.get(layout_slot)
            if mapped_char is None:
                issues.append(f"{source_name}: unknown layout_slot {layout_slot} for {entry_name}")
            elif runtime_char and mapped_char != runtime_char:
                issues.append(
                    f"{source_name}: layout_slot/runtime_char mismatch for {entry_name}: {layout_slot} -> {mapped_char!r}, source={runtime_char!r}"
                )

    issues.extend(collect_duplicates(semantic_codes, "semantic_code", source_name))
    issues.extend(collect_duplicates(runtime_chars, "runtime_char", source_name))
    issues.extend(collect_duplicates(layout_slots, "layout_slot", source_name))

    source_keys = set(runtime_chars)
    for runtime_name, runtime_map in runtime_maps.items():
        runtime_keys = set(runtime_map)
        missing = sorted(source_keys - runtime_keys)
        if missing:
            issues.append(f"{source_name}: missing keys in {runtime_name}: {', '.join(missing)}")

        extra = sorted(runtime_keys - source_keys)
        if extra:
            issues.append(f"{source_name}: extra keys in {runtime_name}: {', '.join(extra)}")

        for key in sorted(source_keys & runtime_keys):
            if runtime_chars[key] != runtime_map[key]:
                issues.append(
                    f"{source_name}: source/runtime mismatch for {key} in {runtime_name}: source={runtime_chars[key]!r}, runtime={runtime_map[key]!r}"
                )

    return issues, runtime_chars


def validate_ganyin_sequences(sequence_path: Path, valid_runtime_chars: set[str]) -> list[str]:
    issues: list[str] = []
    sequences = load_json(sequence_path)
    for ganyin, sequence in sequences.items():
        if not isinstance(sequence, str):
            issues.append(f"ganyin_sequence: non-string encoding for {ganyin}")
            continue
        if len(sequence) != 3:
            issues.append(f"ganyin_sequence: {ganyin} is not fixed length 3")
        for symbol in sequence:
            if symbol not in valid_runtime_chars:
                issues.append(
                    f"ganyin_sequence: {ganyin} uses unknown runtime char {symbol!r}"
                )
    return issues


def main() -> int:
    parser = argparse.ArgumentParser(
        description=(
            "Validate shouyin and ganyin sources against runtime characters and N/M layout slots. "
            "Physical VK positions are intentionally checked later, after the keyboard layout discussion settles."
        )
    )
    parser.add_argument("--layout-map", type=Path, default=DEFAULT_LAYOUT_MAP)
    parser.add_argument("--shouyin-source", type=Path, default=DEFAULT_SHOUYIN_SOURCE)
    parser.add_argument("--yueyin-source", type=Path, default=DEFAULT_YUEYIN_SOURCE)
    parser.add_argument("--shouyin-runtime", type=Path, default=DEFAULT_SHOUYIN_RUNTIME)
    parser.add_argument("--yinyuan-runtime", type=Path, default=DEFAULT_YINYUAN_RUNTIME)
    parser.add_argument("--ganyin-runtime", type=Path, default=DEFAULT_GANYIN_RUNTIME)
    args = parser.parse_args()

    layout_map = load_json(args.layout_map)
    yinyuan_runtime = load_json(args.yinyuan_runtime)

    shouyin_runtime = load_json(args.shouyin_runtime).get("首音", {})
    yueyin_runtime = yinyuan_runtime.get("yueyin", {})
    zaoyin_runtime = yinyuan_runtime.get("zaoyin", {})

    issues: list[str] = []

    shouyin_issues, _ = validate_source_entries(
        source_name="shouyin",
        source_path=args.shouyin_source,
        layout_map=layout_map,
        runtime_maps={
            "shouyin_codepoint.json": shouyin_runtime,
            "yinyuan_codepoint.json.zaoyin": zaoyin_runtime,
        },
    )
    issues.extend(shouyin_issues)

    yueyin_issues, yueyin_chars = validate_source_entries(
        source_name="yueyin",
        source_path=args.yueyin_source,
        layout_map=layout_map,
        runtime_maps={
            "yinyuan_codepoint.json.yueyin": yueyin_runtime,
        },
    )
    issues.extend(yueyin_issues)
    issues.extend(validate_ganyin_sequences(args.ganyin_runtime, set(yueyin_chars.values())))

    if issues:
        print("yinyuan source consistency validation failed")
        for issue in issues:
            print(f"- {issue}")
        return 1

    print("yinyuan source consistency validation passed")
    return 0


if __name__ == "__main__":
    sys.exit(main())
