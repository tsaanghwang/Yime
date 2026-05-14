from __future__ import annotations

import argparse
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parent.parent
if str(ROOT) not in sys.path:
    sys.path.insert(0, str(ROOT))

from syllable.analysis.ganyin_encoder import GanyinEncoder
from syllable.analysis.shouyin_encoder import ShouyinEncoder
from syllable.analysis.yinjie_encoder import YinjieEncoder
from yime.reverse_key_value_pairs import reverse_key_value_pairs


DEFAULT_CODE_PINYIN_OUTPUT = ROOT / "yime" / "code_pinyin.json"


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Rebuild the current encoding artifacts used by the input method."
    )
    parser.add_argument(
        "--skip-code-pinyin",
        action="store_true",
        help="Skip regenerating yime/code_pinyin.json from syllable/codec/yinjie_code.json.",
    )
    return parser.parse_args()


def rebuild_shouyin_assets() -> None:
    print("[1/4] rebuild shouyin runtime assets")
    ShouyinEncoder().generate_encoding_files()


def rebuild_ganyin_assets() -> None:
    print("[2/4] rebuild ganyin runtime assets")
    GanyinEncoder().generate_encoding_files()


def rebuild_yinjie_codebook() -> Path:
    print("[3/4] rebuild syllable codebook")
    output_path = YinjieEncoder().generate_encoding_files()
    print(f"- yinjie_code: {output_path}")
    return output_path


def rebuild_code_pinyin(input_path: Path, output_path: Path) -> None:
    print("[4/4] rebuild reverse code map")
    success, original_count, new_count, merge_count = reverse_key_value_pairs(
        input_path,
        output_path,
    )
    if not success:
        raise RuntimeError("failed to rebuild yime/code_pinyin.json")

    print(f"- code_pinyin: {output_path}")
    print(f"- source_entries: {original_count}")
    print(f"- rebuilt_entries: {new_count}")
    print(f"- merged_entries: {merge_count}")


def main() -> int:
    args = parse_args()

    rebuild_shouyin_assets()
    rebuild_ganyin_assets()
    yinjie_output = rebuild_yinjie_codebook()

    if not args.skip_code_pinyin:
        rebuild_code_pinyin(yinjie_output, DEFAULT_CODE_PINYIN_OUTPUT)

    print("done")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
