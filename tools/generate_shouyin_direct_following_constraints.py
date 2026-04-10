import json
from pathlib import Path


ROOT = Path(__file__).resolve().parent.parent
DEFAULT_INPUT = ROOT / "internal_data" / "shouyin_ganyin_combinability.json"
DEFAULT_OUTPUT = ROOT / "internal_data" / "shouyin_direct_following_constraints.json"


def load_json(path: Path):
    with path.open("r", encoding="utf-8") as handle:
        return json.load(handle)


def sort_symbol_keys(values):
    def sort_key(item: str):
        return item[0], int(item[1:])

    return sorted(values, key=sort_key)


def build_constraints(combinability_data):
    by_noise = combinability_data.get("by_noise", {})
    summary_rows = []
    output = {
        "metadata": {
            "source": "internal_data/shouyin_ganyin_combinability.json",
            "description": "Compact direct-following constraints for keyboard layout design. Each Nxx lists the Mxx values that can appear immediately after it in encoded syllables.",
        },
        "summary": {
            "noise_symbol_count": len(by_noise),
            "constraint_edges": 0,
        },
        "by_noise": {},
        "ranked_noise_by_choice_count": [],
    }

    edge_count = 0
    for noise_key in sort_symbol_keys(by_noise.keys()):
        entry = by_noise[noise_key]
        direct_following = entry.get("direct_following_musicals", [])
        direct_counts = entry.get("direct_following_counts", {})
        edge_count += len(direct_following)

        sorted_choices = sorted(
            direct_following,
            key=lambda musical_key: (-direct_counts[musical_key], musical_key),
        )

        output["by_noise"][noise_key] = {
            "choice_count": len(direct_following),
            "choices": direct_following,
            "choices_ranked_by_frequency": sorted_choices,
            "choice_counts": {musical_key: direct_counts[musical_key] for musical_key in sorted_choices},
            "example_syllables": entry.get("example_syllables", [])[:8],
        }

        summary_rows.append(
            {
                "noise": noise_key,
                "choice_count": len(direct_following),
                "top_choices": sorted_choices[:6],
            }
        )

    output["summary"]["constraint_edges"] = edge_count
    output["ranked_noise_by_choice_count"] = sorted(
        summary_rows,
        key=lambda row: (row["choice_count"], row["noise"]),
    )
    return output


def main() -> None:
    combinability_data = load_json(DEFAULT_INPUT)
    output = build_constraints(combinability_data)

    with DEFAULT_OUTPUT.open("w", encoding="utf-8") as handle:
        json.dump(output, handle, ensure_ascii=False, indent=2)

    print(f"Direct-following constraints written to {DEFAULT_OUTPUT}")


if __name__ == "__main__":
    main()