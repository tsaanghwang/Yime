"""变长音元模型子包：承载四元模型到变长音元模型的转换。"""

from .transform import (
    FOUR_YINYUAN_CODE_LENGTH,
    VariableLengthYinyuanResult,
    merge_adjacent_equal_yinyuan,
    to_variable_length_yinyuan_code,
    transform_full_code,
    transform_yinjie,
)

__all__ = [
    "FOUR_YINYUAN_CODE_LENGTH",
    "VariableLengthYinyuanResult",
    "merge_adjacent_equal_yinyuan",
    "to_variable_length_yinyuan_code",
    "transform_full_code",
    "transform_yinjie",
]
