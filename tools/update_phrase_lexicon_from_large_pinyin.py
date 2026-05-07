from __future__ import annotations

import argparse
import shlex
import subprocess
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parent.parent
SOURCE_DB_DIR = ROOT / "internal_data" / "pinyin_source_db"
YIME_DIR = ROOT / "yime"

DEFAULT_CHAR_SOURCE = Path("C:/dev/pinyin-data/pinyin.txt")
DEFAULT_PHRASE_SOURCE = Path(
    "C:/dev/RIME-LMDG/万象双拼得由来/语料统计词频表.txt"
)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description=(
            "用外部词语拼音源重建 Yime 当前主线词库；如果来源带词频，"
            "会在导入 prototype 时写入 phrase_frequency："
            "source_pinyin.db -> prototype tables -> runtime。"
            "默认真正执行；可先用 --dry-run 看将要跑哪些命令。"
        )
    )
    parser.add_argument(
        "--char-source",
        default=str(DEFAULT_CHAR_SOURCE),
        help="单字拼音来源，默认使用 C:/dev/pinyin-data/pinyin.txt",
    )
    parser.add_argument(
        "--phrase-source",
        default=str(DEFAULT_PHRASE_SOURCE),
        help=(
            "词语拼音来源，默认使用 "
            "C:/dev/RIME-LMDG/万象双拼得由来/语料统计词频表.txt"
        ),
    )
    parser.add_argument(
        "--python",
        default=sys.executable,
        help="执行后续子命令的 Python，可显式指定虚拟环境解释器。",
    )
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="只打印将执行的命令，不真正写入数据库或导出 runtime。",
    )
    parser.add_argument(
        "--skip-validate",
        action="store_true",
        help="跳过 source_pinyin.db 校验步骤。",
    )
    parser.add_argument(
        "--skip-runtime-apply",
        action="store_true",
        help="跳过 refresh_runtime_yime_codes.py --apply；用于只更新 source/prototype 层。",
    )
    return parser.parse_args()


def build_commands(args: argparse.Namespace) -> list[tuple[str, list[str]]]:
    commands: list[tuple[str, list[str]]] = [
        (
            "build-source-db",
            [
                args.python,
                str(SOURCE_DB_DIR / "build_source_pinyin_db.py"),
                "--char-source",
                args.char_source,
                "--phrase-source",
                args.phrase_source,
            ],
        )
    ]
    if not args.skip_validate:
        commands.append(
            (
                "validate-source-db",
                [args.python, str(SOURCE_DB_DIR / "validate_source_pinyin_db.py")],
            )
        )
    commands.extend(
        [
            (
                "import-single-char",
                [args.python, str(YIME_DIR / "import_danzi_into_prototype_tables.py")],
            ),
            (
                "import-phrase",
                [args.python, str(YIME_DIR / "import_duozi_into_prototype_tables.py")],
            ),
        ]
    )
    if not args.skip_runtime_apply:
        commands.append(
            (
                "refresh-runtime",
                [args.python, str(YIME_DIR / "refresh_runtime_yime_codes.py"), "--apply"],
            )
        )
    return commands


def print_plan(commands: list[tuple[str, list[str]]]) -> None:
    print("workspace_root=", ROOT, sep="")
    for step_name, command in commands:
        quoted = " ".join(shlex.quote(part) for part in command)
        print(f"[{step_name}] {quoted}")


def main() -> int:
    args = parse_args()
    char_source = Path(args.char_source)
    phrase_source = Path(args.phrase_source)

    if not char_source.exists():
        raise FileNotFoundError(f"single-character source not found: {char_source}")
    if not phrase_source.exists():
        raise FileNotFoundError(f"phrase source not found: {phrase_source}")

    commands = build_commands(args)
    print_plan(commands)
    if args.dry_run:
        print("dry_run=true")
        return 0

    for step_name, command in commands:
        print(f"running={step_name}")
        subprocess.run(command, check=True, cwd=ROOT)

    print("result=completed")
    print(f"phrase_source={phrase_source}")
    if args.skip_runtime_apply:
        print("runtime_refresh=skipped")
    else:
        print("runtime_refresh=applied")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
