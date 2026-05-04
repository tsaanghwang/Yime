from __future__ import annotations

import argparse
import json
import shutil
import tempfile
from pathlib import Path

from yime.input_method.app_base import BaseInputMethodApp
from yime.input_method.utils.user_lexicon import UserLexiconStore


ROOT = Path(__file__).resolve().parent.parent
DEFAULT_SEED_PATH = ROOT / "yime" / "user_lexicon_seed.json"


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="验收安装包侧 seed 用户词库的首次启动自动导入流程。"
    )
    parser.add_argument(
        "--seed-path",
        default=str(DEFAULT_SEED_PATH),
        help="要模拟打包进安装目录的 seed 文件路径。",
    )
    parser.add_argument(
        "--keep-temp",
        action="store_true",
        help="保留临时安装目录，便于人工检查。",
    )
    return parser.parse_args()


def require(condition: bool, message: str) -> None:
    if not condition:
        raise SystemExit(message)


def build_probe_app(app_dir: Path) -> BaseInputMethodApp:
    app = BaseInputMethodApp.__new__(BaseInputMethodApp)
    app.user_db_path = app_dir / "user_lexicon.db"
    app.user_lexicon_seed_path = app_dir / "user_lexicon_seed.json"
    app.user_lexicon_store = UserLexiconStore(app.user_db_path)
    return app


def run_seed_import(app_dir: Path) -> tuple[dict[str, int], UserLexiconStore]:
    app = build_probe_app(app_dir)
    result = BaseInputMethodApp._maybe_import_seed_user_lexicon(app)
    return result, app.user_lexicon_store


def copy_seed(seed_path: Path, app_dir: Path) -> Path:
    app_dir.mkdir(parents=True, exist_ok=True)
    copied_seed_path = app_dir / "user_lexicon_seed.json"
    shutil.copy2(seed_path, copied_seed_path)
    return copied_seed_path


def count_seed_phrases(seed_path: Path) -> int:
    payload = json.loads(seed_path.read_text(encoding="utf-8"))
    phrase_entries = payload.get("phrase_entries") or []
    return len(phrase_entries)


def verify_imported_store(store: UserLexiconStore, expected_phrase_count: int) -> str:
    phrase_rows = store.list_phrase_entries(limit=1_000_000)
    meta_value = store.get_meta("seed_import_completed")
    require(len(phrase_rows) == expected_phrase_count, "seed 导入后的词条数不符合预期")
    require(store.has_user_data(), "seed 导入后用户词库仍为空")
    require(meta_value.startswith("imported:"), "seed 导入完成标记缺失")
    return meta_value


def scenario_missing_db(seed_path: Path, install_root: Path, expected_phrase_count: int) -> None:
    app_dir = install_root / "scenario_missing_db" / "yime"
    copied_seed_path = copy_seed(seed_path, app_dir)
    result, store = run_seed_import(app_dir)
    require(copied_seed_path.exists(), "未成功复制 seed 文件到模拟安装目录")
    require(store.db_path.exists(), "首次启动后未创建 user_lexicon.db")
    require(result["phrase_entries"] == expected_phrase_count, "无库首次启动没有完整导入 seed 词条")
    meta_value = verify_imported_store(store, expected_phrase_count)
    print(f"[OK] scenario_missing_db imported={result['phrase_entries']} meta={meta_value}")


def scenario_precreated_empty_db(
    seed_path: Path,
    install_root: Path,
    expected_phrase_count: int,
) -> None:
    app_dir = install_root / "scenario_precreated_empty_db" / "yime"
    copy_seed(seed_path, app_dir)
    UserLexiconStore(app_dir / "user_lexicon.db")
    result, store = run_seed_import(app_dir)
    require(result["phrase_entries"] == expected_phrase_count, "空库首次启动没有完整导入 seed 词条")
    meta_value = verify_imported_store(store, expected_phrase_count)
    print(
        f"[OK] scenario_precreated_empty_db imported={result['phrase_entries']} meta={meta_value}"
    )


def scenario_second_launch_no_reimport(
    seed_path: Path,
    install_root: Path,
    expected_phrase_count: int,
) -> None:
    app_dir = install_root / "scenario_second_launch_no_reimport" / "yime"
    copy_seed(seed_path, app_dir)
    first_result, first_store = run_seed_import(app_dir)
    first_meta = verify_imported_store(first_store, expected_phrase_count)
    second_result, second_store = run_seed_import(app_dir)
    second_phrase_rows = second_store.list_phrase_entries(limit=1_000_000)
    second_meta = second_store.get_meta("seed_import_completed")
    require(
        first_result["phrase_entries"] == expected_phrase_count,
        "第二次启动场景的首次导入未成功",
    )
    require(
        second_result == {"phrase_entries": 0, "candidate_frequency": 0},
        "第二次启动不应重复导入 seed",
    )
    require(len(second_phrase_rows) == expected_phrase_count, "第二次启动后词条数发生意外变化")
    require(second_meta == first_meta, "第二次启动不应改写已完成的 seed 标记")
    print(f"[OK] scenario_second_launch_no_reimport imported_once meta={second_meta}")


def main() -> None:
    args = parse_args()
    seed_path = Path(args.seed_path).resolve()
    require(seed_path.exists(), f"seed 文件不存在: {seed_path}")

    expected_phrase_count = count_seed_phrases(seed_path)
    require(expected_phrase_count > 0, "seed 文件中没有 phrase_entries，无法验收首次导入流程")

    with tempfile.TemporaryDirectory(prefix="yime-seed-acceptance-") as temp_dir:
        install_root = Path(temp_dir)
        print(f"seed_path={seed_path}")
        print(f"temp_install_root={install_root}")

        scenario_missing_db(seed_path, install_root, expected_phrase_count)
        scenario_precreated_empty_db(seed_path, install_root, expected_phrase_count)
        scenario_second_launch_no_reimport(seed_path, install_root, expected_phrase_count)

        if args.keep_temp:
            preserved_dir = install_root.parent / f"{install_root.name}-kept"
            if preserved_dir.exists():
                shutil.rmtree(preserved_dir)
            shutil.copytree(install_root, preserved_dir)
            print(f"kept_temp_install_root={preserved_dir}")

        print("[OK] seed install flow acceptance passed")


if __name__ == "__main__":
    main()
