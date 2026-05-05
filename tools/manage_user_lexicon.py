from __future__ import annotations

import argparse
from pathlib import Path

from yime.input_method.utils.user_lexicon import UserLexiconStore


ROOT = Path(__file__).resolve().parent.parent
USER_DB_PATH = ROOT / "yime" / "user_lexicon.db"


def print_user_lexicon_db(path: Path) -> None:
    print(f"user_lexicon_db={path}")


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        description=(
            "维护持久用户词库和调序频率。"
            "词条里的 numeric_pinyin 会自动规范空格；带数字声调的连写拼音"
            "例如 ri4ben3 也会被整理成 ri4 ben3。"
        )
    )
    parser.add_argument(
        "--db-path",
        default="",
        help="可选，指定要操作的用户词库路径；默认使用 yime/user_lexicon.db。",
    )
    subparsers = parser.add_subparsers(dest="command", required=True)

    init_db = subparsers.add_parser("init-db", help="显式创建空用户词库文件。")

    list_phrases = subparsers.add_parser("list-phrases", help="列出用户词条。")
    list_phrases.add_argument("term", nargs="?", default="", help="可选，按词语过滤。")
    list_phrases.add_argument("--like", action="store_true", help="使用模糊匹配。")
    list_phrases.add_argument("--limit", type=int, default=50, help="最多列出多少条。")

    list_recent = subparsers.add_parser("list-recent", help="列出最近更新的用户词条。")
    list_recent.add_argument("--limit", type=int, default=20, help="最多列出多少条。")

    list_freq = subparsers.add_parser("list-freq", help="列出持久调序频率。")
    list_freq.add_argument("term", nargs="?", default="", help="可选，按候选文本过滤。")
    list_freq.add_argument("--like", action="store_true", help="使用模糊匹配。")
    list_freq.add_argument("--limit", type=int, default=50, help="最多列出多少条。")

    export_data = subparsers.add_parser("export", help="导出用户词库备份。")
    export_data.add_argument("output", help="导出文件路径，例如 backups/user_lexicon.json")
    export_data.add_argument(
        "--no-frequency",
        action="store_true",
        help="只导出词条，不导出调序频率。",
    )

    import_data = subparsers.add_parser(
        "import",
        help="导入用户词库备份，并规范词条里的 numeric_pinyin 空格。",
    )
    import_data.add_argument("input", help="导入文件路径。")
    import_data.add_argument(
        "--replace-existing",
        action="store_true",
        help="导入前先清空当前用户词库和频率。",
    )
    import_data.add_argument(
        "--no-frequency",
        action="store_true",
        help="导入时忽略备份中的调序频率。",
    )

    delete_phrase = subparsers.add_parser("delete", help="删除用户词条。")
    delete_phrase.add_argument("phrase", help="要删除的词语。")

    reset_freq = subparsers.add_parser("reset-freq", help="重置持久调序频率。")
    reset_freq.add_argument("text", nargs="?", default="", help="可选，按候选文本重置。")
    reset_freq.add_argument("--lookup-code", default="", help="可选，按 lookup_code 进一步限定。")

    stats = subparsers.add_parser("stats", help="输出用户词库统计信息。")
    stats.add_argument("--top", type=int, default=10, help="最多显示多少条高频记录。")

    subparsers.add_parser(
        "check",
        help="检查用户词库中可自动修复的问题，包括 numeric_pinyin 的连写规范化。",
    )
    subparsers.add_parser(
        "repair-phrases",
        help="修复用户词条中的空字段、错误编码、连写 numeric_pinyin 和重复词条。",
    )
    subparsers.add_parser("repair-frequency", help="修复持久调序频率中的空键、非正频率和重复记录。")
    subparsers.add_parser("repair-meta", help="修复 seed 导入元数据中的无效或过期状态。")
    subparsers.add_parser("repair-all", help="一次执行用户词条、频率和元数据修复。")

    return parser


def print_repairable_issues(store: UserLexiconStore) -> None:
    issues = store.check_repairable_issues(ROOT)
    print_user_lexicon_db(store.db_path)
    issue_count = sum(
        count
        for key, count in issues.items()
        if key not in {"user_phrase_entries", "persisted_reorder_entries", "meta_entries"}
    )
    print(f"check_result={'issues_found' if issue_count else 'clean'}")
    for key, value in issues.items():
        print(f"{key}={value}")


def print_repair_result(result_name: str, store: UserLexiconStore, result: dict[str, int]) -> None:
    print_user_lexicon_db(store.db_path)
    print(f"repair_result={result_name}")
    for key, value in result.items():
        print(f"{key}={value}")


def print_phrase_rows(store: UserLexiconStore, term: str, use_like: bool, limit: int) -> None:
    rows = store.list_phrase_entries(term, use_like=use_like, limit=limit)
    print_user_lexicon_db(store.db_path)
    print(f"user_phrase_entries={len(rows)}")
    if not rows:
        print("无结果")
        return
    for row in rows:
        print(
            f"phrase={row.phrase} numeric_pinyin={row.numeric_pinyin} marked_pinyin={row.marked_pinyin} "
            f"yime_code={row.yime_code} source_note={row.source_note} updated_at={row.updated_at}"
        )


def print_frequency_rows(store: UserLexiconStore, term: str, use_like: bool, limit: int) -> None:
    rows = store.list_candidate_frequency_entries(term, use_like=use_like, limit=limit)
    print_user_lexicon_db(store.db_path)
    print(f"persisted_reorder_entries={len(rows)}")
    if not rows:
        print("无结果")
        return
    for row in rows:
        print(
            f"candidate_text={row.text} lookup_code={row.lookup_code} persisted_reorder_frequency={row.freq} "
            f"last_recorded_at={row.last_used_at} numeric_pinyin={row.numeric_pinyin} marked_pinyin={row.marked_pinyin}"
        )


def print_recent_rows(store: UserLexiconStore, limit: int) -> None:
    rows = store.list_recent_phrase_entries(limit=limit)
    print_user_lexicon_db(store.db_path)
    print(f"recent_user_phrase_entries={len(rows)}")
    if not rows:
        print("无结果")
        return
    for row in rows:
        print(
            f"phrase={row.phrase} numeric_pinyin={row.numeric_pinyin} marked_pinyin={row.marked_pinyin} "
            f"updated_at={row.updated_at}"
        )


def print_stats(store: UserLexiconStore, top: int) -> None:
    phrase_rows = store.list_phrase_entries(limit=1_000_000)
    frequency_rows = store.list_candidate_frequency_entries(limit=max(top, 1_000_000))
    print_user_lexicon_db(store.db_path)
    print(f"user_phrase_entries={len(phrase_rows)}")
    print(f"persisted_reorder_entries={len(frequency_rows)}")
    if frequency_rows:
        print("top_persisted_reorder_entries=")
        for row in frequency_rows[:top]:
            print(
                f"  candidate_text={row.text} lookup_code={row.lookup_code} persisted_reorder_frequency={row.freq} "
                f"last_recorded_at={row.last_used_at}"
            )


def main() -> None:
    args = build_parser().parse_args()
    db_path = Path(args.db_path).resolve() if args.db_path else USER_DB_PATH
    if args.command == "init-db":
        existed = db_path.exists()
        store = UserLexiconStore(db_path)
        print_user_lexicon_db(db_path)
        print(f"init_result=created_or_opened")
        print(f"already_existed={existed}")
        print(f"user_phrase_entries={len(store.list_phrase_entries(limit=1_000_000))}")
        return

    store = UserLexiconStore(db_path)

    if args.command == "list-phrases":
        print_phrase_rows(store, args.term, args.like, args.limit)
        return
    if args.command == "list-recent":
        print_recent_rows(store, args.limit)
        return
    if args.command == "list-freq":
        print_frequency_rows(store, args.term, args.like, args.limit)
        return
    if args.command == "export":
        output_path = Path(args.output).resolve()
        store.write_export_file(output_path, include_frequency=not args.no_frequency)
        print_user_lexicon_db(store.db_path)
        print(f"export_path={output_path}")
        print(f"include_frequency={not args.no_frequency}")
        print("export_result=completed")
        return
    if args.command == "import":
        input_path = Path(args.input).resolve()
        result = store.import_file(
            input_path,
            replace_existing=args.replace_existing,
            include_frequency=not args.no_frequency,
        )
        print_user_lexicon_db(store.db_path)
        print(f"import_path={input_path}")
        print(f"replace_existing={args.replace_existing}")
        print(f"include_frequency={not args.no_frequency}")
        print(f"imported_user_phrase_entries={result['phrase_entries']}")
        print(f"imported_persisted_reorder_entries={result['candidate_frequency']}")
        return
    if args.command == "delete":
        deleted = store.delete_phrase(args.phrase)
        print_user_lexicon_db(store.db_path)
        print(f"phrase={args.phrase}")
        print(f"delete_result={'deleted' if deleted else 'not_found'}")
        return
    if args.command == "reset-freq":
        deleted_rows = store.reset_candidate_frequency(
            text=args.text or None,
            lookup_code=args.lookup_code or None,
        )
        print_user_lexicon_db(store.db_path)
        print(f"candidate_text={args.text}")
        print(f"lookup_code={args.lookup_code}")
        print(f"reset_persisted_reorder_entries={deleted_rows}")
        return
    if args.command == "stats":
        print_stats(store, args.top)
        return
    if args.command == "check":
        print_repairable_issues(store)
        return
    if args.command == "repair-phrases":
        print_repair_result("phrases_completed", store, store.repair_phrase_entries(ROOT))
        return
    if args.command == "repair-frequency":
        print_repair_result("frequency_completed", store, store.repair_candidate_frequency_entries())
        return
    if args.command == "repair-meta":
        print_repair_result("meta_completed", store, store.repair_meta_entries())
        return
    if args.command == "repair-all":
        phrase_result = store.repair_phrase_entries(ROOT)
        frequency_result = store.repair_candidate_frequency_entries()
        meta_result = store.repair_meta_entries()
        print_repair_result(
            "all_completed",
            store,
            {
                **phrase_result,
                **frequency_result,
                **meta_result,
            },
        )
        return

    raise SystemExit(f"未知命令: {args.command}")


if __name__ == "__main__":
    main()
