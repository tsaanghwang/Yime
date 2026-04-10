import argparse
import json
from pathlib import Path


ROOT = Path(__file__).resolve().parent.parent
DEFAULT_LAYOUT = ROOT / "internal_data" / "manual_key_layout.json"
DEFAULT_SYMBOLS = ROOT / "internal_data" / "key_to_symbol.json"
DEFAULT_OUTPUT = ROOT / "internal_data" / "manual_key_layout.resolved.json"


def load_json(path: Path):
    with path.open("r", encoding="utf-8") as handle:
        return json.load(handle)


def validate_layers(layers, key_to_symbol):
    seen_slots = {}
    seen_symbol_keys = {}
    resolved_layers = []

    for item in layers:
        physical_key = item["physical_key"]
        output_layer = item["output_layer"]
        slot_key = (physical_key, output_layer)
        if slot_key in seen_slots:
            raise ValueError(
                f"Duplicate physical slot: physical_key={physical_key}, output_layer={output_layer}"
            )
        seen_slots[slot_key] = item["order"]

        symbol_key = item.get("symbol_key")
        literal_char = item.get("literal_char")
        resolved_item = dict(item)

        if symbol_key is None:
            resolved_item["symbol_char"] = None
            resolved_item["symbol_codepoint"] = None
            resolved_item["symbol_category"] = None
        else:
            if symbol_key not in key_to_symbol:
                raise ValueError(f"Unknown symbol_key: {symbol_key}")
            if symbol_key in seen_symbol_keys:
                previous_slot = seen_symbol_keys[symbol_key]
                raise ValueError(
                    "Duplicate symbol_key assignment: "
                    f"symbol_key={symbol_key} is already assigned to "
                    f"physical_key={previous_slot['physical_key']}, output_layer={previous_slot['output_layer']}"
                )
            seen_symbol_keys[symbol_key] = {
                "physical_key": physical_key,
                "output_layer": output_layer,
            }
            symbol_char = key_to_symbol[symbol_key]
            resolved_item["symbol_char"] = symbol_char
            resolved_item["symbol_codepoint"] = f"U+{ord(symbol_char):06X}"
            resolved_item["symbol_category"] = "noise" if symbol_key.startswith("N") else "musical"

        if literal_char is None:
            resolved_item["literal_codepoint"] = None
        else:
            resolved_item["literal_codepoint"] = f"U+{ord(literal_char):04X}"

        resolved_char = resolved_item["symbol_char"] if symbol_key is not None else literal_char
        if resolved_char is None:
            resolved_item["resolved_char"] = None
            resolved_item["resolved_codepoint"] = None
            resolved_item["resolved_category"] = None
        else:
            resolved_item["resolved_char"] = resolved_char
            resolved_item["resolved_codepoint"] = f"U+{ord(resolved_char):06X}" if ord(resolved_char) > 0xFFFF else f"U+{ord(resolved_char):04X}"
            resolved_item["resolved_category"] = resolved_item["symbol_category"] if symbol_key is not None else "literal"

        resolved_layers.append(resolved_item)

    return resolved_layers


def build_resolved_layout(layout_data, key_to_symbol):
    metadata = dict(layout_data.get("metadata", {}))
    metadata["resolved_from"] = "internal_data/manual_key_layout.json + internal_data/key_to_symbol.json"
    metadata["resolved_output"] = "internal_data/manual_key_layout.resolved.json"

    layers = layout_data.get("layers", [])
    resolved_layers = validate_layers(layers, key_to_symbol)

    return {
        "metadata": metadata,
        "stats": {
            "total_slots": len(resolved_layers),
            "assigned_slots": sum(
                1
                for item in resolved_layers
                if item["symbol_key"] is not None or item.get("literal_char") is not None
            ),
            "unassigned_slots": sum(
                1
                for item in resolved_layers
                if item["symbol_key"] is None and item.get("literal_char") is None
            ),
        },
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
