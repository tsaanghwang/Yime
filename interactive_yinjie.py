"""项目根目录交互入口，统一复用包内实现。"""

from syllable.analysis.slice.interactive_yinjie_session import interactive_encoder
from syllable.analysis.slice.yinjie_api_manifest import YINJIE_INTERACTIVE_ENTRY_EXPORTS
from syllable.analysis.slice.yinjie_composition import run_default_interactive_session


def main(input_reader=input) -> None:
    run_default_interactive_session(input_reader=input_reader)


__all__ = YINJIE_INTERACTIVE_ENTRY_EXPORTS  # pyright: ignore[reportUnsupportedDunderAll]

if __name__ == "__main__":
    main()
