from __future__ import annotations

import argparse
from pathlib import Path

from yime.input_method.utils.user_lexicon import (
    UserLexiconStore,
    normalize_numeric_pinyin_syllable_spacing,
    resolve_yime_code_from_numeric_pinyin,
)


ROOT = Path(__file__).resolve().parent.parent
USER_DB_PATH = ROOT / "yime" / "user_lexicon.db"


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="向持久用户词库写入或更新词条。")
    parser.add_argument("phrase", help="要写入的词语，例如：日本、今日")
    parser.add_argument("numeric_pinyin", help="数字标调拼音，例如：ri4 ben3；也接受 ri4ben3 这种连写。")
    parser.add_argument(
        "--marked-pinyin",
        default="",
        help="标准拼音，例如：rì běn；可留空。",
    )
    parser.add_argument(
        "--yime-code",
        default="",
        help="可选，手动指定音元编码；默认按 numeric_pinyin 自动推导。",
    )
    parser.add_argument(
        "--note",
        default="manual_user_lexicon",
        help="可选备注。",
    )
    return parser.parse_args()


def main() -> None:
    args = parse_args()
    normalized_numeric = normalize_numeric_pinyin_syllable_spacing(args.numeric_pinyin)
    yime_code = args.yime_code.strip() or resolve_yime_code_from_numeric_pinyin(
        ROOT,
        normalized_numeric,
    )
    if not yime_code:
        raise SystemExit("无法根据 numeric_pinyin 自动推导音元编码，请显式传入 --yime-code。")

    store = UserLexiconStore(USER_DB_PATH)
    store.upsert_phrase(
        args.phrase,
        normalized_numeric,
        marked_pinyin=args.marked_pinyin,
        yime_code=yime_code,
        source_note=args.note,
    )

    print(f"user_lexicon_db={USER_DB_PATH}")
    print(f"phrase={args.phrase}")
    print(f"numeric_pinyin={normalized_numeric}")
    print(f"marked_pinyin={args.marked_pinyin}")
    print(f"yime_code={yime_code}")
    print("write_result=upserted")


if __name__ == "__main__":
    main()
