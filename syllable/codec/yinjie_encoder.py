"""项目根目录转发入口，统一复用包内实现。"""

from syllable.analysis.yinjie_api_manifest import YINJIE_ROOT_ENTRY_EXPORTS
from syllable.analysis.yinjie_encoder import *
from syllable.analysis.yinjie_composition import *

__all__ = YINJIE_ROOT_ENTRY_EXPORTS  # pyright: ignore[reportUnsupportedDunderAll]


if __name__ == "__main__":
    main()
