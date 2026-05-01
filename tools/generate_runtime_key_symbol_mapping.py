import argparse
import json
from pathlib import Path


ROOT = Path(__file__).resolve().parent.parent
DEFAULT_OUTPUT = ROOT / "internal_data" / "yinjie_runtime_key_symbol_mapping.json"
DEFAULT_CANONICAL_OUTPUT = ROOT / "internal_data" / "key_to_symbol.json"


def load_json(path: Path):
    with path.open("r", encoding="utf-8") as handle:
        return json.load(handle)


def classify_plane(codepoint: int) -> str:
    if 0xE000 <= codepoint <= 0xF8FF:
        return "BMP Private Use Area"
    if 0xF0000 <= codepoint <= 0xFFFFD:
        return "Supplementary Private Use Area-A"
    if 0x100000 <= codepoint <= 0x10FFFD:
        return "Supplementary Private Use Area-B"
    return "Not Private Use Area"


def collect_usage(yinjie_code: dict[str, str]) -> dict[str, list[dict[str, object]]]:
    usage: dict[str, list[dict[str, object]]] = {}
    for syllable, code in yinjie_code.items():
        for position, symbol in enumerate(code, start=1):
            usage.setdefault(symbol, []).append(
                {
                    "syllable": syllable,
                    "position_in_code": position,
                    "full_code": code,
                }
            )
    return usage


def build_shouyin_entries(
    shouyin_map: dict[str, str],
    symbol_to_key: dict[str, str],
    usage: dict[str, list[dict[str, object]]],
) -> list[dict[str, object]]:
    entries: list[dict[str, object]] = []
    for shouyin, symbol in shouyin_map.items():
        codepoint = ord(symbol)
        examples = usage.get(symbol, [])[:5]
        entries.append(
            {
                "key": symbol_to_key.get(symbol),
                "symbol": symbol,
                "codepoint": f"U+{codepoint:06X}",
                "plane": classify_plane(codepoint),
                "source_type": "shouyin",
                "source_name": shouyin,
                "source_file": "syllable/analysis/slice/yinyuan/shouyin_codepoint.json",
                "used_in_yinjie_position": [1],
                "example_syllables": examples,
            }
        )
    return entries


def build_ganyin_entries(
    ganyin_map: dict[str, str],
    symbol_to_key: dict[str, str],
    usage: dict[str, list[dict[str, object]]],
) -> list[dict[str, object]]:
    aggregated: dict[str, dict[str, object]] = {}
    for ganyin, sequence in ganyin_map.items():
        for position, symbol in enumerate(sequence, start=1):
            bucket = aggregated.setdefault(
                symbol,
                {
                    "key": symbol_to_key.get(symbol),
                    "symbol": symbol,
                    "codepoint": f"U+{ord(symbol):06X}",
                    "plane": classify_plane(ord(symbol)),
                    "source_type": "ganyin",
                    "source_file": "syllable/analysis/slice/yinyuan/ganyin_to_fixed_length_yinyuan_sequence.json",
                    "used_in_yinjie_position": set(),
                    "ganyin_names": [],
                },
            )
            bucket["used_in_yinjie_position"].add(position + 1)
            names = bucket["ganyin_names"]
            if ganyin not in names:
                names.append(ganyin)

    entries: list[dict[str, object]] = []
    for symbol, entry in aggregated.items():
        examples = usage.get(symbol, [])[:5]
        entry["used_in_yinjie_position"] = sorted(entry["used_in_yinjie_position"])
        entry["ganyin_names"] = entry["ganyin_names"][:12]
        entry["example_syllables"] = examples
        entries.append(entry)

    return entries


def build_report() -> dict[str, object]:
    shouyin_path = ROOT / "syllable" / "analysis" / "slice" / "yinyuan" / "shouyin_codepoint.json"
    ganyin_path = ROOT / "syllable" / "analysis" / "slice" / "yinyuan" / "ganyin_to_fixed_length_yinyuan_sequence.json"
    key_to_code_path = ROOT / "syllable_codec" / "key_to_code.json"
    yinjie_code_path = ROOT / "syllable_codec" / "yinjie_code.json"

    shouyin_map = load_json(shouyin_path)["首音"]
    ganyin_map = load_json(ganyin_path)
    key_to_code = load_json(key_to_code_path)
    yinjie_code = load_json(yinjie_code_path)

    symbol_to_key = {symbol: key for key, symbol in key_to_code.items()}
    usage = collect_usage(yinjie_code)

    shouyin_entries = build_shouyin_entries(shouyin_map, symbol_to_key, usage)
    ganyin_entries = build_ganyin_entries(ganyin_map, symbol_to_key, usage)
    entries = sorted(shouyin_entries + ganyin_entries, key=lambda item: ord(item["symbol"]))

    return {
        "description": "Canonical runtime key-symbol mapping derived from syllable_codec/yinjie_encoder.py dependencies.",
        "source_chain": {
            "final_code_file": "syllable_codec/yinjie_code.json",
            "encoder_entry": "syllable_codec/yinjie_encoder.py -> YinjieEncoder.encode_single_yinjie()",
            "join_rule": "final code = shouyin_code + ganyin_code",
            "shouyin_runtime_source": "syllable/analysis/slice/yinyuan/shouyin_codepoint.json",
            "ganyin_runtime_source": "syllable/analysis/slice/yinyuan/ganyin_to_fixed_length_yinyuan_sequence.json",
            "key_assignment_source": "syllable_codec/key_to_code.json",
        },
        "non_runtime_reference_files": [
            {
                "path": "internal_data/key_symbol_mapping.json",
                "note": "Legacy/manual mapping file. Not read by syllable_codec/yinjie_encoder.py when generating syllable_codec/yinjie_code.json.",
            },
            {
                "path": "data_json_files/key_symbol_mapping.json",
                "note": "Legacy/manual mapping file. Not read by syllable_codec/yinjie_encoder.py when generating syllable_codec/yinjie_code.json.",
            },
            {
                "path": "tools/key_symbol_mapping.py",
                "note": "Manual generator for an older symbol set. Not part of the current yinjie_encoder runtime chain.",
            },
        ],
        "counts": {
            "unique_symbols_in_yinjie_code": len(entries),
            "shouyin_symbols": len(shouyin_entries),
            "ganyin_symbols": len(ganyin_entries),
        },
        "key_to_symbol": key_to_code,
        "entries": entries,
    }


def build_canonical_key_symbol_mapping(report: dict[str, object]) -> dict[str, str]:
    key_to_symbol = report.get("key_to_symbol", {})
    if not isinstance(key_to_symbol, dict):
        raise ValueError("report['key_to_symbol'] must be a mapping")
    return dict(key_to_symbol)


def main() -> None:
    parser = argparse.ArgumentParser(description="Generate the runtime key-symbol mapping used by syllable_codec/yinjie_encoder.py.")
    parser.add_argument(
        "--output",
        type=Path,
        default=DEFAULT_OUTPUT,
        help=f"Output JSON path. Default: {DEFAULT_OUTPUT}",
    )
    parser.add_argument(
        "--canonical-output",
        type=Path,
        default=None,
        help=(
            "Optional output path for the canonical key-symbol mapping derived from runtime data. "
            f"Suggested path: {DEFAULT_CANONICAL_OUTPUT}"
        ),
    )
    args = parser.parse_args()

    report = build_report()
    args.output.parent.mkdir(parents=True, exist_ok=True)
    with args.output.open("w", encoding="utf-8") as handle:
        json.dump(report, handle, ensure_ascii=False, indent=2)

    print(f"Generated runtime key-symbol mapping: {args.output}")

    if args.canonical_output is not None:
        canonical_mapping = build_canonical_key_symbol_mapping(report)
        args.canonical_output.parent.mkdir(parents=True, exist_ok=True)
        with args.canonical_output.open("w", encoding="utf-8") as handle:
            json.dump(canonical_mapping, handle, ensure_ascii=False, indent=2)
        print(f"Generated canonical key-symbol mapping: {args.canonical_output}")


if __name__ == "__main__":
    main()
