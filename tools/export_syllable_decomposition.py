"""Export the exhaustive syllable decomposition table used by the Windows inspector."""

from __future__ import annotations

import argparse
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))

from yime.utils.syllable_decomposition_audit import (  # noqa: E402
    DEFAULT_CHAR_SOURCE_PATH,
    DEFAULT_INVENTORY_PATH,
    DEFAULT_OMISSION_OUTPUT_PATH,
    DEFAULT_OUTPUT_PATH,
    export_syllable_decomposition_tsv,
    export_syllable_omissions_tsv,
)
from yime.utils.syllable_encoding_provenance import (  # noqa: E402
    DEFAULT_PHRASE_SOURCE_PATH,
    DEFAULT_PROVENANCE_OUTPUT_PATH,
    export_syllable_encoding_provenance_tsv,
)


def main() -> None:
    parser = argparse.ArgumentParser(description="Export all canonical Pinyin decomposition stages.")
    parser.add_argument("--inventory", type=Path, default=DEFAULT_INVENTORY_PATH)
    parser.add_argument("--output", type=Path, default=DEFAULT_OUTPUT_PATH)
    parser.add_argument("--omissions-output", type=Path, default=DEFAULT_OMISSION_OUTPUT_PATH)
    parser.add_argument("--provenance-output", type=Path, default=DEFAULT_PROVENANCE_OUTPUT_PATH)
    parser.add_argument("--char-source", type=Path, default=DEFAULT_CHAR_SOURCE_PATH)
    parser.add_argument("--phrase-source", type=Path, default=DEFAULT_PHRASE_SOURCE_PATH)
    args = parser.parse_args()
    count = export_syllable_decomposition_tsv(args.output, inventory_path=args.inventory)
    omissions = export_syllable_omissions_tsv(
        args.omissions_output,
        inventory_path=args.inventory,
        char_source_path=args.char_source,
    )
    provenance = export_syllable_encoding_provenance_tsv(
        args.inventory,
        args.provenance_output,
        char_source_path=args.char_source,
        phrase_source_path=args.phrase_source,
    )
    print(f"Exported {count} syllable decomposition rows to {args.output}")
    grouped: dict[str, int] = {}
    for row in omissions:
        grouped[row.status] = grouped.get(row.status, 0) + 1
    print(f"Exported {len(omissions)} omission rows to {args.omissions_output}")
    for status, status_count in sorted(grouped.items()):
        print(f"  {status}: {status_count}")
    print(f"Exported {len(provenance)} encoding provenance rows to {args.provenance_output}")


if __name__ == "__main__":
    main()
