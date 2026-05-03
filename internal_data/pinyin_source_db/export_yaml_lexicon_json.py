from __future__ import annotations

import argparse
import json
from collections import defaultdict, OrderedDict
from pathlib import Path


SCRIPT_DIR = Path(__file__).resolve().parent
WORKSPACE_ROOT = SCRIPT_DIR.parent.parent
DEFAULT_SINGLE_YAML = WORKSPACE_ROOT / "pinyin" / "hanzi_pinyin" / "hanzi_pinyin_danzi.yaml"
DEFAULT_PHRASE_YAML = WORKSPACE_ROOT / "pinyin" / "hanzi_pinyin" / "hanzi_pinyin_duozi.yaml"
DEFAULT_SINGLE_JSON = WORKSPACE_ROOT / "pinyin" / "hanzi_pinyin" / "danzi_pinyin.json"
DEFAULT_PHRASE_JSON = WORKSPACE_ROOT / "pinyin" / "hanzi_pinyin" / "duozi_pinyin.json"


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Export single-char and phrase YAML lexicon sources to JSON without touching the SQLite rebuild chain."
    )
    parser.add_argument("--single-yaml", default=str(DEFAULT_SINGLE_YAML), help="Input YAML-like TSV file for single-char entries")
    parser.add_argument("--phrase-yaml", default=str(DEFAULT_PHRASE_YAML), help="Input YAML-like TSV file for phrase entries")
    parser.add_argument("--single-json", default=str(DEFAULT_SINGLE_JSON), help="Output JSON path for single-char readings")
    parser.add_argument("--phrase-json", default=str(DEFAULT_PHRASE_JSON), help="Output JSON path for phrase readings")
    parser.add_argument("--skip-single", action="store_true", help="Skip exporting the single-char JSON")
    parser.add_argument("--skip-phrase", action="store_true", help="Skip exporting the phrase JSON")
    return parser.parse_args()


def load_yaml_lexicon(path: Path, *, expect_single_char: bool) -> OrderedDict[str, list[str]]:
    if not path.exists():
        raise FileNotFoundError(f"source file not found: {path}")

    lexicon: defaultdict[str, list[str]] = defaultdict(list)
    with path.open("r", encoding="utf-8") as handle:
        for line_number, raw_line in enumerate(handle, start=1):
            stripped = raw_line.strip()
            if not stripped or stripped.startswith("#"):
                continue

            parts = stripped.split("\t")
            if len(parts) != 2:
                raise ValueError(f"invalid line {line_number} in {path}: expected <text><TAB><pinyin>")

            text, pinyin = (part.strip() for part in parts)
            if not text or not pinyin:
                raise ValueError(f"invalid line {line_number} in {path}: empty text or pinyin")
            if expect_single_char and len(text) != 1:
                raise ValueError(f"invalid line {line_number} in {path}: expected single char, got {text!r}")
            if pinyin not in lexicon[text]:
                lexicon[text].append(pinyin)

    return OrderedDict(sorted(lexicon.items(), key=lambda item: item[0]))


def write_json(path: Path, payload: OrderedDict[str, list[str]]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(payload, ensure_ascii=False, indent=2), encoding="utf-8")


def main() -> int:
    args = parse_args()

    if not args.skip_single:
        single_payload = load_yaml_lexicon(Path(args.single_yaml), expect_single_char=True)
        write_json(Path(args.single_json), single_payload)
        print(f"single_json: {args.single_json}")
        print(f"single_rows: {len(single_payload)}")

    if not args.skip_phrase:
        phrase_payload = load_yaml_lexicon(Path(args.phrase_yaml), expect_single_char=False)
        write_json(Path(args.phrase_json), phrase_payload)
        print(f"phrase_json: {args.phrase_json}")
        print(f"phrase_rows: {len(phrase_payload)}")

    return 0


if __name__ == "__main__":
    raise SystemExit(main())