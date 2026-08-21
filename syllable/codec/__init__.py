"""音节编解码：模型全码、变长音元模型、输入省键与运行时 JSON 产物。"""

from .paths import KEY_TO_CODE_PATH, PACKAGE_ROOT, REPO_ROOT, YINJIE_CODE_PATH
from .input_shorthand import omit_middle_tone_if_same_quality_run
from .model_full_code import GanyinSlots, Yinjie, YunyinSlots
from .variable_length_yinyuan import (
    VariableLengthYinyuanResult,
    merge_adjacent_equal_yinyuan,
    to_variable_length_yinyuan_code,
    transform_full_code,
    transform_yinjie,
)
from .yinjie_decoder import (
    DEFAULT_PHONEME_REPORT,
    DEFAULT_YINYUAN_REPORT,
    YinjieDecoder,
    YinjieDecoderRunResult,
)

__all__ = [
    "DEFAULT_PHONEME_REPORT",
    "DEFAULT_YINYUAN_REPORT",
    "GanyinSlots",
    "KEY_TO_CODE_PATH",
    "PACKAGE_ROOT",
    "REPO_ROOT",
    "VariableLengthYinyuanResult",
    "merge_adjacent_equal_yinyuan",
    "omit_middle_tone_if_same_quality_run",
    "to_variable_length_yinyuan_code",
    "transform_full_code",
    "transform_yinjie",
    "YINJIE_CODE_PATH",
    "Yinjie",
    "YinjieDecoder",
    "YinjieDecoderRunResult",
    "YunyinSlots",
]
