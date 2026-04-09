import json
from collections import Counter, defaultdict
from pathlib import Path


ROOT = Path(__file__).resolve().parent.parent
DEFAULT_YINJIE = ROOT / "yinjie_code.json"
DEFAULT_SYMBOLS = ROOT / "internal_data" / "key_to_symbol.json"
DEFAULT_OUTPUT = ROOT / "internal_data" / "shouyin_ganyin_combinability.json"


def load_json(path: Path):
    with path.open("r", encoding="utf-8") as handle:
        return json.load(handle)


def sort_symbol_keys(values):
    def sort_key(item: str):
        return item[0], int(item[1:])

    return sorted(values, key=sort_key)


def build_combinability(yinjie_code, char_to_key):
    by_noise = defaultdict(
        lambda: {
            "syllable_count": 0,
            "direct_following_counts": Counter(),
            "reachable_musicals_any_position": Counter(),
            "ganyin_sequences": Counter(),
            "example_syllables": [],
        }
    )
    by_direct_musical = defaultdict(lambda: {"noise_counts": Counter(), "example_syllables": []})

    for syllable, code in yinjie_code.items():
        if not code:
            continue

        noise_key = char_to_key.get(code[0])
        if noise_key is None or not noise_key.startswith("N"):
            continue

        musical_keys = [char_to_key[ch] for ch in code[1:] if char_to_key.get(ch, "").startswith("M")]
        if not musical_keys:
            continue

        noise_entry = by_noise[noise_key]
        noise_entry["syllable_count"] += 1

        if len(noise_entry["example_syllables"]) < 12:
            noise_entry["example_syllables"].append(syllable)

        direct_key = musical_keys[0]
        noise_entry["direct_following_counts"][direct_key] += 1
        by_direct_musical[direct_key]["noise_counts"][noise_key] += 1

        if len(by_direct_musical[direct_key]["example_syllables"]) < 12:
            by_direct_musical[direct_key]["example_syllables"].append(syllable)

        for musical_key in musical_keys:
            noise_entry["reachable_musicals_any_position"][musical_key] += 1

        noise_entry["ganyin_sequences"][tuple(musical_keys)] += 1

    return by_noise, by_direct_musical


def serialize_counter(counter: Counter):
    keys = sort_symbol_keys(counter.keys())
    return {key: counter[key] for key in keys}


def serialize_sequence_counter(counter: Counter):
    serialized = []
    for sequence, count in sorted(counter.items(), key=lambda item: (-item[1], item[0])):
        serialized.append(
            {
                "sequence": list(sequence),
                "count": count,
            }
        )
    return serialized


def build_output(yinjie_code, key_to_symbol):
    char_to_key = {value: key for key, value in key_to_symbol.items()}
    by_noise, by_direct_musical = build_combinability(yinjie_code, char_to_key)

    noise_keys = [key for key in key_to_symbol if key.startswith("N")]
    musical_keys = [key for key in key_to_symbol if key.startswith("M")]

    output = {
        "metadata": {
            "source_yinjie_code": "yinjie_code.json",
            "source_symbol_map": "internal_data/key_to_symbol.json",
            "description": "Derived combinability table from runtime syllable codes. Direct-following musical means the first Mxx immediately after Nxx in each encoded syllable.",
        },
        "summary": {
            "noise_symbol_count": len(noise_keys),
            "musical_symbol_count": len(musical_keys),
            "encoded_syllable_count": len(yinjie_code),
            "noise_symbols_with_data": len(by_noise),
            "direct_following_musicals_with_data": len(by_direct_musical),
        },
        "by_noise": {},
        "by_direct_following_musical": {},
    }

    for noise_key in sort_symbol_keys(by_noise.keys()):
        entry = by_noise[noise_key]
        output["by_noise"][noise_key] = {
            "syllable_count": entry["syllable_count"],
            "direct_following_musicals": sort_symbol_keys(entry["direct_following_counts"].keys()),
            "direct_following_counts": serialize_counter(entry["direct_following_counts"]),
            "reachable_musicals_any_position": sort_symbol_keys(entry["reachable_musicals_any_position"].keys()),
            "reachable_musicals_any_position_counts": serialize_counter(entry["reachable_musicals_any_position"]),
            "ganyin_sequences": serialize_sequence_counter(entry["ganyin_sequences"]),
            "example_syllables": entry["example_syllables"],
        }

    for musical_key in sort_symbol_keys(by_direct_musical.keys()):
        entry = by_direct_musical[musical_key]
        output["by_direct_following_musical"][musical_key] = {
            "noise_symbols": sort_symbol_keys(entry["noise_counts"].keys()),
            "noise_counts": serialize_counter(entry["noise_counts"]),
            "example_syllables": entry["example_syllables"],
        }

    return output


def main() -> None:
    yinjie_code = load_json(DEFAULT_YINJIE)
    key_to_symbol = load_json(DEFAULT_SYMBOLS)
    output = build_output(yinjie_code, key_to_symbol)

    with DEFAULT_OUTPUT.open("w", encoding="utf-8") as handle:
        json.dump(output, handle, ensure_ascii=False, indent=2)

    print(f"Combinability table written to {DEFAULT_OUTPUT}")


if __name__ == "__main__":
    main()