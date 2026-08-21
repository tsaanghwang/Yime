import argparse
import json
import sys
from pathlib import Path
from typing import Any

ROOT = Path(__file__).resolve().parent.parent
if str(ROOT) not in sys.path:
    sys.path.insert(0, str(ROOT))

from yime.utils.yinyuan_id_chain import load_shared_layout_groups  # noqa: E402


DEFAULT_LAYOUT = ROOT / "internal_data" / "manual_key_layout.json"
DEFAULT_SYMBOLS = ROOT / "internal_data" / "key_to_symbol.json"
DEFAULT_OUTPUT = ROOT / "internal_data" / "manual_key_layout.resolved.json"


def load_json(path: Path) -> Any:
    with path.open("r", encoding="utf-8") as handle:
        return json.load(handle)


def validate_layers(layers: list[dict[str, Any]], key_to_symbol: dict[str, str]) -> list[dict[str, Any]]:
    seen_slots: dict[tuple[Any, Any], Any] = {}
    seen_yinyuan_ids: dict[str, dict[str, Any]] = {}
    resolved_layers: list[dict[str, Any]] = []

    for item in layers:
        physical_key = item["physical_key"]
        output_layer = item["output_layer"]
        slot_key = (physical_key, output_layer)
        if slot_key in seen_slots:
            raise ValueError(
                f"Duplicate physical slot: physical_key={physical_key}, output_layer={output_layer}"
            )
        seen_slots[slot_key] = item["order"]

        yinyuan_id = item.get("yinyuan_id")
        literal_char = item.get("literal_char")
        resolved_item = dict(item)

        if literal_char is not None:
            native_literal = " " if physical_key == "space" else item.get("display_label")
            if literal_char != native_literal:
                raise ValueError(
                    "Relocated literal_char is not allowed: "
                    f"physical_key={physical_key}, output_layer={output_layer}, "
                    f"display_label={item.get('display_label')!r}, literal_char={literal_char!r}"
                )

        if yinyuan_id is None:
            resolved_item["symbol_char"] = None
            resolved_item["symbol_codepoint"] = None
            resolved_item["symbol_category"] = None
        else:
            if yinyuan_id not in key_to_symbol:
                raise ValueError(f"Unknown yinyuan_id: {yinyuan_id}")
            if yinyuan_id in seen_yinyuan_ids:
                previous_slot = seen_yinyuan_ids[yinyuan_id]
                raise ValueError(
                    "Duplicate yinyuan_id assignment: "
                    f"yinyuan_id={yinyuan_id} is already assigned to "
                    f"physical_key={previous_slot['physical_key']}, output_layer={previous_slot['output_layer']}"
                )
            seen_yinyuan_ids[yinyuan_id] = {
                "physical_key": physical_key,
                "output_layer": output_layer,
            }
            symbol_char = key_to_symbol[yinyuan_id]
            resolved_item["symbol_char"] = symbol_char
            resolved_item["symbol_codepoint"] = f"U+{ord(symbol_char):06X}"
            resolved_item["symbol_category"] = "noise" if yinyuan_id.startswith("N") else "musical"

        if literal_char is None:
            resolved_item["literal_codepoint"] = None
        else:
            resolved_item["literal_codepoint"] = f"U+{ord(literal_char):04X}"

        resolved_char = resolved_item["symbol_char"] if yinyuan_id is not None else literal_char
        if resolved_char is None:
            resolved_item["resolved_char"] = None
            resolved_item["resolved_codepoint"] = None
            resolved_item["resolved_category"] = None
        else:
            resolved_item["resolved_char"] = resolved_char
            resolved_item["resolved_codepoint"] = f"U+{ord(resolved_char):06X}" if ord(resolved_char) > 0xFFFF else f"U+{ord(resolved_char):04X}"
            resolved_item["resolved_category"] = resolved_item["symbol_category"] if yinyuan_id is not None else "literal"

        resolved_layers.append(resolved_item)

    return resolved_layers


def build_resolved_layout(layout_data: dict[str, Any], key_to_symbol: dict[str, str]) -> dict[str, Any]:
    metadata: dict[str, Any] = dict(layout_data.get("metadata", {}))
    metadata["resolved_from"] = "internal_data/manual_key_layout.json + internal_data/key_to_symbol.json"
    metadata["resolved_output"] = "internal_data/manual_key_layout.resolved.json"

    layers: list[dict[str, Any]] = layout_data.get("layers", [])
    resolved_layers = validate_layers(layers, key_to_symbol)
    shared_groups = load_shared_layout_groups(layout_data)
    primary_ids = {
        str(item.get("yinyuan_id") or "")
        for item in resolved_layers
        if item.get("yinyuan_id")
    }
    for owner, members in shared_groups.items():
        if owner not in primary_ids:
            raise ValueError(f"Shared-key owner is not assigned: {owner}")
        for member in members:
            if member not in key_to_symbol:
                raise ValueError(f"Unknown shared yinyuan_id: {member}")
            if member != owner and member in primary_ids:
                raise ValueError(f"Shared-key member also owns a physical slot: {member}")

    return {
        "metadata": metadata,
        "stats": {
            "total_slots": len(resolved_layers),
            "assigned_slots": sum(
                1
                for item in resolved_layers
                if item["yinyuan_id"] is not None or item.get("literal_char") is not None
            ),
            "unassigned_slots": sum(
                1
                for item in resolved_layers
                if item["yinyuan_id"] is None and item.get("literal_char") is None
            ),
            "assigned_yinyuan_ids": len(primary_ids) + sum(
                len(members) - 1 for members in shared_groups.values()
            ),
        },
        "shared_yinyuan_key_groups": layout_data.get("shared_yinyuan_key_groups", []),
        "layers": resolved_layers,
    }


def main() -> None:
    parser = argparse.ArgumentParser(description="Resolve manual key layout to PUA chars and codepoints.")
    parser.add_argument("--layout", type=Path, default=DEFAULT_LAYOUT, help=f"Manual layout JSON path. Default: {DEFAULT_LAYOUT}")
    parser.add_argument("--symbols", type=Path, default=DEFAULT_SYMBOLS, help=f"key_to_symbol JSON path. Default: {DEFAULT_SYMBOLS}")
    parser.add_argument("--output", type=Path, default=DEFAULT_OUTPUT, help=f"Resolved output path. Default: {DEFAULT_OUTPUT}")
    args = parser.parse_args()

    layout_data = load_json(args.layout)
    key_to_symbol = load_json(args.symbols)
    resolved = build_resolved_layout(layout_data, key_to_symbol)

    args.output.parent.mkdir(parents=True, exist_ok=True)
    with args.output.open("w", encoding="utf-8") as handle:
        json.dump(resolved, handle, ensure_ascii=False, indent=2)

    print(f"Resolved manual layout written to {args.output}")


if __name__ == "__main__":
    main()
