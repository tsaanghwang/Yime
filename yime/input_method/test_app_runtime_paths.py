from pathlib import Path

from yime.input_method.app_base import (
    resolve_user_data_dir,
    resolve_user_documents_dir,
    resolve_user_lexicon_exchange_dir,
)


def test_resolve_user_data_dir_defaults_to_app_dir_in_source_mode() -> None:
    app_dir = Path(r"C:\dev\Yime\yime")

    assert resolve_user_data_dir(app_dir, env={}, is_frozen=False) == app_dir


def test_resolve_user_data_dir_uses_localappdata_for_frozen_build() -> None:
    app_dir = Path(r"C:\Program Files\Yime\yime")
    env = {"LOCALAPPDATA": r"C:\Users\demo\AppData\Local"}

    assert resolve_user_data_dir(app_dir, env=env, is_frozen=True) == (
        Path(r"C:\Users\demo\AppData\Local") / "Yime"
    )


def test_resolve_user_data_dir_prefers_explicit_override() -> None:
    app_dir = Path(r"C:\Program Files\Yime\yime")
    env = {
        "LOCALAPPDATA": r"C:\Users\demo\AppData\Local",
        "YIME_USER_DATA_DIR": r"D:\Portable\YimeUserData",
    }

    assert resolve_user_data_dir(app_dir, env=env, is_frozen=True) == Path(
        r"D:\Portable\YimeUserData"
    )


def test_resolve_user_documents_dir_uses_userprofile_documents() -> None:
    assert resolve_user_documents_dir(env={"USERPROFILE": r"C:\Users\demo"}) == (
        Path(r"C:\Users\demo") / "Documents"
    )


def test_resolve_user_lexicon_exchange_dir_places_files_under_documents() -> None:
    assert resolve_user_lexicon_exchange_dir(env={"USERPROFILE": r"C:\Users\demo"}) == (
        Path(r"C:\Users\demo") / "Documents" / "Yime" / "UserLexicon"
    )
