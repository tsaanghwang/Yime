from os import PathLike
from typing import Callable, Literal, Protocol, cast

from .backup import create_timestamped_backup, prune_backup_files
from .charfilter import is_allowed_code_char, is_pua_char
from .pinyin_normalizer import (
    PinyinNormalizer,
    normalize_dict_existing_only,
    normalize_dict_with_supplements,
    normalize_existing_pinyin_dict,
    normalize_one,
    normalize_pinyin,
    normalize_pinyin_file,
    process_pinyin_dict,
)
from .marked_pinyin import marked_pinyin_to_numeric, marked_syllable_to_numeric
from .pinyin_zhuyin import PinyinZhuyinConverter
from . import reverse_key_value_pairs as _reverse_key_value_pairs_module


class _ReverseKeyValuePairsModule(Protocol):
    reverse_key_value_pairs: Callable[
        [str | PathLike[str], str | PathLike[str]],
        tuple[Literal[True], int, int, int]
        | tuple[Literal[False], Literal[0], Literal[0], Literal[0]],
    ]


_typed_reverse_key_value_pairs_module = cast(
    _ReverseKeyValuePairsModule, _reverse_key_value_pairs_module
)

reverse_key_value_pairs: Callable[
    [str | PathLike[str], str | PathLike[str]],
    tuple[Literal[True], int, int, int]
    | tuple[Literal[False], Literal[0], Literal[0], Literal[0]],
] = _typed_reverse_key_value_pairs_module.reverse_key_value_pairs

__all__ = [
    "PinyinNormalizer",
    "PinyinZhuyinConverter",
    "create_timestamped_backup",
    "prune_backup_files",
    "is_allowed_code_char",
    "is_pua_char",
    "marked_pinyin_to_numeric",
    "marked_syllable_to_numeric",
    "reverse_key_value_pairs",
    "normalize_dict_existing_only",
    "normalize_dict_with_supplements",
    "normalize_existing_pinyin_dict",
    "normalize_one",
    "normalize_pinyin",
    "normalize_pinyin_file",
    "process_pinyin_dict",
]
